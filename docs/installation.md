# Installation

## lazy.nvim

```lua
{
  "StefanBartl/data.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "JSON" },
  opts = {},
},
```

`cmd = { "JSON" }` lazy-loads on first use of the command; drop it (or add `ft`) if
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
lazy.nvim) is what registers `:JSON` — see [configuration.md](configuration.md) for
every option `setup()` accepts.
