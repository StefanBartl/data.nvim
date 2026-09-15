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

`keymaps.preset` is a placeholder for a future default keymap set; setting it to
`true` today has no effect, since none is defined (see
[what-you-get.md](what-you-get.md)).
