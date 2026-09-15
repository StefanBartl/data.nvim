---@module 'data.config'
--- Runtime configuration store for data.nvim.
---
--- Deep-merges user options over `data.config.DEFAULTS` and exposes a single
--- `get(path)` accessor (dot-separated path) so other modules never read a
--- raw options table directly.

local DEFAULTS = require("data.config.DEFAULTS")
local lib_config = require("lib.lua.config")

---@class DataConfigModule
---@field options DataConfig
local M = {}

M.options = DEFAULTS

--- Apply user options. Safe to call once from `setup()`.
---@param opts DataConfig|nil
---@return nil
function M.setup(opts)
  if type(opts) ~= "table" then
    M.options = lib_config.deep_merge(DEFAULTS, {})
  else
    M.options = lib_config.deep_merge(DEFAULTS, opts)
  end
end

--- Read a value by dot-path, e.g. `get("json.indent")`.
---@param path string
---@return any
function M.get(path)
  return lib_config.get(M.options, path)
end

return M
