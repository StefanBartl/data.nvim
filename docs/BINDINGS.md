# data.nvim — Binding Cheatsheet

Every user command, keymap, and autocommand `data.nvim` defines. Kept in sync with
`lua/data/bindings/`. Regenerate the usercmd table with
`:lua require("lib.nvim.bindings.usercmd.composer").document("docs/BINDINGS.md")`.

## User Commands

`:JSON [action] [args] [flags]` and `:YAML [action] [args] [flags]` — range-aware
(no range = whole buffer).

| Invocation | Range | Args | Flags | Description |
| --- | --- | --- | --- | --- |
| `:JSON` / `:YAML` | — | — | — | Default action: same as `pretty`. |
| `pretty [indent]` | yes | `indent?: INT` | — | Pretty-print (default 2-space indent). |
| `compact` | yes | — | — | Collapse onto one line. **JSON only.** |
| `lines [--sep=X]` | yes | — | `--sep: STRING` | One `path: value` per leaf, nested keys dotted. |
| `keys [--sep=X]` | yes | — | `--sep: STRING` | Only the (dotted) key paths, no values. |
| `sort [indent]` | yes | `indent?: INT` | — | Pretty-print with object keys sorted (see `docs/commands.md`). |

Full action semantics: [commands.md](commands.md).

## Keymaps

None by default (`data.nvim`'s actions are Ex commands, not motions/toggles) — see
[what-you-get.md](what-you-get.md). `keymaps.preset` in `data.config.DEFAULTS` is
reserved for a future preset.

## Autocommands

None — `data.nvim` only acts on an explicit `:JSON`/`:YAML` invocation.
