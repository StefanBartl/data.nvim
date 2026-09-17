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

## Source and target are two decisions, not one scope

Every action does the same two things before any decoding happens: resolve
*where the input comes from* (`data.scope.source`) and *where the result goes*
(`data.scope.sink`). `run`/`convert`/`filter` then decode and render something
that knows about neither, and hand the lines to the sink.

Splitting them that way is what makes the flag matrix small instead of
combinatorial. `--reg` is purely a source, `--inplace`/`--split`/`--out-reg`
are purely targets, and the only coupling between them is the default: a
buffer/selection source replaces itself, a register source opens a split. Every
other pairing falls out for free, including the two that are genuinely useful
and would have needed special cases otherwise — `:JSON lines --split` (flatten
this buffer, keep the original) and `:'<,'>JSON pretty --reg=+ --inplace`
(paste the formatted clipboard over a selection).

It also moved one check to where it actually belongs. `'modifiable'` used to
gate every invocation at scope-resolution time, which was correct only as long
as the result always went back into the buffer. A read-only buffer is a
perfectly good source for `--split`/`--out-reg`, so the check now lives in the
in-place write and nowhere else.

### `--out-reg`, not `--reg`, for the register target

The concept listed `--inplace`/`--split`/`--reg=<name>` as the target flags,
while using `--reg=<name>` one paragraph earlier for the register *source*. One
flag name cannot mean both "read from here" and "write to there" on the same
command line. The source kept `--reg` — that is the reading the roadmap's Phase
1 entry spells out first and in most detail, and it is the more common of the
two by a wide margin — and the register target became `--out-reg`.

### `--reg --inplace` needs a range

With a register source and no range, "in place" can only mean the whole buffer,
so the combination would quietly replace an entire file with clipboard
contents. It is refused with a message saying so rather than being either
silently allowed or silently ignored. With an explicit range or Visual
selection it is exactly what it looks like, and is allowed.

### The preview is a `filter` flag, not a delivery option

`--preview` hangs off `filter` alone, and there are two independent reasons,
either of which would be enough. `filter` is the only action that *loses*
information — `pretty`/`compact`/`sort`/`to`/`ndjson` all render the same
document a different way, and the worst a mistaken one costs is an undo. And
`filter` is already built to survive an arbitrarily long gap between resolving
a scope and writing it (the extmark below); a confirmation prompt is a second
such gap, and putting one on the synchronous actions would mean giving each of
them that machinery for a case none of them needs.

Because the flag is declared only on `filter`'s routes, `:JSON pretty --preview`
is an unknown-flag error from the composer rather than a flag that silently does
nothing — the composer's fail-loud stance on undeclared flags doing the work a
runtime check would otherwise have to.

The preview goes through diff.nvim's public `require("diff").run("key=value …")`
API with both sides as buffer specifiers, and uses `view=inline`/`float` only:
diff.nvim's side-by-side renderer materializes the *target* and pairs it with
whatever buffer the origin window shows, so the left-hand side would be the
whole data buffer instead of the resolved scope — fine for a whole-buffer
scope, wrong for a fenced-block or Visual one. The unified-diff views build
from both resolved sides and are correct for all of them.

### `filter` only pays for the extmark when it needs to

`filter`'s in-place path anchors its scope to an extmark across the interactive
prompt, because the buffer can change arbitrarily while a person builds a
clause stack. A `--split`/`--out-reg` target writes somewhere that did not
exist yet when the prompt opened, so it needs none of that — the extmark is
only created for an in-place target.

`--preview` adds a second gap of the same kind, so the extmark stays alive
until after the `Apply`/`Discard` decision, and the live span is re-read from
it on both sides of the preview: once to build the "before" the diff actually
shows, and once more before the write. Reusing the first read for the second
would mean previewing one span and writing another whenever the buffer changed
while the diff was on screen.

## `:Data` reuses the fenced-block lookup it's already paying for

`data.detect.format` doesn't add a second fence-scanning mechanism next to
`data.scope.resolve`'s -- it calls the exact same
`color_my_ascii.fences.block_at` API, just without a fixed `lang` filter, so
the block's own language tag becomes the answer instead of a yes/no match
against one already-chosen format. `:Data pretty` therefore does two
`block_at` lookups on a fenced-scope hit (one in `data.detect` to learn the
format, one in `data.scope.resolve` once `data.run` is called with that
format to learn the range) rather than one -- an accepted, deliberate
duplication in the same spirit as `data.filter`'s double `path_flatten` call:
both lookups are cheap, per-buffer-changedtick-cached reads
(`color_my_ascii.fences.list_blocks`'s own doc comment), and threading the
already-resolved block from `data.detect` into `data.scope.resolve` would
couple two modules that otherwise don't know about each other, to save a call
that was never the expensive part of either function.

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
