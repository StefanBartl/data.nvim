# What it does, and what not (yet)

## Does

- Reformat JSON in the current buffer or a visual selection: `pretty`, `compact`,
  `lines` (flattened, dotted-path `key: value`), `keys`, `sort`.
- Reformat YAML the same way, minus `compact` — see
  [`lib.lua.yaml`](https://github.com/StefanBartl/lib.nvim/tree/main/lua/lib/lua/yaml)'s
  own doc comment for the (intentionally minimal) subset supported: no anchors, no
  flow style, no block scalars.
- Leave the buffer untouched on invalid input, with a clear error notification.

## Does not (yet)

Per the project's phased concept, in order:

1. **Register scope.** `:JSON pretty --reg=+` (read from a register, write to a
   scratch split instead of the buffer) is designed but not built.
2. **Filter UI.** A `pickers.refine`-backed `:JSON filter` to reduce a large object
   down to the keys that matter (`user.*`, `error.stack`, ...) is designed but not
   built.
3. **XML.** `:XML` needs an XML module in `lib.nvim` — neither a decoder nor an
   encoder exists yet.
4. **Format conversion** (`:JSON to yaml`) and an `ndjson` line-by-line mode fall
   out "for free" once (3) lands, since all formats share the same flatten-based
   Lua-value pipeline.

This plugin is deliberately thin: the JSON/YAML/table primitives it uses
(`lib.nvim.json`, `lib.lua.json.encode`, `lib.lua.yaml`, `lib.lua.tables.path_flatten`,
`lib.lua.null`) live in [`lib.nvim`](https://github.com/StefanBartl/lib.nvim), not
here — see [architecture.md](architecture.md).

## Around it

**[`casedesk.nvim`](https://github.com/StefanBartl/casedesk.nvim)** is support-case
*scaffolding* (folders per ticket, SLA tracking) — it has no generic data-formatting
command of its own and may one day call into data.nvim for that, never the other way
around.

**[`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim)** is a generic picker
framework; its `refine` filter-stack module is the planned building block for
`:JSON filter` (see "Does not" above), not something data.nvim depends on today.
