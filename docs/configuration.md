# Configuration

Every option `setup()` accepts, with its default (`data.config.DEFAULTS`):

```lua
require("data").setup({
  json = {
    indent = 2,   -- default indent width for `:JSON pretty`/`:JSON sort`
    sep = ".",    -- default path separator for `:JSON lines`/`:JSON keys`
  },
  yaml = {
    indent = 2,   -- default indent width for `:YAML pretty`/`:YAML sort`
    sep = ".",    -- default path separator for `:YAML lines`/`:YAML keys`
  },
  xml = {
    indent = 2,   -- default indent width for `:XML pretty`/`:XML sort`
    sep = ".",    -- default path separator for `:XML lines`/`:XML keys`
  },
  fenced_scope = {
    enable = true, -- scope to an enclosing ```json/```yaml/```xml block when color_my_ascii is installed
  },
  register = {
    default = "+", -- which register a bare `--reg` / `--out-reg` reads from / writes to
  },
  target = {
    split = "right", -- where `--split` opens: "above"|"below"|"left"|"right"|"auto"
  },
  preview = {
    filter = false,   -- diff the result before an in-place `filter` replaces the scope
    view = "inline",  -- diff.nvim view for that preview: "inline" (a split) or "float"
  },
  keymaps = {
    preset = false, -- reserved: no default keymap preset exists yet
  },
})
```

`indent`/`sep` are also overridable per invocation (`:JSON pretty 4`,
`:YAML lines --sep=/`) — the config values are only the fallback when neither is
given.

`fenced_scope.enable = false` always uses whole-buffer scope, even with
`color_my_ascii.nvim` installed and the cursor inside a matching fence — see
[integrations.md](integrations.md).

`register.default` is the register a bare `--reg`/`--out-reg` uses; `--reg=x`
names one explicitly and ignores this. `+` is the system clipboard — the case
the register scope exists for is "I copied a payload out of a ticket tool". On
a Neovim without a clipboard provider, `+` is permanently empty, so a *bare*
`--reg` falls back to `"` and says so; an explicitly typed `--reg=+` is left
alone and fails with the ordinary "register is empty" message instead, because
that one was the user's own choice. See
[commands.md](commands.md#source-and-target-flags).

`target.split` is where `--split` (and a register source's default target)
opens its scratch window. `"auto"` — or any value that isn't one of the four
directions — uses a plain `:new`, honoring your own `'splitbelow'`/
`'splitright'`.

`preview.filter = true` makes every in-place `filter` show a
[diff.nvim](https://github.com/StefanBartl/diff.nvim) before/after diff and ask
before writing; `--preview`/`--no-preview` override it per invocation. It
requires diff.nvim — with the preview on and diff.nvim missing, `filter` reports
that and writes nothing, rather than quietly filtering unseen. `preview.view`
picks `inline` (a split) or `float`; side-by-side views are not offered, and
[integrations.md](integrations.md#diffnvim--filter---preview) says why.

`keymaps.preset` is a placeholder for a future default keymap set; setting it to
`true` today has no effect, since none is defined (see
[what-you-get.md](what-you-get.md)).
