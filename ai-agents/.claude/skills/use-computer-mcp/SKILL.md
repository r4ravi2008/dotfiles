---
name: use-computer-mcp
description: >-
  Computer use through Open Computer Use MCP. Use when a task requires
  interacting with a desktop app or authenticated browser UI, choosing a browser
  profile, or recovering a failed Computer interaction.
---
# Use Computer MCP

Drive the UI with a **tight loop**: choose the right identity, snapshot once, chain only against fresh state, and verify the outcome.

This server is registered as `open-computer-use` (`open-computer-use mcp`). Cursor, Claude Code, and OpenCode may prefix tool names with the server id. Use `get_app_state`, `list_apps`, `click`, `set_value`, `type_text`, and `press_key` (with whatever prefix the client shows).

## 1. Choose the channel and identity

Use an API or CLI for deterministic structured reads and writes. Use Computer for auth-bound, desktop-only, or genuinely visual work; it may verify the UI after a deterministic change.

For a browser, resolve the profile before navigation:

- work account, company domain, or internal service → **work**
- personal account, finance, shopping, or personal service → **personal**
- ambiguous identity or mixed accounts → ask which profile

Helium is `net.imput.helium` if that browser is installed. Otherwise use the running browser's name or bundle id from `list_apps`. Confirm the selected profile from the profile control or signed-in account marker.

For another app, use the name or bundle identifier already known from the current session. Call `list_apps` only when the app identity is unknown or stale, then keep the returned identifier stable.

## 2. Start the turn with fresh state

Begin each assistant turn that interacts with an app by calling `get_app_state`. Start with its defaults. The snapshot's element indices belong only to that state.

Use the refreshed state returned by each action to choose the next action. Call `get_app_state` again only after navigation, reload, modal or window changes, a failed action, or evidence that the returned tree is incomplete.

Keep snapshots compact:

- raise `text_limit` only when truncated semantic text is required; prefer a bounded integer before `"max"`
- raise `max_tree_nodes` or `max_tree_depth` only when a visible long page, list, or table is missing from the tree after scrolling
- retain only the few element indices and state facts needed for the next chain

The state is fresh when it identifies the intended app/window/profile and exposes the next target or proves that the target is absent.

## 3. Act in short stable chains

Prefer semantic element actions over coordinates.

- **Click:** use `click` with `element_index`; omit `click_method` so `auto` applies.
- **Fill:** when the element is marked settable, use `set_value`. Otherwise click the editable element, confirm focus in the refreshed state, then use `type_text` for literal text.
- **Keys:** use `press_key` for named keys and combinations, not literal prose.
- **Coordinates:** use them only when the rendered tree has no target. Keep the default `auto` method unless a specific fallback is justified.

Chain multiple calls in one assistant turn only while every next target is present in the latest action result and the window has not changed. Stop the chain at navigation, submission, modal transitions, downloads/uploads, or uncertainty; inspect before continuing.

## 4. Recover by changing the precondition

One failed call ends that strategy:

- stale element or changed page → refresh state and choose a current index
- no focused editable element → click the field, inspect focus, then type; use `set_value` when the field is settable
- non-settable element → focus it and type rather than repeating `set_value`
- app or window not found → call `list_apps` once, adopt its canonical identifier, then refresh state
- unsupported key or click method → use a supported key name or return to `auto`
- tool/catalog or connection error → reconnect or reload once, then rediscover the server surface
- permission error → report the required OS permission and pause for the user (macOS: Accessibility and Screen Recording)

A retry is valid only when the state, target, arguments, or method changed.

## 5. Verify

Use the latest action result when it proves the requested outcome; otherwise refresh state once. Completion requires visible evidence of the outcome, not merely a successful tool response.

## Reference branches

Read [REFERENCE.md](REFERENCE.md) only when overriding snapshot budgets or selecting a non-default macOS click method.
