---@module 'data.format'
--- Registry of supported data formats.

local M = {}

---@type table<string, Data.Formatter>
M.formats = {
  json = require("data.format.json"),
  yaml = require("data.format.yaml"),
  xml = require("data.format.xml"),
}

--- Look up a registered formatter by name.
---@param name string
---@return Data.Formatter|nil
function M.get(name)
  return M.formats[name]
end

return M
