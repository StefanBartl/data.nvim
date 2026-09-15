---@module 'data.format'
--- Registry of supported data formats.

local M = {}

---@internal
--- `pcall`-wrapped so one missing `lib.nvim` submodule degrades only its
--- own format, not the whole registry -- `data.health` already reports
--- `tables.path_flatten`/`yaml.encode`/`lib.lua.xml` as independently
--- present-or-absent (each shipped alongside the data.nvim feature that
--- needs it), so a `lib.nvim` install missing just `lib.lua.xml` must not
--- also take `:JSON`/`:YAML` down with it via one shared `require`.
---@param name string
---@param modpath string
local function try_register(name, modpath)
  local ok, mod = pcall(require, modpath)
  if ok then
    M.formats[name] = mod
  end
end

---@type table<string, Data.Formatter>
M.formats = {}
try_register("json", "data.format.json")
try_register("yaml", "data.format.yaml")
try_register("xml", "data.format.xml")

--- Look up a registered formatter by name.
---@param name string
---@return Data.Formatter|nil
function M.get(name)
  return M.formats[name]
end

return M
