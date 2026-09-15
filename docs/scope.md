# What it does, and what not (yet)

## Does

- Reformat JSON in the current buffer or a visual selection: `pretty`, `compact`,
  `lines` (flattened, dotted-path `key: value`), `keys`, `sort`.
- Reformat YAML the same way, minus `compact` — see
  [`lib.lua.yaml`](https://github.com/StefanBartl/lib.nvim/tree/main/lua/lib/lua/yaml)'s
  own doc comment for the (intentionally minimal) subset supported: no anchors, no
  flow style, no block scalars.
- Reformat XML the same way, all five actions — see
  [`lib.lua.xml`](https://github.com/StefanBartl/lib.nvim/tree/main/lua/lib/lua/xml)'s
  own doc comment for its subset (no namespace resolution, DOCTYPEs are skipped
  rather than parsed). `:XML lines`/`keys` flatten the **raw decoded element tree**
  (`{tag, attrs, children}`), not a JSON-like objectification of the document — see
  [architecture.md](architecture.md) for why that mapping is deliberately not
  attempted.
- `:JSON ndjson` — pretty-print a buffer of one-JSON-object-per-line logs, each
  line independently; a line that fails to decode is left unchanged rather than
  aborting the rest.
- `:JSON to yaml` / `:YAML to json` — convert the scope in place between the two
  formats that share a plain-map/array decoded shape.
- Scope to an enclosing ` ```json `/` ```yaml `/` ```xml ` fenced code block
  (e.g. in a Markdown note) instead of the whole buffer, when
  [color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim) is
  installed — see [integrations.md](integrations.md). Optional; a total no-op
  without it.
- Leave the buffer untouched on invalid input, with a clear error notification.

## Does not (yet)

1. **Register scope.** `:JSON pretty --reg=+` (read from a register, write to a
   scratch split instead of the buffer) is designed but not built.
2. **Filter UI.** A `pickers.refine`-backed `:JSON filter` to reduce a large object
   down to the keys that matter (`user.*`, `error.stack`, ...) is designed but not
   built. A `diff.nvim` before/after preview once it exists depends on this.
3. **`to xml`/`from xml`.** XML's decoded shape is a raw element tree
   (`{tag, attrs, children}`), not a plain map/array like JSON/YAML — converting
   either way would mean guessing a schema (which repeated sibling tag becomes an
   array? which attribute becomes "the" value?) without one to guess from. See
   [architecture.md](architecture.md). Not planned unless a concrete, honestly
   lossy mapping is worth defining later.

This plugin is deliberately thin: the JSON/YAML/XML/table primitives it uses
(`lib.nvim.json`, `lib.lua.json.encode`, `lib.lua.yaml`, `lib.lua.xml`,
`lib.lua.tables.path_flatten`, `lib.lua.null`) live in
[`lib.nvim`](https://github.com/StefanBartl/lib.nvim), not here — see
[architecture.md](architecture.md).

## Around it

**[`casedesk.nvim`](https://github.com/StefanBartl/casedesk.nvim)** is support-case
*scaffolding* (folders per ticket, SLA tracking) — it has no generic data-formatting
command of its own and may one day call into data.nvim for that, never the other way
around.

**[`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim)** is a generic picker
framework; its `refine` filter-stack module is the planned building block for
`:JSON filter` (see "Does not" above), not something data.nvim depends on today.
