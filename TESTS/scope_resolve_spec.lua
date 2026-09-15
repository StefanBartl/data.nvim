---@diagnostic disable: need-check-nil
-- TESTS/scope_resolve_spec.lua — data.scope.resolve

local resolve = require("data.scope.resolve")

describe("data.scope.resolve.lines", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns the whole buffer when no range was given", function()
    local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(4, e0, "last 0-based line index of a 5-line buffer")
  end)

  it("returns the explicit 1-based range converted to 0-based inclusive", function()
    local s0, e0 = resolve.lines(bufnr, { range = 2, line1 = 2, line2 = 4 })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(1, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(3, e0)
  end)

  it("does not error on an empty buffer with no range", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, e0, "nvim_buf_line_count of a scratch buffer is never 0 (one blank line)")
  end)
end)
