# Commands

`:JSON [action] [args] [flags]` and `:YAML [action] [args] [flags]` — range-aware:
no range acts on the whole buffer, a visual selection or an explicit `:N,M` range
acts only on those lines. Both are built on
`lib.nvim.bindings.usercmd.composer`, so every action and flag below also has
`<Tab>` completion.

| Invocation | Action |
| --- | --- |
| `:JSON` / `:YAML` | Same as `pretty` (the default action). |
| `pretty [indent]` | Pretty-print, multi-line. `indent` defaults to 2 (or `json.indent`/`yaml.indent`). |
| `compact` | Collapse onto one line. **JSON only** — YAML's subset has no flow style to collapse into, see [scope.md](scope.md). |
| `lines [--sep=X]` | One `path: value` per leaf; nested keys joined with `.` (or `--sep`). |
| `keys [--sep=X]` | Like `lines`, but only the paths — no values. |
| `sort [indent]` | Pretty-print with sorted object keys. |

**`sort` vs `pretty`:** identical output today, for both formats. Neither decoder
(`vim.json.decode`, `lib.lua.yaml.simple_parse`) preserves the source's original key
order, and both encoders sort object keys by default — there is no "as read" order
left to preserve once a value has round-tripped through Lua. `sort` stays its own
route for discoverability and forward-compatibility (an order-preserving decoder
would give it real meaning), documented in `data.format.json`/`data.format.yaml`.

**Scope:** no range → whole buffer, in place. A range (`:5,12JSON compact`) or a
visual selection (`'<,'>YAML lines`) → only those lines are decoded and replaced;
the rest of the buffer is untouched. Register scope (`--reg=`, output to a scratch
split instead of the buffer) is planned but not implemented yet — see
[scope.md](scope.md).

**Errors:** malformed input in the resolved scope leaves the buffer untouched and
reports a notification (`[data] JSON decode failed: ...`) instead of partially
overwriting anything.
