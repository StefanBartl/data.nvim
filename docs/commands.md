# Commands

`:JSON`, `:YAML`, `:XML`, each `[action] [args] [flags]` — range-aware: no range
acts on the whole buffer, a visual selection or an explicit `:N,M` range acts only
on those lines. All three are built on `lib.nvim.bindings.usercmd.composer`, so
every action and flag below also has `<Tab>` completion.

| Invocation | Action |
| --- | --- |
| `:JSON` / `:YAML` / `:XML` | Same as `pretty` (the default action). |
| `pretty [indent]` | Pretty-print, multi-line. `indent` defaults to 2 (or `json.indent`/`yaml.indent`/`xml.indent`). |
| `compact` | Collapse onto one line. **JSON and XML only** — YAML's subset has no flow style to collapse into, see [scope.md](scope.md). |
| `lines [--sep=X]` | One `path: value` per leaf; nested keys joined with `.` (or `--sep`). For XML this flattens the raw `{tag, attrs, children}` tree — see [scope.md](scope.md). |
| `keys [--sep=X]` | Like `lines`, but only the paths — no values. |
| `sort [indent]` | Pretty-print with sorted object keys (JSON/YAML) or sorted attributes (XML). |

**`sort` vs `pretty`:** identical output today, for all three formats. Neither
JSON's nor YAML's decoder preserves the source's original key order, and both
encoders sort object keys by default; XML's encoder always sorts attribute names
and never reorders elements, so there's nothing a "sort" pass could change either.
`sort` stays its own route for discoverability and forward-compatibility (an
order-preserving JSON/YAML decoder would give it real meaning), documented in each
`data.format.*` module.

**Scope:** no range → whole buffer, in place. A range (`:5,12JSON compact`) or a
visual selection (`'<,'>YAML lines`) → only those lines are decoded and replaced;
the rest of the buffer is untouched. Register scope (`--reg=`, output to a scratch
split instead of the buffer) is planned but not implemented yet — see
[scope.md](scope.md).

**Errors:** malformed input in the resolved scope leaves the buffer untouched and
reports a notification (`[data] JSON decode failed: ...`) instead of partially
overwriting anything.
