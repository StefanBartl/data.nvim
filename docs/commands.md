# Commands

`:JSON`, `:YAML`, `:XML`, `:Data`, each `[action] [args] [flags]` — range-aware:
no range acts on the whole buffer, a visual selection or an explicit `:N,M` range
acts only on those lines. All four are built on `lib.nvim.bindings.usercmd.composer`,
so every action and flag below also has `<Tab>` completion.

| Invocation | Action |
| --- | --- |
| `:JSON` / `:YAML` / `:XML` | Same as `pretty` (the default action). |
| `pretty [indent]` | Pretty-print, multi-line. `indent` defaults to 2 (or `json.indent`/`yaml.indent`/`xml.indent`). |
| `compact` | Collapse onto one line. **JSON and XML only** — YAML's subset has no flow style to collapse into, see [scope.md](scope.md). |
| `lines [--sep=X]` | One `path: value` per leaf; nested keys joined with `.` (or `--sep`). For XML this flattens the raw `{tag, attrs, children}` tree — see [scope.md](scope.md). |
| `keys [--sep=X]` | Like `lines`, but only the paths — no values. |
| `sort [indent]` | Pretty-print with sorted object keys (JSON/YAML) or sorted attributes (XML). |
| `ndjson [indent]` | **`:JSON` only.** Pretty-print each line as its own JSON object, not the scope as one document. A line that fails to decode is left unchanged; the total skipped count is reported once. |
| `to yaml` | **`:JSON` only.** Convert the scope to YAML, in place. |
| `to json` | **`:YAML` only.** Convert the scope to JSON, in place. |
| `filter [--sep=X] [--preview]` | Interactively reduce the flattened `path`/`value` entries down to the ones matching a clause stack, replacing the scope with the survivors' `lines`-style text. **Requires [pickers.nvim](https://github.com/StefanBartl/pickers.nvim);** `--preview` additionally requires [diff.nvim](https://github.com/StefanBartl/diff.nvim). |

Every action also takes the source/target flags below.

## Source and target flags

Where the input comes from, and where the result goes. Available on every
action of every verb, in any order, alongside that action's own args/flags.

| Flag | What it does |
| --- | --- |
| `--reg` / `--reg=<name>` | Read the input from a register instead of the buffer. Bare `--reg` uses `register.default` (`+`, the system clipboard). |
| `--inplace` | Write the result back over the buffer scope. |
| `--split` | Write the result into a fresh scratch split (`target.split` picks the direction). |
| `--out-reg` / `--out-reg=<name>` | Write the result into a register. Bare `--out-reg` uses `register.default`. |

(`filter` takes two more of its own, `--preview`/`--no-preview` — see below.)

**Defaults follow the source.** A buffer or selection scope replaces itself
(`--inplace`); a register source opens a split (`--split`), because the point
of reading from a register is not to touch the buffer you happen to be sitting
in. So `:JSON pretty --reg=+` formats the clipboard into a new split and leaves
the current buffer alone, and plain `:JSON pretty` behaves exactly as it always
has.

```vim
:JSON pretty --reg=+          " format the clipboard into a scratch split
:JSON lines --split           " flatten this buffer, result beside it
:JSON compact --out-reg=+     " minify this buffer back onto the clipboard
:'<,'>JSON pretty --reg=+ --inplace  " paste the formatted clipboard over the selection
```

**Refusals, on purpose:**

- The three target flags are mutually exclusive — two at once is an error, not
  a ranking.
- `--reg --inplace` needs an explicit range or visual selection. Without one,
  "in place" would mean the whole buffer, and replacing an entire file with
  register contents is not something a formatting command should be able to do
  by accident.
- `--out-reg` refuses Vim's read-only registers (`:`, `.`, `%`, `#`, `=`) by
  name rather than failing inside `setreg`.
- An empty register is reported (`register '+' is empty`); nothing is written.

**`--out-reg` says what it did.** A register write is invisible, so it reports
`wrote 12 line(s) to register '+'` rather than looking like it did nothing.

**Read-only buffers** are perfectly good *sources* for `--split`/`--out-reg`.
Only the in-place write needs `'modifiable'`, and that is the only place it is
checked.

**Bare `:JSON`/`:YAML`/`:XML`/`:Data`** (no action) is still whole-buffer,
in-place pretty-printing; flags need an explicit action
(`:JSON pretty --split`).

**The result split** is a `nofile` scratch buffer, wiped when hidden, named
`data://json pretty (+) [1]` and modifiable so a line can be trimmed before
yanking it back. Each run opens its own — a second one never overwrites the
first. Its `'filetype'` is the result's format (`json`/`yaml`/`xml`), except
for `lines`/`keys`/`filter`, whose flattened `path: value` text is not a
document in any of the three.

**`sort` vs `pretty`:** identical output today, for all three formats. Neither
JSON's nor YAML's decoder preserves the source's original key order, and both
encoders sort object keys by default; XML's encoder always sorts attribute names
and never reorders elements, so there's nothing a "sort" pass could change either.
`sort` stays its own route for discoverability and forward-compatibility (an
order-preserving JSON/YAML decoder would give it real meaning), documented in each
`data.format.*` module.

**`filter`:** opens `pickers.refine`'s own `vim.ui.select`/`vim.ui.input` prompt
to add a clause (`path`/`line` contains/excludes a term, `/pattern/` for a Lua
pattern instead of a plain substring); adding a clause reopens the prompt for
another, and cancelling it (`<Esc>`) is what commits the filter and replaces the
scope — cancelling the very *first* prompt, before any clause exists, aborts
instead and leaves the scope untouched. `line` matches against the same text
`lines` would have shown for that entry (`path: value`), so a clause can match
a value too, not just a path. A filter matching nothing also leaves the scope
untouched, with a warning. `pickers.nvim` not installed is the one way any
`data.nvim` command fails outright rather than degrading — see
[integrations.md](integrations.md).

**`filter --preview`:** show the result as a unified diff against the scope as
it stands, and write it only after an `Apply`/`Discard` prompt — so a filter
that removes more than you meant can be thrown away before it lands. Backed by
[diff.nvim](https://github.com/StefanBartl/diff.nvim); see
[integrations.md](integrations.md#diffnvim--filter---preview).

```vim
:JSON filter --preview     " diff the result, then decide
:JSON filter --no-preview  " skip it, even with preview.filter = true configured
```

`preview.filter = true` in [configuration.md](configuration.md) makes the
preview the default for every in-place `filter`; `--preview`/`--no-preview`
override it per invocation, and giving both is an error rather than a ranking.
Three more things it deliberately does:

- **Asked for and unavailable means nothing is written.** `--preview` without
  diff.nvim installed is an error, not a silent plain filter — the flag exists
  precisely so that nothing is replaced unseen.
- **`--preview` is a `filter` flag only,** so `:JSON pretty --preview` is an
  unknown-flag error rather than a flag that quietly does nothing. `filter` is
  the one action that *loses* data; the rest render the same document a
  different way, and the worst a bad one costs is an undo.
- **It applies to an in-place result only.** `--split`/`--out-reg` leave the
  scope where it is, so there is nothing to preview against; combining them
  warns rather than pretending.

**Why no `to xml`/`from xml`:** XML's decoded shape is a raw element tree
(`{tag, attrs, children}`), not a plain map/array like JSON/YAML — converting
either way would mean guessing a schema (which repeated sibling tag becomes an
array? which attribute becomes "the" value?). See [architecture.md](architecture.md).

## `:Data` — format auto-detected

`:Data pretty`/`lines`/`keys`/`sort`/`filter` are the same actions, minus the
ones that are already format-specific by nature (`compact`, `ndjson`, `to`) —
reaching for one of those already means knowing whether it's JSON, YAML or
XML, which is exactly the choice `:Data` exists to skip. The format comes
from, in order:

1. With `--reg`, the register's own first non-blank line: `{`/`[` is JSON,
   `<` is XML, a `---` marker / `- ` sequence item / `key:` mapping line is
   YAML. Neither the fenced block nor the filetype says anything about text
   that never came from this buffer, so neither is consulted in that case.
2. The enclosing fenced code block's language tag, when the cursor sits
   inside one, no explicit range was given, and `fenced_scope.enable` isn't
   `false` — same source as [integrations.md](integrations.md)'s
   `color_my_ascii.nvim` scope, just without a fixed language to look for.
3. The buffer's own `'filetype'` otherwise (a compound filetype like
   `yaml.docker-compose` is read by its first dotted component).

None of them found: a clear error naming the buffer's filetype (or the
register), not a guess — use `:JSON`/`:YAML`/`:XML` directly instead.

**Scope:** an explicit range (`:5,12JSON compact`) or visual selection
(`'<,'>YAML lines`) always wins. Without one: if the cursor sits inside a
matching ` ```json `/` ```yaml `/` ```xml ` fenced code block and
[color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim) is
installed, that block's interior is the scope (see
[integrations.md](integrations.md)); otherwise the whole buffer. Either way,
only the resolved lines are decoded and replaced — unless `--reg` names a
register as the input instead, in which case the buffer is not read at all and
the range (if any) only says where an `--inplace` result would go. See
[Source and target flags](#source-and-target-flags).

**Errors:** malformed input in the resolved scope leaves the buffer untouched and
reports a notification (`[data] JSON decode failed: ...`) instead of partially
overwriting anything.
