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
- `:JSON filter` / `:YAML filter` / `:XML filter` — interactively reduce the
  flattened `path`/`value` entries (the same ones `lines`/`keys` render) down
  to the ones matching a `pickers.refine` clause stack (`user.*`, excludes
  `error.stack`, ...), then replace the scope with the survivors. Requires
  [pickers.nvim](https://github.com/StefanBartl/pickers.nvim) — see
  [integrations.md](integrations.md); every other action works without it.
- `:Data pretty`/`lines`/`keys`/`sort`/`filter` — the same actions as above,
  minus the format-specific ones (`compact`/`ndjson`/`to`), with the format
  auto-detected instead of named by the command: the enclosing fenced
  block's language tag when the cursor is inside one, otherwise the
  buffer's own `'filetype'`. A clear error, not a guess, when neither maps
  to json/yaml/xml — use `:JSON`/`:YAML`/`:XML` directly in that case.
- Leave the buffer untouched on invalid input, with a clear error notification.

## Does not (yet)

1. **Register scope.** `:JSON pretty --reg=+` (read from a register, write to a
   scratch split instead of the buffer) is designed but not built.
2. **`to xml`/`from xml`.** XML's decoded shape is a raw element tree
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
framework; its `refine` filter-stack module backs `:JSON filter`/`:YAML filter`/
`:XML filter` (see "Does" above and [integrations.md](integrations.md)) — the one
action in this plugin that does not work without it.

**[`diff.nvim`](https://github.com/StefanBartl/diff.nvim)** before/after preview of
a filter result is a natural next step now that `filter` exists, but is not built —
`filter` replaces the scope in place today, the same way every other action does.
