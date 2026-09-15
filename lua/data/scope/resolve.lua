---@module 'data.scope.resolve'
--- Resolve which buffer lines a `:JSON`/`:YAML`/`:XML` invocation should act
--- on: an explicit range (visual selection or `:N,M`), or the whole buffer.
---
--- Register scope (`--reg=`, scratch-split output) is Phase 1 in the
--- project's concept and not implemented here yet -- this module only
--- resolves an in-buffer line span.

local M = {}

--- 0-based, inclusive line span for `cmd`'s invocation against `bufnr`.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@return integer start0
---@return integer end0
function M.lines(bufnr, cmd)
  if cmd.range and cmd.range > 0 then
    return cmd.line1 - 1, cmd.line2 - 1
  end
  return 0, math.max(0, vim.api.nvim_buf_line_count(bufnr) - 1)
end

return M
