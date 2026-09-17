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
  block's language tag when the cursor is inside one, the register's own
  first non-blank line under `--reg`, otherwise the buffer's own
  `'filetype'`. A clear error, not a guess, when none of them maps to
  json/yaml/xml — use `:JSON`/`:YAML`/`:XML` directly in that case.
- Read the input from a register instead of the buffer (`:JSON pretty --reg=+`)
  and open the result in a scratch split, so a payload copied out of a ticket
  tool can be formatted without touching whatever buffer you happen to be in.
- Choose where any result goes, per invocation: `--inplace` (the default for a
  buffer/selection scope), `--split`, or `--out-reg=<name>` (write it back into
  a register). See [commands.md](commands.md#source-and-target-flags).
- `filter --preview` — show the filter result as a before/after diff and write
  it only after an `Apply`/`Discard` prompt, so a filter that removed more than
  you meant can be thrown away before it lands. Requires
  [diff.nvim](https://github.com/StefanBartl/diff.nvim) — see
  [integrations.md](integrations.md); plain `filter` works without it.
- Leave the buffer untouched on invalid input, with a clear error notification.

## Does not (yet)

1. **Object reconstruction after `filter`.** The filter result is a flat
   `path: value` line list, not a re-nested JSON/YAML document containing only
   the surviving keys. Recovering array- vs. map-shaped intermediate nodes from
   plain path strings is ambiguous without a schema — the same problem
   [architecture.md](architecture.md) describes for XML→JSON.
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

**[`diff.nvim`](https://github.com/StefanBartl/diff.nvim)** renders the
before/after diff behind `filter --preview` (see "Does" above and
[integrations.md](integrations.md)). Optional: only that one flag needs it, and
asking for it without diff.nvim installed writes nothing rather than filtering
unseen. `:JSON filter --split` remains the zero-dependency version of the same
idea — the original scope stays put and the survivors land beside it.

**[`ai.nvim`](https://github.com/StefanBartl/ai.nvim)** optionally consumes this
plugin, never the other way around: its `context.structured_data` flag (see
[its docs](https://github.com/StefanBartl/ai.nvim/blob/main/docs/configuration.md))
calls straight into `data.detect`/`data.scope.resolve`/`data.format` — the same
pipeline `:Data` itself uses — to fold the flattened form of a json/yaml/xml block
under the cursor into an AI prompt's context. Nothing to configure here; data.nvim
has no knowledge of ai.nvim and no code changed on this side.
