# Why it does it that way

## A thin editor layer over lib.nvim

data.nvim's own code is deliberately small: `lua/data/format/json.lua` and
`format/yaml.lua` are each under 100 lines, thin adapters rather than
parsers/encoders. The actual JSON/YAML decode/encode, the shared null sentinel,
and the recursive path-flattening `lines`/`keys` need, live in `lib.nvim`
(`lib.nvim.json`, `lib.lua.json.encode`, `lib.lua.yaml`, `lib.lua.null`,
`lib.lua.tables.path_flatten`) — reusable by any other plugin, not re-implemented
here. This mirrors how `replacer.nvim` uses `pickers.refine` rather than owning a
filter stack: the generic capability belongs one level down, the plugin is the
command/scope/UI wiring on top. Adding `:YAML` (once `lib.lua.yaml.encode` existed)
was almost entirely that kind of wiring: a second ~90-line format adapter and a
route-factory refactor in `bindings/usrcmds.lua` — no new decode/encode/flatten
logic in this repo at all.

## One Lua-value IR, no format-specific pipeline

There is no data.nvim-specific intermediate representation. `format/*` works
purely against the decoded Lua value — a plain table from `vim.json.decode` or
`lib.lua.yaml.simple_parse`, with `lib.lua.null.NULL` as the one shared
representation of an explicit null across both (see that module's own doc
comment for why: neither JSON's nor YAML's decoder can use Lua's own `nil` for
it). `lib.lua.tables.path_flatten` doesn't know or care which format produced
its input — the same call handles JSON's `lines`/`keys` and YAML's. This is
*why* YAML support turned out to be mostly wiring rather than a second
implementation, and why XML (see [scope.md](scope.md)) is expected to be the
same shape once `lib.nvim` grows an XML decoder/encoder.

## Why `sort` isn't actually different from `pretty` yet

Both encoders (`lib.lua.json.encode`, `lib.lua.yaml.encode`) sort object keys by
default, and neither decoder (`vim.json.decode`, `lib.lua.yaml.simple_parse`)
preserves the source's original key order in the decoded Lua table (Lua tables
have no such concept). So "pretty, as read" and "pretty, sorted" collapse to the
same operation once a value has round-tripped through a plain decode — see
`data.format.json`/`data.format.yaml`'s own doc comments and
[commands.md](docs/commands.md). Building a custom order-preserving decoder just
to make the two commands diverge was judged out of scope for what a
"pretty-print my pasted log" plugin needs; `sort` is kept as an explicit,
self-documenting route rather than removed, in case an order-preserving decoder
is ever worth adding for its own sake.

## Compound commands via `lib.nvim`'s composer

`:JSON <action>`/`:YAML <action>` (one verb per format, several subcommands each)
instead of `:JSONPretty`, `:JSONCompact`, etc. — `lib.nvim.bindings.usercmd.composer`
builds the whole tree (dispatch, `<Tab>` completion, Markdown docgen for
[BINDINGS.md](BINDINGS.md)) from one declarative route table per verb. Both verbs
share a single route-factory function (`bindings/usrcmds.lua`'s `make_routes`) since
their actions are identical apart from `compact` (JSON only) — adding `:YAML` meant
parameterizing that factory by format name, not duplicating five route definitions.
Same composer pattern `cascade.nvim`/`replacer.nvim`/`gopath.nvim` already use.
