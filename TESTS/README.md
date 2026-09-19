# TESTS/

data.nvim's automated suite: plenary.nvim's busted-compatible harness
(`describe`/`it`/`before_each`, luassert assertions), one file per concern,
every file named `*_spec.lua`.

## Table of content

- [Running it](#running-it)
- [What the layout means](#what-the-layout-means)
- [Coverage by module](#coverage-by-module)
- [Deliberately not covered, and why](#deliberately-not-covered-and-why)
- [Things pinned as behaviour rather than fixed](#things-pinned-as-behaviour-rather-than-fixed)
- [Conventions to keep](#conventions-to-keep)

## Running it

```sh
scripts/test.sh                       # every spec under TESTS/
scripts/test.sh TESTS/api_spec.lua    # one file
```

`scripts/test.sh` wraps `nvim --clean --headless -u scripts/minimal_init.lua`;
that bootstrap file documents how each dependency is found and why `-u` and
`--clean` both matter. CI runs exactly this script, on Linux **and** Windows.

Dependencies, all resolved by `scripts/minimal_init.lua` from an env var, a
`.deps/<name>` checkout, or a sibling directory:

| Dependency | Env var | Required? |
|---|---|---|
| lib.nvim | `LIB_NVIM_DIR` | **yes** — `data.*` modules require it directly |
| plenary.nvim | `PLENARY_DIR` | **yes** — the harness itself |
| color_my_ascii.nvim | `COLOR_MY_ASCII_DIR` | no — fenced-block scope |
| pickers.nvim | `PICKERS_DIR` | no — `filter` |
| diff.nvim | `DIFF_DIR` | no — `filter --preview` |

A spec that needs an optional dependency checks `pcall(require, ...)` itself
and registers zero `it`s when it is absent — which is the correct "skipped"
outcome, not a failure. **Every such spec has a counterpart that runs
everywhere**, driving the same code against a double (`filter_failure_spec.lua`
for `filter_spec.lua`, `preview_failure_spec.lua` for `preview_spec.lua`,
`filter_lifecycle_spec.lua` for both), so no arm of this plugin is covered
*only* on a machine that happens to have all three installed.

`PlenaryBustedDirectory` gives each spec file its own child nvim process, so
files cannot leak state into each other. Within a file they can, and the
specs that replace a `package.loaded` entry restore it in the same `it` or in
`after_each`.

## What the layout means

Three kinds of file, and it is worth knowing which you are looking at:

- **`*_spec.lua` against the real thing** — `usrcmds_spec.lua`,
  `usrcmds_io_spec.lua`, `detect_spec.lua`, `format_*_spec.lua` drive real
  buffers, real registers and the real `:JSON`/`:YAML`/`:XML`/`:Data` commands.
- **`*_spec.lua` against a double** — `filter_failure_spec.lua`,
  `preview_failure_spec.lua`, `filter_lifecycle_spec.lua`,
  `health_deps_spec.lua`, parts of `scope_sink_failure_spec.lua`. A double is
  used only where the real collaborator cannot produce the state under test (a
  diff.nvim that renders nothing, a refine handle that throws, an outdated
  lib.nvim) or where it would make the test depend on what is installed.
- **BUG-marked blocks** — a failure that was found, deliberately *not* fixed,
  and pinned so a fix has something to flip. See
  [below](#things-pinned-as-behaviour-rather-than-fixed).

Doubles are always installed into `package.loaded` **before** the module under
test requires them. Where that is safe is a property of the source: `data.init`
binds `config`/`format`/`scope.source`/`scope.sink` to upvalues at load time
(so those need a fresh `require` after the swap), while `data.filter`,
`data.preview` and `data.scope.sink`'s split path all `pcall(require, ...)`
*inside* the function, which is what makes a call-time swap work at all.

## Coverage by module

| Module | Specs |
|---|---|
| `init.lua` (`run`/`convert`/`filter`/`run_auto`/`setup`) | `api_spec`, `usrcmds_spec`, `usrcmds_io_spec`, `filter_lifecycle_spec`, `malformed_spec` |
| `format/init.lua` | `format_spec` |
| `format/json.lua` | `format_json_spec`, `format_roundtrip_spec`, `malformed_spec`, `oneline_spec` |
| `format/yaml.lua` | `format_yaml_spec`, `format_roundtrip_spec`, `malformed_spec` |
| `format/xml.lua` | `format_xml_spec`, `format_roundtrip_spec`, `malformed_spec` |
| `detect/init.lua` | `detect_spec`, `usrcmds_io_spec`, `api_spec`, `malformed_spec` |
| `filter/init.lua` | `filter_spec` (real pickers), `filter_failure_spec` (doubles) |
| `preview.lua` | `preview_spec` (real diff.nvim), `preview_failure_spec` (doubles) |
| `scope/resolve.lua` | `scope_resolve_spec`, `scope_source_spec` |
| `scope/source.lua` | `scope_source_spec` |
| `scope/sink.lua` | `scope_sink_spec`, `scope_sink_failure_spec`, `malformed_spec` |
| `scope/register.lua` | `scope_register_spec`, `scope_register_edge_spec` |
| `config/init.lua` + `DEFAULTS.lua` | `config_spec`, `config_validate_spec` |
| `util/oneline.lua` | `oneline_spec` |
| `util/safe_call.lua` | `safe_call_spec` |
| `health.lua` | `health_spec`, `health_deps_spec` |
| `bindings/*` | `bindings_spec`, `routes_spec` |

Worth calling out, because each took a file of its own to get at:

- **Malformed and degenerate input** (`malformed_spec`). Empty, whitespace-only,
  truncated, trailing-comma, single-quoted, BOM-prefixed, CRLF, `NaN`,
  `-Infinity`, duplicate keys, nesting at and past the guard's limit, and values
  the encoder refuses — per format, at the formatter and again end to end
  through the command. The invariant is always the same: reported, with the
  scope untouched.
- **The truthy-`null` trap** (`malformed_spec`). `vim.json.decode("null")`
  returns a *truthy* userdata sentinel, so a `if not parsed` guard never fires
  for it — a mistake that has caused real bugs in sibling plugins. data.nvim
  branches on the returned `err` instead, and `lib.nvim.json` normalizes the
  sentinel into `lib.lua.null`; both halves are pinned.
- **A failed write leaves the scope byte-identical** (`malformed_spec`). This
  plugin does **no filesystem I/O at all** — no `readfile`/`writefile`, no
  `mkdir`, no `uv.fs_*` — so the "unwritable path / unmakeable parent
  directory / raw `E739`" family that dominates its siblings does not exist
  here. The equivalent property is that a write either fully replaces the
  scope or does not touch it: driven through all three ways a target can
  refuse (a vanished buffer, a locked one, an unrepresentable value).
- **The filter extmark's whole lifecycle** (`filter_lifecycle_spec`). It lives
  in a module-level namespace, so a leaked mark is permanent for the session.
  Every exit path — committed, cancelled, nothing matched, errored, preview
  applied/discarded/unrenderable, `--split`, `--out-reg`, ten runs in a row —
  ends with an empty namespace.
- **The command surface** (`routes_spec`). Which subcommand each verb offers,
  which flags each *route* accepts, and what `<Tab>` completes to. Flags are
  per-route (`--sep` on `lines`/`keys`/`filter`, `--preview` on `filter`
  alone), and a route that accepted a flag it ignores would be worse than one
  that rejects it. This also pins the leak-free property `with_io`'s
  fresh-list comment exists for: the flag spec tables are shared across every
  route of every verb, and an in-place append anywhere would show up as
  `--sep` being accepted where it does nothing.
- **`health.lua`'s structure** (`health_deps_spec`). Driven with *every*
  dependency unavailable at once, because the recurring defect in sibling
  repos is a check that reports a dependency missing and then reaches into it
  on the next line. data.nvim does not: every arm stays behind its own guard.

## Deliberately not covered, and why

- **`lua/data/@types/init.lua`** — `---@meta` annotations only. No runtime code.
- **`lua/data/bindings/keymaps.lua`, `lua/data/bindings/autocmds.lua`** —
  deliberate no-op stubs (`NEW-08`: the wiring point should a preset or an
  opt-in autocmd ever be added). `bindings_spec.lua` asserts exactly that:
  they neither error nor register anything.
- **`config/DEFAULTS.lua` as a data table** — no branches to exercise. What
  *is* checked is its contract with the rest of the plugin:
  `config_validate_spec.lua` asserts every dot-path the source actually reads
  resolves to a default, and that `setup()` never mutates the table.
- **The real pickers.refine prompt UI and the real diff.nvim renderer** — the
  window geometry, highlighting and key handling belong to those plugins.
  data.nvim's side of each contract is pinned instead: the items and field
  accessors handed to `refine.new`, and the exact `source=/target=/view=/output=`
  specifier handed to `diff.run`. `preview_spec.lua` does verify the rendered
  diff's `---`/`+++` header, because that header comes from data.nvim's own
  holder-buffer names.
- **`preview.view = "tab"`'s teardown** — the other four views are checked for
  window and buffer leaks in a loop; `tab` is left out of *that* loop because
  closing the last window of a tabpage inside a headless run is fragile for
  reasons unrelated to what is being tested. The specifier for `view=tab` **is**
  asserted (`preview_failure_spec.lua`), and the "never delete a buffer we
  merely found" regression is driven against exactly the shape an older
  diff.nvim's `view=tab` produced.
- **`health.lua`'s `health.report_*` legacy fallbacks** — the
  `vim.health.start or health.report_start` chain targets Neovim older than the
  version this plugin requires; unreachable on any supported version.
- **Clipboard provider behaviour itself** — `scope_register_edge_spec.lua`
  simulates `has("clipboard") == 0` rather than depending on whether the
  machine running the suite has a provider.
- **A register holding binary data** — `scope_register_spec.lua` stubs
  `getreg` for this and says so in the test: no register reachable through
  `setreg` produces a Blob, since `setreg` rejects a NUL byte itself. The guard
  is defensive, and the test is labelled as covering a defensive guard.

## Things pinned as behaviour rather than fixed

Each of these has a `BUG:`-prefixed `describe` or `it` and a comment saying
where the defect lives. They are pinned, not fixed, because each would change
user-visible behaviour or lives in a dependency — a fix flips the assertion.

1. **`:checkhealth data` reports two errors on a fully working install**
   (`health_deps_spec.lua`). `lib.lua.yaml.encode` and `lib.lua.xml.encode` are
   callable *tables* (`__call` plus members like `encode.pretty`, which
   `format/xml.lua` calls by name), and `health.lua` gates both on
   `type(...) == "function"`. So the check says "lib.nvim is outdated", at error
   level, while `:YAML` and `:XML` work — as the rest of the suite proves in the
   same process. **data.nvim's own bug**; the assertion pins the count at two, so
   a fix takes it to zero and any *new* false error fails there instead of
   hiding behind these.
2. **`:YAML` over a blank scope silently deletes it** (`malformed_spec.lua`).
   Whitespace decodes to `{}`, `render` turns `{}` into zero lines, and the
   in-place write replaces the span with those zero lines. `:2YAML pretty` on a
   blank line removes it, with no notification. `:JSON` and `:XML` refuse the
   identical input with a decode error — controls for both are next to it.
3. **A UTF-8 BOM is never stripped, and only YAML fails quietly**
   (`malformed_spec.lua`). JSON and XML report a confusing "character 1" /
   "position 1" error; YAML glues the BOM onto the first key's *name* and
   reports success, so `:YAML lines` emits a corrupt path. `data.detect.from_text`
   also returns nil for BOM'd text, so `:Data --reg=+` on BOM'd clipboard
   contents cannot classify it. Note that `data.scope.register.read` already
   normalizes CRLF away, arguing it "is an artifact of where the text came from,
   not content" — a BOM is the same artifact from the same source.
4. **An empty JSON object is silently rewritten as an empty array**
   (`format_roundtrip_spec.lua`). `vim.json.decode` marks `{}` with
   `vim.empty_dict()`'s metatable and leaves `[]` plain, and
   `lib.nvim.json.decode` carries that through — then `lib.lua.json.encode`
   ignores it and writes `[]` for both. For most consumers of a config file that
   is a type change, not a formatting change. The existing round-trip fixture
   `{"empty_obj":{},"empty_arr":[]}` **passes** while this happens, because
   `assert.same` compares contents and both are empty; the new block asserts on
   the metatable instead. Defect in lib.nvim's encoder.
5. **Replacing the scope line-wise mid-prompt inverts the extmark**
   (`filter_lifecycle_spec.lua`). The mark is created as `(s0,0)`–`(e0+1,0)`;
   when `nvim_buf_set_lines` replaces exactly that span, Neovim moves the start
   past the collapsed end, so `M.filter` asks for `[1, 0)` and the write fails
   with `could not write the result: 'start' is higher than 'end'`. The filter
   result is discarded and the message names an API constraint — the very
   outcome the surrounding `pcall`'s own comment says it was added to avoid. The
   trigger is a line-wise buffer rewrite (format-on-save, an applied LSP edit,
   another plugin), not an exotic one. `:s///`, partial replacements,
   deletions and insertions above the scope all work — pinned as controls, so
   a fix has both sides to aim at. (A character-level edit, `nvim_buf_set_text`
   included, used to fall through this same gap silently — the extmark stays
   intact, so nothing caught it — but that half is now fixed: `M.filter`
   re-reads the scope's live content, not just its position, and refuses the
   write when it no longer matches what the result was computed from.)
6. **A tab-indented YAML child is silently promoted to the document root**
   (`malformed_spec.lua`). `a:` + a tab-indented `b: 1` decodes to `{b = 1}`:
   the parent key is *gone*, with no error. Defect in
   `lib.lua.yaml.simple_parse`; pinned here because `:YAML` is where a user
   meets it.

Also documented as behaviour rather than flagged (not defects, but each looks
like one until you know):

- `lines`/`keys` on a scalar or `null` root render a path-less `": null"` — and
  `keys` a single empty line — because `path_flatten` treats a scalar root as
  one leaf with an empty path.
- The JSON decoder accepts `NaN`/`-Infinity`, which the encoder then refuses
  with "cannot encode NaN": a document can be read and then decline to be
  written back. Reported cleanly either way.
- The effective maximum JSON nesting depth is **64** (the null normalizer's
  guard), well below the parser's own limit, and the message mentions null
  normalization.
- `data.setup()` **resets** rather than accumulating: `DEFAULTS` is the merge
  base on every call, so an option set only by an earlier call is gone. (The
  opposite was a real bug in replacer.nvim.)
- The composer silently drops a surplus positional argument, so `:JSON lines 4`
  runs a plain `lines` without a word. Leniency owned by lib.nvim's composer.
- The bare form of a verb (`:JSON` with no subcommand) does not thread IO
  flags, so `:JSON --split` is a plain pretty-print. `:JSON pretty --split` is
  how a split is requested.

## Conventions to keep

- Every spec file starts with `---@diagnostic disable: need-check-nil` and a
  one-line comment saying what it covers. Test code *should* crash and name the
  culprit when a require or a decode comes back nil; the nil guards LuaLS asks
  for would hide exactly what the spec exists to catch.
- A test double set on `vim.notify`/`vim.ui.select`/`vim.fn.*` carries
  `---@diagnostic disable-next-line: duplicate-set-field` and a comment saying
  where it is restored. Restore it in the same `it` or in `after_each`, never
  later — an uncaught error inside an `it` skips whatever cleanup follows it and
  leaks the stub into every later test in the file.
- Byte sequences that matter are **built**, never written literally:
  `string.char(92)` for a backslash, `string.char(239, 187, 191)` for a BOM.
  Whether a raw one survives to mean itself depends on every layer that touched
  the file, and getting it wrong produces a test that passes for the wrong
  reason — an earlier draft of `oneline_spec.lua` put a real newline inside a
  JSON string literal, which is invalid JSON the decoder happened to tolerate.
- Fixtures live in buffers, registers and `package.loaded` — nothing here
  touches the filesystem, and nothing touches the repository.
- Both gates are `stylua --check .` and `luacheck .`, and **both include
  `TESTS/`**. Run them before pushing; CI runs exactly those.
