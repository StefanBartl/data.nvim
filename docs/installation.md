# Installation

## lazy.nvim

```lua
{
  "StefanBartl/data.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "JSON", "YAML", "XML", "Data" },
  opts = {},
},
```

`cmd = { "JSON", "YAML", "XML", "Data" }` lazy-loads on first use of any of the four
commands `setup()` registers -- list all four, not just `"JSON"`: lazy.nvim only
loads the plugin (and so only defines a command) when you run one it was told to
trigger on, so a trimmed list would leave e.g. `:YAML` reporting "not an editor
command" the first time you reach for it. Drop `cmd` entirely (or add `ft`) if
you'd rather load it eagerly or on a filetype.

## packer.nvim

```lua
use({
  "StefanBartl/data.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("data").setup()
  end,
})
```

Either way, `require("data").setup()` (directly, or implicitly via `opts` under
lazy.nvim) is what registers `:JSON`/`:YAML`/`:XML`/`:Data` — see
[configuration.md](configuration.md) for every option `setup()` accepts.
