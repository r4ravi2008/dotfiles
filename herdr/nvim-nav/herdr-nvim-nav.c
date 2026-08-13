/*
 * herdr-nvim-nav -- herdr keybind action for alt+h/j/k/l (tilish-style nav).
 *
 * Forward the chord to Neovim when it owns the focused pane, otherwise move
 * herdr's pane focus. Same decision the shell version made; the reason this is
 * C is purely cost.
 *
 * herdr runs a plugin action as an external command, so one fork/exec is
 * unavoidable -- 2.4ms on this machine. Everything above that is waste:
 *
 *     /usr/bin/true      2.4ms   fork/exec floor
 *     /bin/sh -c true    5.1ms   + shell startup
 *     herdr --version    5.6ms   + loading the herdr binary
 *     herdr pane edges   5.9ms   + the socket round trip (only 0.3ms!)
 *
 * A shell script that exec'd the herdr CLI paid both loads (~11ms) to do 0.3ms
 * of work. This does the same work in the one process herdr already had to
 * start: read the marker, write one request to herdr's socket. ~3ms.
 *
 * Build:  cc -O2 -o herdr-nvim-nav herdr-nvim-nav.c
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define PATH_BUF 1024
#define JSON_BUF 512

static int build_marker_path(const char *pane, char *out, size_t out_len) {
    const char *cache = getenv("XDG_CACHE_HOME");
    if (cache && *cache)
        return snprintf(out, out_len, "%s/herdr/nvim-panes/%s", cache, pane) < (int)out_len;

    const char *home = getenv("HOME");
    if (!home || !*home)
        return 0;
    return snprintf(out, out_len, "%s/.cache/herdr/nvim-panes/%s", home, pane) < (int)out_len;
}

/*
 * Neovim writes its PID to a file named after the pane on entry and removes it
 * on exit -- herdr has no equivalent of tmux's `@pane-is-vim` pane option, and
 * asking herdr what a pane is running would mean loading its binary, which is
 * the cost we are here to avoid. A PID that no longer exists was left by a hard
 * crash: drop the marker so the pane stops being misread.
 */
static int marker_says_vim(const char *pane) {
    char path[PATH_BUF];
    if (!build_marker_path(pane, path, sizeof path))
        return 0;

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;

    char buf[32];
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n <= 0)
        return 0;
    buf[n] = '\0';

    long pid = strtol(buf, NULL, 10);
    if (pid <= 0)
        return 0;

    /* Signal 0 only probes. EPERM means it exists but is not ours to signal. */
    if (kill((pid_t)pid, 0) == 0 || errno == EPERM)
        return 1;

    unlink(path);
    return 0;
}

static int socket_path(char *out, size_t out_len) {
    const char *sock = getenv("HERDR_SOCKET_PATH");
    if (sock && *sock)
        return snprintf(out, out_len, "%s", sock) < (int)out_len;

    const char *home = getenv("HOME");
    if (!home || !*home)
        return 0;
    return snprintf(out, out_len, "%s/.config/herdr/herdr.sock", home) < (int)out_len;
}

/* One newline-delimited JSON request over herdr's control socket. */
static int herdr_request(const char *json) {
    char path[PATH_BUF];
    if (!socket_path(path, sizeof path))
        return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof addr.sun_path)
        return -1;
    memcpy(addr.sun_path, path, strlen(path) + 1);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        close(fd);
        return -1;
    }

    size_t len = strlen(json), sent = 0;
    while (sent < len) {
        ssize_t w = write(fd, json + sent, len - sent);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            close(fd);
            return -1;
        }
        sent += (size_t)w;
    }

    /* Wait for the reply before closing: hanging up mid-handling can abort it.
     * A reply is either {"id":..,"result":{..}} or {"id":..,"error":{..}}, and
     * the discriminator is well inside the first read -- so a rejected request
     * fails loudly here instead of looking like a working keybind that does
     * nothing. herdr records our stderr and exit code in `herdr plugin log`. */
    char reply[256];
    ssize_t r;
    do {
        r = read(fd, reply, sizeof reply - 1);
    } while (r < 0 && errno == EINTR);

    close(fd);
    if (r <= 0)
        return -1;

    reply[r] = '\0';
    if (strstr(reply, "\"error\"") != NULL) {
        fprintf(stderr, "herdr-nvim-nav: herdr rejected the request: %s\n", reply);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: herdr-nvim-nav <left|down|up|right>\n");
        return 2;
    }

    const char *dir = argv[1];
    const char *key;
    /* Forward Alt+hjkl to match this repo's tilish / smart-splits scheme
     * (Alt = navigate, Ctrl = resize). Upstream defaults to Ctrl+hjkl. */
    if (strcmp(dir, "left") == 0)
        key = "alt+h";
    else if (strcmp(dir, "down") == 0)
        key = "alt+j";
    else if (strcmp(dir, "up") == 0)
        key = "alt+k";
    else if (strcmp(dir, "right") == 0)
        key = "alt+l";
    else {
        fprintf(stderr, "herdr-nvim-nav: unknown direction: %s\n", dir);
        return 2;
    }

    const char *pane = getenv("HERDR_PANE_ID");
    if (!pane)
        pane = "";

    /* Pane ids look like "w4:p2" and the keys are fixed literals, so neither
     * needs JSON escaping. */
    char json[JSON_BUF];
    if (*pane && marker_says_vim(pane))
        snprintf(json, sizeof json,
                 "{\"id\":\"herdr-nvim-nav\",\"method\":\"pane.send_keys\","
                 "\"params\":{\"pane_id\":\"%s\",\"keys\":[\"%s\"]}}\n",
                 pane, key);
    else if (*pane)
        snprintf(json, sizeof json,
                 "{\"id\":\"herdr-nvim-nav\",\"method\":\"pane.focus_direction\","
                 "\"params\":{\"direction\":\"%s\",\"pane_id\":\"%s\"}}\n",
                 dir, pane);
    else
        snprintf(json, sizeof json,
                 "{\"id\":\"herdr-nvim-nav\",\"method\":\"pane.focus_direction\","
                 "\"params\":{\"direction\":\"%s\"}}\n",
                 dir);

    if (herdr_request(json) != 0) {
        fprintf(stderr, "herdr-nvim-nav: herdr socket request failed\n");
        return 1;
    }
    return 0;
}
