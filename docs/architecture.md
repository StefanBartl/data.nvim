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
`:JSON to yaml`/`:YAML to json` (`data.convert`) exist and `to xml`/`from xml`
don't: the former just decodes with one format's adapter and renders with the
other's, because both work against the same plain-map/array shape; the latter
has no shape to convert into or out of without guessing.

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

## `ndjson` is a scope-loop, not a fourth render primitive

`:JSON ndjson` doesn't add a new mode to `data.format.json`'s `render()` -- it's
handled entirely in `data.init`'s `run_ndjson`, which loops the resolved scope's
lines and calls the *existing* `decode`/`render("pretty", ...)` pair once per
line, substituting the original line unchanged wherever decode fails rather than
aborting the whole invocation. Keeping this at the `data.run` layer (not inside
`format/json.lua`) means the format module's contract stays simple ("one text
in, one value out" / "one value in, some lines out") and per-line fault
tolerance is a property of the *command*, not smuggled into the formatter.

## Fenced-block scope is additive, not a scope rewrite

`data.scope.resolve.lines` tries an explicit range first, exactly as before;
only when there isn't one does it ask (via `pcall`) whether
[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim)'s
fence API knows about a block matching the requested format under the cursor.
No color_my_ascii, no matching fence, or `fenced_scope.enable = false` all fall
through to the pre-existing whole-buffer default unchanged -- the integration
adds a scope source, it doesn't touch the two that were already there. See
[integrations.md](integrations.md).

## `filter` is `lines` plus a borrowed filter stack, not a new pipeline

`data.filter` doesn't add a fourth thing `path_flatten` needs to know how to
do — it flattens exactly the way `lines` already does, then hands the result
to [`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim)'s
`pickers.refine`, a pure model+UI module with no picker-engine dependency of
its own (the same building block `replacer.nvim` already uses outside of any
picker). data.nvim owns none of the filter-stack UI; it only supplies the
items (`{path, line}`, one per flattened leaf) and renders whatever survives
back as `lines`-style text. This is also why `filter` is offered on `:JSON`,
`:YAML` and `:XML` alike with no per-format gating, unlike `compact`/`ndjson`/
`to`: it operates on the same `path_flatten` output `lines`/`keys` already
share across all three formats, so there is nothing format-specific to opt in
or out of.

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
