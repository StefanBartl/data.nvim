---@module 'data.config.DEFAULTS'
--- Immutable default configuration for data.nvim.
---
--- Single source of truth for every configurable value. `data.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.

---@type DataConfig
local DEFAULTS = {
  json = {
    indent = 2,
    sep = ".",
  },
  yaml = {
    indent = 2,
    sep = ".",
  },
  xml = {
    indent = 2,
    sep = ".",
  },
  keymaps = {
    preset = false,
  },
}

return DEFAULTS
