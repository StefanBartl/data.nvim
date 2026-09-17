# data.nvim — Binding Cheatsheet

Every user command, keymap, and autocommand `data.nvim` defines. Kept in sync with
`lua/data/bindings/`. `lib.nvim.bindings.usercmd.composer`'s own
`.document("path.md")` regenerates a *complete* replacement file in its own
per-verb layout — useful as a cross-check while editing routes, not for
regenerating this hand-maintained page, whose format (one shared table, a
`filter`/`:Data` row where they'd otherwise be duplicated four times, the
Keymaps/Autocommands sections) predates and diverges from that generator's own
output shape. Update the table below by hand alongside `bindings/usrcmds.lua`.

## User Commands

`:JSON`, `:YAML`, `:XML`, each `[action] [args] [flags]` — range-aware (no range =
whole buffer). `:Data` is a fourth, format-auto-detecting verb — see its own
section below.

Every action below additionally accepts the four source/target flags
(`--reg`, `--inplace`, `--split`, `--out-reg`) listed in their own table
underneath; the "Flags" column names only what is specific to that action.

| Invocation | Range | Args | Flags | Description |
| --- | --- | --- | --- | --- |
| `:JSON` / `:YAML` / `:XML` | — | — | — | Default action: same as `pretty`. Bare form only — flags need an explicit action. |
| `pretty [indent]` | yes | `indent?: INT` | — | Pretty-print (default 2-space indent). |
| `compact` | yes | — | — | Collapse onto one line. **JSON and XML only.** |
| `lines [--sep=X]` | yes | — | `--sep: STRING` | One `path: value` per leaf, nested keys dotted. |
| `keys [--sep=X]` | yes | — | `--sep: STRING` | Only the (dotted) key paths, no values. |
| `sort [indent]` | yes | `indent?: INT` | — | Pretty-print with object keys sorted (see `docs/commands.md`). |
| `ndjson [indent]` | yes | `indent?: INT` | — | **`:JSON` only.** Pretty-print each line as its own JSON object. |
| `to yaml` | yes | `format: STRING` | — | **`:JSON` only.** Convert the scope to YAML. |
| `to json` | yes | `format: STRING` | — | **`:YAML` only.** Convert the scope to JSON. |
| `filter [--sep=X]` | yes | — | `--sep: STRING` | Interactively filter flattened path/value entries. **Requires pickers.nvim.** |

### Source / target flags (every action, every verb)

| Flag | Value | What it does |
| --- | --- | --- |
| `--reg` / `--reg=<name>` | optional STRING | Read the input from a register instead of the buffer. Bare form = `register.default` (`+`). |
| `--inplace` | — | Replace the buffer scope. Default for a buffer/selection source. |
| `--split` | — | Open the result in a scratch split. Default for a register source. |
| `--out-reg` / `--out-reg=<name>` | optional STRING | Write the result into a register. Bare form = `register.default`. |

The three target flags are mutually exclusive. `--reg --inplace` additionally
requires an explicit range or visual selection. Full semantics:
[commands.md](commands.md#source-and-target-flags).

Full action semantics: [commands.md](commands.md).

## `:Data` — format auto-detected

`:Data [action] [args] [flags]` — same range-awareness as above, same
`pretty`/`lines`/`keys`/`sort`/`filter` rows from the table above (no
`compact`/`ndjson`/`to`: those are already format-specific by nature). The
format comes from the enclosing fenced block's language tag, the register's
own first non-blank line under `--reg`, or the buffer's `'filetype'` otherwise
— see [commands.md](commands.md#data--format-auto-detected). Neither found: a
clear error, not a guess.

## Keymaps

None by default (`data.nvim`'s actions are Ex commands, not motions/toggles) — see
[what-you-get.md](what-you-get.md). `keymaps.preset` in `data.config.DEFAULTS` is
reserved for a future preset.

## Autocommands

None — `data.nvim` only acts on an explicit `:JSON`/`:YAML`/`:XML`/`:Data` invocation.
