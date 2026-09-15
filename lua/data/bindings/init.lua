---@module 'data.bindings'
--- Orchestrates data.nvim's bindings: user commands, keymaps, autocmds.

local M = {}

--- Wire up every binding for the resolved config.
---@return nil
function M.setup()
  require("data.bindings.usrcmds").setup()
  local cfg = require("data.config").get_all()
  require("data.bindings.keymaps").setup(cfg)
  require("data.bindings.autocmds").setup(cfg)
end

return M
