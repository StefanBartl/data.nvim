# What you get with the defaults

Calling `require("data").setup()` with no arguments (or `opts = {}` under lazy.nvim):

- `:JSON` and `:XML` (six actions each: `pretty`, `compact`, `lines`, `keys`,
  `sort`, `filter`) and `:YAML` (the same five, minus `compact`) are registered
  and ready — see [commands.md](commands.md).
- `:Data` is also registered: `pretty`/`lines`/`keys`/`sort`/`filter` with the
  format auto-detected (fenced block, register contents under `--reg`, else
  buffer filetype) instead of named by the command — see
  [commands.md](commands.md#data--format-auto-detected).
- No default keymaps and no default autocmds are bound. data.nvim's actions are Ex
  commands, not motions or toggles, so there is nothing to bind by default (see
  `data.config.DEFAULTS`'s `keymaps.preset`, currently always `false`).
- `<Tab>` completion on every `:JSON`/`:YAML`/`:XML`/`:Data` subcommand and flag,
  for free (the composer command layer — see [architecture.md](architecture.md)).
- `pretty` defaults to 2-space indent; override per-invocation (`:JSON pretty 4`)
  or via [configuration.md](configuration.md)'s `json.indent`/`yaml.indent`/`xml.indent`.
- `lines`/`keys` default to `.` as the path separator; override per-invocation
  (`:YAML lines --sep=/`) or via `json.sep`/`yaml.sep`/`xml.sep`.
- `:JSON` also gets `ndjson` (pretty-print one-object-per-line logs) and
  `to yaml` (`:YAML` gets `to json`) — see [commands.md](commands.md).
- With no range given, a cursor inside a matching fenced code block scopes to
  that block instead of the whole buffer, if
  [color_my_ascii.nvim](https://github.com/StefanBartl/color_my_ascii.nvim) is
  installed — see [integrations.md](integrations.md). A total no-op without it.
- `filter` (on any of the four commands) needs
  [pickers.nvim](https://github.com/StefanBartl/pickers.nvim) installed —
  every other action works regardless. See [integrations.md](integrations.md).
- Every action takes `--reg`/`--reg=<name>` to read from a register instead of
  the buffer, and `--inplace`/`--split`/`--out-reg=<name>` to say where the
  result goes. The defaults need no flags at all: a buffer or selection scope
  replaces itself, a register source opens a scratch split. A bare `--reg`
  means the system clipboard (`register.default`), and `--split` opens to the
  right (`target.split`) — see
  [commands.md](commands.md#source-and-target-flags).
