-- herdr-nvim-nav -- the Neovim half.
--
-- Seamless Alt+h/j/k/l across Neovim splits and the surrounding multiplexer
-- (tilish-style; this dotfiles fork). Move within Neovim's windows, and at a
-- split edge cross into the neighbouring herdr pane (or tmux pane under tmux).
--
-- Plugin-manager agnostic: `require('herdr-nvim-nav').setup{ ... }`. See the
-- README for lazy.nvim / packer / manual install snippets.

local M = {}

local uv = vim.uv or vim.loop

local DIRECTIONS = { 'left', 'down', 'up', 'right' }
local WINCMD = { left = 'h', down = 'j', up = 'k', right = 'l' }
local TMUX_DIR = { left = 'Left', down = 'Down', up = 'Up', right = 'Right' }

local defaults = {
  -- true / false forces tmux fallback on / off. nil auto-detects from $TMUX,
  -- so tmux users get it without config and herdr-only users pull in nothing.
  with_tmux = nil,

  -- lhs list per direction. Override to remap, or set a direction to {} to skip.
  -- Dotfiles default: Alt+hjkl navigate (Ctrl+hjkl is resize via herdr-splits).
  keymaps = {
    left = { '<M-h>' },
    down = { '<M-j>' },
    up = { '<M-k>' },
    right = { '<M-l>' },
  },

  -- Paths default to herdr's env vars, then its documented defaults. Rarely set.
  socket_path = nil, -- default: $HERDR_SOCKET_PATH or ~/.config/herdr/herdr.sock
  cache_dir = nil, -- default: $XDG_CACHE_HOME or ~/.cache
  herdr_bin = nil, -- default: $HERDR_BIN_PATH or "herdr" on $PATH
  socket_timeout_ms = 150,
}

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  -- Merge scalars, but replace keymaps per-direction so `right = {}` disables it
  -- (a deep merge treats {} as "no change" and would keep the default lhs list).
  local user_keymaps = opts.keymaps
  opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts)
  if user_keymaps then
    for _, dir in ipairs(DIRECTIONS) do
      if user_keymaps[dir] ~= nil then
        opts.keymaps[dir] = user_keymaps[dir]
      end
    end
  end

  -- Which multiplexer surrounds us never changes during a session, so resolve
  -- it once instead of reading the environment on every keystroke.
  local herdr_pane = vim.env.HERDR_PANE_ID
  local in_herdr = herdr_pane ~= nil and herdr_pane ~= ''

  local use_tmux = opts.with_tmux
  if use_tmux == nil then
    use_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= ''
  end

  -- Under tmux we call TmuxNavigate* ourselves for edge fallthrough. Disable
  -- vim-tmux-navigator's own maps if it is present.
  if use_tmux then
    vim.g.tmux_navigator_no_mappings = 1
  end

  -- Tell the herdr `herdr-nvim-nav` plugin that Neovim owns this pane, so its
  -- alt+h/j/k/l actions forward the chord here instead of moving panes. herdr
  -- has no equivalent of tmux's `@pane-is-vim` pane option; a marker file named
  -- after the pane lets the C action decide without spawning `herdr`/`jq`.
  local marker_owned = true

  local function marker_path()
    if not in_herdr then
      return nil
    end
    local cache = opts.cache_dir
    if cache == nil or cache == '' then
      cache = vim.env.XDG_CACHE_HOME
    end
    if cache == nil or cache == '' then
      cache = vim.env.HOME .. '/.cache'
    end
    return cache .. '/herdr/nvim-panes/' .. herdr_pane
  end

  ---@return integer|nil pid in the marker, if it names a live process
  local function live_marker_pid(path)
    local fd = io.open(path, 'r')
    if not fd then
      return nil
    end
    local pid = tonumber(fd:read('l'))
    fd:close()
    if not pid then
      return nil
    end
    local ok, alive = pcall(uv.kill, pid, 0) -- signal 0 only probes
    return (ok and alive) and pid or nil
  end

  local function claim_marker()
    local path = marker_path()
    if not path then
      return
    end
    -- Another live Neovim already claimed this pane: we are nested in its
    -- :terminal, so the marker is not ours to write or remove.
    local owner = live_marker_pid(path)
    if owner and owner ~= uv.os_getpid() then
      marker_owned = false
      return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    local fd = io.open(path, 'w')
    if fd then
      fd:write(tostring(uv.os_getpid()), '\n')
      fd:close()
    end
  end

  local function release_marker()
    if not marker_owned then
      return
    end
    local path = marker_path()
    if path then
      os.remove(path)
    end
  end

  claim_marker()
  vim.api.nvim_create_autocmd('VimResume', { callback = claim_marker })
  vim.api.nvim_create_autocmd({ 'VimSuspend', 'VimLeavePre' }, { callback = release_marker })

  -- Crossing a pane boundary used to shell out with `vim.fn.system{herdr, ...}`,
  -- which blocks the UI for a process spawn -- a median of ~10ms on this machine
  -- and a tail into the hundreds, because fork/exec here is slow and erratic.
  -- herdr's control socket answers the same request in ~0.1ms and creates no
  -- process. The spawn stays as a fallback: the wire protocol is undocumented
  -- and could move under us on an update.
  local herdr_bin = opts.herdr_bin
  if herdr_bin == nil or herdr_bin == '' then
    herdr_bin = vim.env.HERDR_BIN_PATH
  end
  if herdr_bin == nil or herdr_bin == '' then
    herdr_bin = 'herdr'
  end
  local socket = opts.socket_path
  if socket == nil or socket == '' then
    socket = vim.env.HERDR_SOCKET_PATH
  end
  if socket == nil or socket == '' then
    socket = vim.fn.expand('~/.config/herdr/herdr.sock')
  end

  -- Newline-delimited JSON. The body only varies by direction, so encode the
  -- four payloads once rather than on every keystroke.
  local FOCUS_PAYLOAD = {}
  for _, d in ipairs(DIRECTIONS) do
    FOCUS_PAYLOAD[d] = vim.json.encode({
      id = 'nvim.nav',
      method = 'pane.focus_direction',
      params = { direction = d, pane_id = herdr_pane },
    }) .. '\n'
  end

  ---@return boolean reached  false means fall back to the CLI
  local function focus_via_socket(dir)
    local pipe = uv.new_pipe(false)
    if not pipe then
      return false
    end

    -- nil = still in flight; true/false = the reply arrived (or the connection
    -- failed). vim.wait polls this until it stops being nil or we time out.
    local reached = nil
    pipe:connect(socket, function(cerr)
      if cerr then
        reached = false
      else
        pipe:read_start(function(rerr, data)
          reached = not rerr and data ~= nil
        end)
        pipe:write(FOCUS_PAYLOAD[dir])
      end
    end)

    vim.wait(opts.socket_timeout_ms, function()
      return reached ~= nil
    end, 1)
    pipe:close()
    return reached == true
  end

  local function nav(dir)
    local prev = vim.api.nvim_get_current_win()
    vim.cmd('wincmd ' .. WINCMD[dir])
    if vim.api.nvim_get_current_win() ~= prev then
      return -- moved within Neovim
    end

    -- At a split edge: cross into the surrounding multiplexer.
    if in_herdr then
      if not focus_via_socket(dir) then
        vim.fn.system({ herdr_bin, 'pane', 'focus', '--direction', dir, '--current' })
      end
    elseif use_tmux then
      -- Requires christoomey/vim-tmux-navigator. Only reached under tmux.
      pcall(vim.cmd, 'TmuxNavigate' .. TMUX_DIR[dir])
    end
  end

  for _, dir in ipairs(DIRECTIONS) do
    for _, lhs in ipairs(opts.keymaps[dir] or {}) do
      vim.keymap.set({ 'n', 't' }, lhs, function()
        nav(dir)
      end, { silent = true, noremap = true, desc = 'Navigate ' .. dir })
    end
  end
end

return M
