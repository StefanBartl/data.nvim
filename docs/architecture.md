# Why it does it that way

## A thin editor layer over lib.nvim

data.nvim's own code is deliberately small: `lua/data/format/{json,yaml,xml}.lua`
are each under 100 lines, thin adapters rather than parsers/encoders. The actual
decode/encode for all three formats, the shared null sentinel, and the recursive
path-flattening `lines`/`keys` need, live in `lib.nvim` (`lib.nvim.json`,
`lib.lua.json.encode`, `lib.lua.yaml`, `lib.lua.xml`, `lib.lua.null`,
`lib.lua.tables.path_flatten`) — reusable by any other plugin, not re-implemented
here. This mirrors how `replacer.nvim` uses `pickers.refine` rather than owning a
filter stack: the generic capability belongs one level down, the plugin is the
command/scope/UI wiring on top. Adding `:YAML` and `:XML` (once `lib.nvim` had the
matching encoder/decoder) was almost entirely that kind of wiring: one ~90-line
format adapter each, plus a route-factory refactor in `bindings/usrcmds.lua` — no
new decode/encode/flatten logic in this repo at all.

## One Lua-value IR, no format-specific pipeline

There is no data.nvim-specific intermediate representation. `format/*` works
purely against the decoded Lua value from each format's own `lib.nvim`/`lib.lua`
decoder, with `lib.lua.null.NULL` as the one shared representation of an explicit
null across JSON and YAML (see that module's own doc comment for why: neither
decoder can use Lua's own `nil` for it). `lib.lua.tables.path_flatten` doesn't
know or care which format produced its input — the same call handles `lines`/
`keys` for all three. This is *why* YAML and XML support turned out to be mostly
wiring rather than a second/third implementation.

XML is the one place this IR shows its edges: JSON and YAML decode to a plain
map/array, but XML's element/attribute/mixed-content shape doesn't fit that —
collapsing it onto a JSON-like object would mean guessing which repeated sibling
tags become an array and which attribute becomes "the" value, without a schema
to guess from. `lib.lua.xml.decode` deliberately does **not** attempt that: it
returns the raw tree (`{tag, attrs, children}`), and `:XML lines`/`keys` flatten
*that*, mechanical paths (`children.1.attrs.id`) and all, rather than pretending
to a JSON-shaped summary the format can't honestly provide. This is also why
JSON↔YAML format conversion (see [scope.md](scope.md)) is a reasonable future
feature and JSON/YAML↔XML conversion is not: the former shares one IR shape, the
latter doesn't.

## Why `sort` isn't actually different from `pretty` yet

`lib.lua.json.encode`/`lib.lua.yaml.encode` both sort object keys by default, and
neither JSON's nor YAML's decoder preserves the source's original key order in the
decoded Lua table (Lua tables have no such concept) — so "pretty, as read" and
"pretty, sorted" collapse to the same operation for those two. XML's encoder
always sorts attribute names and never reorders elements (there's no "unsorted"
element order to begin with — a document's element sequence *is* its order), so
`sort` is a no-op there for a different, XML-specific reason. See each
`data.format.*` module's own doc comment and [commands.md](docs/commands.md).
Building a custom order-preserving JSON/YAML decoder just to make the two
commands diverge was judged out of scope for what a "pretty-print my pasted log"
plugin needs; `sort` is kept as an explicit, self-documenting route rather than
removed, in case an order-preserving decoder is ever worth adding for its own
sake.

## Compound commands via `lib.nvim`'s composer

`:JSON <action>`/`:YAML <action>`/`:XML <action>` (one verb per format, several
subcommands each) instead of `:JSONPretty`, `:JSONCompact`, etc. —
`lib.nvim.bindings.usercmd.composer` builds the whole tree (dispatch, `<Tab>`
completion, Markdown docgen for [BINDINGS.md](BINDINGS.md)) from one declarative
route table per verb. All three verbs share a single route-factory function
(`bindings/usrcmds.lua`'s `make_routes`) since their actions are identical apart
from `compact` (JSON and XML, not YAML) — adding `:XML` after `:YAML` meant one
more `make_verb(...)` call, not a duplicated route table. Same composer pattern
`cascade.nvim`/`replacer.nvim`/`gopath.nvim` already use.
