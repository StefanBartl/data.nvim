---@module 'data.format'
--- Registry of supported data formats. Only "json" is implemented (Phase 0
--- of the project concept); "yaml"/"xml" need a YAML encoder and an XML
--- module in lib.nvim first (neither exists yet) and are staged for later.

local M = {}

---@type table<string, Data.Formatter>
M.formats = {
  json = require("data.format.json"),
}

--- Look up a registered formatter by name.
---@param name string
---@return Data.Formatter|nil
function M.get(name)
  return M.formats[name]
end

return M
