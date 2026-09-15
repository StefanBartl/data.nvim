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
| `ndjson [indent]` | **`:JSON` only.** Pretty-print each line as its own JSON object, not the scope as one document. A line that fails to decode is left unchanged; the total skipped count is reported once. |
| `to yaml` | **`:JSON` only.** Convert the scope to YAML, in place. |
| `to json` | **`:YAML` only.** Convert the scope to JSON, in place. |
| `filter [--sep=X]` | Interactively reduce the flattened `path`/`value` entries down to the ones matching a clause stack, replacing the scope with the survivors' `lines`-style text. **Requires [pickers.nvim](https://github.com/StefanBartl/pickers.nvim).** |

**`sort` vs `pretty`:** identical output today, for all three formats. Neither
JSON's nor YAML's decoder preserves the source's original key order, and both
encoders sort object keys by default; XML's encoder always sorts attribute names
and never reorders elements, so there's nothing a "sort" pass could change either.
`sort` stays its own route for discoverability and forward-compatibility (an
order-preserving JSON/YAML decoder would give it real meaning), documented in each
`data.format.*` module.

**`filter`:** opens `pickers.refine`'s own `vim.ui.select`/`vim.ui.input` prompt
to add a clause (`path`/`line` contains/excludes a term, `/pattern/` for a Lua
pattern instead of a plain substring); adding a clause reopens the prompt for
another, and cancelling it (`<Esc>`) is what commits the filter and replaces the
scope — cancelling the very *first* prompt, before any clause exists, aborts
instead and leaves the scope untouched. `line` matches against the same text
`lines` would have shown for that entry (`path: value`), so a clause can match
a value too, not just a path. A filter matching nothing also leaves the scope
untouched, with a warning. `pickers.nvim` not installed is the one way any
`data.nvim` command fails outright rather than degrading — see
[integrations.md](integrations.md).

**Why no `to xml`/`from xml`:** XML's decoded shape is a raw element tree
(`{tag, attrs, children}`), not a plain map/array like JSON/YAML — converting
either way would mean guessing a schema (which repeated sibling tag becomes an
array? which attribute becomes "the" value?). See [architecture.md](architecture.md).

**Scope:** an explicit range (`:5,12JSON compact`) or visual selection
(`'<,'>YAML lines`) always wins. Without one: if the cursor sits inside a
matching ` ```json `/` ```yaml `/` ```xml ` fenced code block and
[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim) is
installed, that block's interior is the scope (see
[integrations.md](integrations.md)); otherwise the whole buffer. Either way,
only the resolved lines are decoded and replaced. Register scope (`--reg=`,
output to a scratch split instead of the buffer) is planned but not implemented
yet — see [scope.md](scope.md).

**Errors:** malformed input in the resolved scope leaves the buffer untouched and
reports a notification (`[data] JSON decode failed: ...`) instead of partially
overwriting anything.
