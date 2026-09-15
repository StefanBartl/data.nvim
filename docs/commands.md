# Commands

`:JSON [action] [args] [flags]` — range-aware: no range acts on the whole buffer, a
visual selection or an explicit `:N,M` range acts only on those lines. Built on
`lib.nvim.bindings.usercmd.composer`, so every action and flag below also has
`<Tab>` completion.

| Invocation | Action |
| --- | --- |
| `:JSON` | Same as `:JSON pretty` (the default action). |
| `:JSON pretty [indent]` | Pretty-print, multi-line. `indent` defaults to 2 (or `json.indent`). |
| `:JSON compact` | Collapse onto one line. |
| `:JSON lines [--sep=X]` | One `path: value` per leaf; nested keys joined with `.` (or `--sep`). |
| `:JSON keys [--sep=X]` | Like `lines`, but only the paths — no values. |
| `:JSON sort [indent]` | Pretty-print with sorted object keys. |

**`sort` vs `pretty`:** identical output today. `vim.json.decode` returns a plain Lua
table with no preserved source key order, and the underlying encoder
(`lib.lua.json.encode`) sorts object keys by default — there is no "as read" order
left to preserve once a value has round-tripped through Lua. `sort` stays its own
route for discoverability and forward-compatibility (an order-preserving decoder
would give it real meaning), documented in `data.format.json`.

**Scope:** no range → whole buffer, in place. A range (`:5,12JSON compact`) or a
visual selection (`'<,'>JSON lines`) → only those lines are decoded and replaced;
the rest of the buffer is untouched. Register scope (`--reg=`, output to a scratch
split instead of the buffer) is planned but not implemented yet — see
[scope.md](scope.md).

**Errors:** malformed input in the resolved scope leaves the buffer untouched and
reports a notification (`[data] JSON decode failed: ...`) instead of partially
overwriting anything.
