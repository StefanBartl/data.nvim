---@module 'data.bindings.autocmds'
--- No default autocmds: data.nvim only acts on an explicit `:JSON`
--- invocation, never automatically on buffer events. This module exists
--- (`NEW-08`) as the wiring point should an opt-in autocmd (e.g. detecting a
--- pasted JSON blob) be added later.

local M = {}

--- Register autocmds for the resolved config.
---@param _cfg DataConfig
---@return nil
function M.setup(_cfg)
  -- Reserved: no default autocmds are defined yet.
end

return M
