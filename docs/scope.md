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
- Leave the buffer untouched on invalid input, with a clear error notification.

## Does not (yet)

Per the project's phased concept, in order:

1. **Register scope.** `:JSON pretty --reg=+` (read from a register, write to a
   scratch split instead of the buffer) is designed but not built.
2. **Filter UI.** A `pickers.refine`-backed `:JSON filter` to reduce a large object
   down to the keys that matter (`user.*`, `error.stack`, ...) is designed but not
   built.
3. **Format conversion** (`:JSON to yaml`) between JSON and YAML — same flatten-based
   Lua-value pipeline, not yet wired into a `to` action. XML is excluded: its
   element/attribute/mixed-content shape has no unambiguous mapping to or from a
   plain JSON/YAML map without a schema (see architecture.md).
4. **`ndjson`** line-by-line mode for `:JSON` (support logs are often one JSON
   object per line, not one big document).

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
