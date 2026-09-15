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

  it("ignores the fenced-block fallback entirely when fmt is not given", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, e0, "no fmt -> whole buffer, never even looks for color_my_ascii")
  end)
end)

describe("data.scope.resolve.lines -- fenced-block scope (color_my_ascii)", function()
  -- Optional soft dependency: see docs/CONTRIBUTING.md's COLOR_MY_ASCII_DIR.
  -- Registering zero `it`s below (rather than failing) is the correct
  -- "skipped" outcome when it isn't present in this test environment.
  local cma_ok = pcall(require, "color_my_ascii")
  if not cma_ok then
    return
  end

  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it(
    "scopes to the enclosing fenced block when the cursor is inside it and no range was given",
    function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "before",
        "```json",
        '{"a":1}',
        "```",
        "after",
      })
      vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- the '{"a":1}' line, 1-indexed
      local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(2, s0)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(2, e0)
    end
  )

  it("does not scope to a fence of a different language", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```yaml", "a: 1", "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0, "a yaml fence doesn't match the json format's fence-language list")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, e0)
  end)

  it("an explicit range still wins over the fenced block", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local s0, e0 = resolve.lines(bufnr, { range = 1, line1 = 1, line2 = 1 }, "json")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, e0)
  end)

  it("fenced_scope.enable = false disables the fallback", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ fenced_scope = { enable = false } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local s0, e0 = resolve.lines(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, e0)

    package.loaded["data.config"] = nil
    require("data.config").setup(nil)
  end)

  it("falls back to whole-buffer when bufnr isn't the current window's buffer", function()
    -- Regression: the cursor is read from the *current* window, which
    -- only means anything for `bufnr` when that window actually displays
    -- it. A hidden buffer with its own fence (never focused) must not
    -- borrow whatever the currently-focused window's cursor happens to be.
    local other_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(other_bufnr, 0, -1, false, {
      "```json",
      '{"a":1}',
      "```",
    })
    -- bufnr (from before_each) stays the current buffer; put its cursor
    -- inside where a fence interior would be, to prove it's ignored too.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local s0, e0 = resolve.lines(other_bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, s0)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, e0, "whole other_bufnr (3 lines), not a fenced guess from bufnr's cursor")

    vim.api.nvim_buf_delete(other_bufnr, { force = true })
  end)
end)
