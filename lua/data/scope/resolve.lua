---@module 'data.scope.resolve'
--- Resolve which buffer lines a `:JSON`/`:YAML`/`:XML` invocation should act
--- on: an explicit range (visual selection or `:N,M`) wins; otherwise, when
--- the cursor sits inside a matching fenced code block
--- (` ```json `/` ```yaml `/` ```xml `) and
--- [`color_my_ascii`](https://github.com/StefanBartl/color_my_ascii.nvim) is
--- installed, that block's interior becomes the scope; otherwise the whole
--- buffer. Purely additive soft integration: no color_my_ascii, no matching
--- fence, or `fenced_scope.enable = false` all fall back to the previous
--- whole-buffer behavior unchanged.
---
--- Register scope (`--reg=`, scratch-split output) is Phase 1 in the
--- project's concept and not implemented here yet -- this module only
--- resolves an in-buffer line span.

local M = {}

---@internal
--- Fence language tags accepted per data.nvim format name.
---@type table<string, string[]>
local FENCE_LANGS = {
  json = { "json", "jsonc" },
  yaml = { "yaml", "yml" },
  xml = { "xml" },
}

---@internal
--- The interior of the fenced block (of a language matching `fmt`) enclosing
--- the cursor, if any -- nil when color_my_ascii isn't installed, `fmt` has
--- no fence-language mapping, or no such block contains the cursor.
---@param bufnr integer
---@param fmt string
---@return integer|nil start0
---@return integer|nil end0
local function fenced_block_scope(bufnr, fmt)
  local langs = FENCE_LANGS[fmt]
  if not langs then
    return nil, nil
  end
  local ok, cma = pcall(require, "color_my_ascii")
  if not ok or type(cma.fences) ~= "table" then
    return nil, nil
  end
  local row0 = vim.api.nvim_win_get_cursor(0)[1] - 1
  local block = cma.fences.block_at(bufnr, row0, { lang = langs })
  if not block or block.content_end <= block.content_start then
    return nil, nil
  end
  return block.content_start, block.content_end - 1
end

--- 0-based, inclusive line span for `cmd`'s invocation against `bufnr`.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@param fmt? string # "json"|"yaml"|"xml" -- enables the fenced-block fallback when given
---@return integer start0
---@return integer end0
function M.lines(bufnr, cmd, fmt)
  if cmd.range and cmd.range > 0 then
    return cmd.line1 - 1, cmd.line2 - 1
  end

  if fmt and require("data.config").get("fenced_scope.enable") ~= false then
    local s0, e0 = fenced_block_scope(bufnr, fmt)
    if s0 then
      ---@cast e0 integer
      return s0, e0
    end
  end

  return 0, math.max(0, vim.api.nvim_buf_line_count(bufnr) - 1)
end

return M
