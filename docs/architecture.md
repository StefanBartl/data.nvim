# Why it does it that way

## A thin editor layer over lib.nvim

data.nvim's own code is deliberately small: `lua/data/format/json.lua` is a ~90-line
adapter, not a JSON parser. The actual JSON decode/encode, and the recursive
path-flattening `:JSON lines`/`keys` need, live in `lib.nvim`
(`lib.nvim.json`, `lib.lua.json.encode`, `lib.lua.tables.path_flatten`) — reusable by
any other plugin, not re-implemented here. This mirrors how `replacer.nvim` uses
`pickers.refine` rather than owning a filter stack: the generic capability belongs
one level down, the plugin is the command/scope/UI wiring on top.

## One Lua-value IR, no format-specific pipeline

There is no data.nvim-specific intermediate representation. `render/*` (currently
just `format/json.lua`) works purely against the decoded Lua value — a plain table
from `vim.json.decode` today, and (once built) a `lib.lua.yaml`/`lib.lua.xml`
decoder's output tomorrow. `lib.lua.tables.path_flatten` doesn't know or care which
format produced its input. This is *why* YAML/XML support (see
[scope.md](scope.md)) is expected to be mostly wiring once the missing `lib.nvim`
encoders exist, not a second implementation of `lines`/`keys`.

## Why `sort` isn't actually different from `pretty` yet

`lib.lua.json.encode` sorts object keys by default, and `vim.json.decode` doesn't
preserve the source's original key order in the decoded Lua table (Lua tables have
no such concept). So "pretty, as read" and "pretty, sorted" collapse to the same
operation once the JSON has round-tripped through a plain decode — see
`data.format.json`'s own doc comment and [commands.md](docs/commands.md). Building a
custom order-preserving JSON decoder just to make the two commands diverge was
judged out of scope for what a "pretty-print my pasted log" plugin needs; `sort`
is kept as an explicit, self-documenting route rather than removed, in case an
order-preserving decoder is ever worth adding for its own sake.

## Compound commands via `lib.nvim`'s composer

`:JSON <action>` (one verb, several subcommands) instead of `:JSONPretty`,
`:JSONCompact`, etc. — `lib.nvim.bindings.usercmd.composer` builds the whole tree
(dispatch, `<Tab>` completion, Markdown docgen for
[BINDINGS.md](BINDINGS.md)) from one declarative route table
(`data/bindings/usrcmds.lua`), the same pattern `cascade.nvim`/`replacer.nvim`/
`gopath.nvim` already use.
