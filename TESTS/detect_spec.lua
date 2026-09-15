-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/detect_spec.lua — data.detect (format auto-detection for :Data)

describe("data.detect.format", function()
  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup(nil)

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("falls back to the buffer's filetype when there is no fence", function()
    vim.bo[bufnr].filetype = "json"
    local fmt, err = require("data.detect").format(bufnr, { range = 0 })
    assert.equals("json", fmt)
    assert.is_nil(err)
  end)

  it("reads yaml/xml filetypes the same way", function()
    vim.bo[bufnr].filetype = "yaml"
    local fmt = require("data.detect").format(bufnr, { range = 0 })
    assert.equals("yaml", fmt)

    vim.bo[bufnr].filetype = "xml"
    fmt = require("data.detect").format(bufnr, { range = 0 })
    assert.equals("xml", fmt)
  end)

  it("reads the first component of a compound filetype", function()
    vim.bo[bufnr].filetype = "yaml.docker-compose"
    local fmt = require("data.detect").format(bufnr, { range = 0 })
    assert.equals("yaml", fmt)
  end)

  it("reports a clear error when nothing maps to a format", function()
    vim.bo[bufnr].filetype = "markdown"
    local fmt, err = require("data.detect").format(bufnr, { range = 0 })
    assert.is_nil(fmt)
    assert.matches("could not determine a format", err)
    assert.matches("markdown", err)
  end)

  it("an explicit range still uses the filetype (never guesses a fence)", function()
    vim.bo[bufnr].filetype = "json"
    local fmt = require("data.detect").format(bufnr, { range = 1, line1 = 1, line2 = 1 })
    assert.equals("json", fmt)
  end)
end)

describe("data.detect.format -- fenced-block detection (color_my_ascii)", function()
  -- Optional soft dependency, same "sibling checkout" convention as
  -- scope_resolve_spec.lua's fenced-block section.
  local cma_ok = pcall(require, "color_my_ascii")
  if not cma_ok then
    return
  end

  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup(nil)

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "markdown"
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("detects the format from the fenced block under the cursor", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "before",
      "```yaml",
      "a: 1",
      "```",
      "after",
    })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local fmt, err = require("data.detect").format(bufnr, { range = 0 })
    assert.equals("yaml", fmt)
    assert.is_nil(err)
  end)

  it("falls back to filetype when the cursor is outside any fence", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```yaml", "a: 1", "```", "not fenced" })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local fmt, err = require("data.detect").format(bufnr, { range = 0 })
    assert.is_nil(fmt)
    assert.matches("could not determine a format", err)
  end)

  it("an explicit range skips the fence and uses the filetype instead", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```yaml", "a: 1", "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.bo[bufnr].filetype = "json"
    local fmt = require("data.detect").format(bufnr, { range = 1, line1 = 1, line2 = 1 })
    assert.equals("json", fmt)
  end)

  it("fenced_scope.enable = false disables the fence signal too", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ fenced_scope = { enable = false } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```yaml", "a: 1", "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local fmt, err = require("data.detect").format(bufnr, { range = 0 })
    assert.is_nil(fmt)
    assert.matches("could not determine a format", err)

    package.loaded["data.config"] = nil
    require("data.config").setup(nil)
  end)
end)

describe(":Data", function()
  local bufnr

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("bare :Data pretty-prints using the buffer's filetype", function()
    vim.bo[bufnr].filetype = "json"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"b":2,"a":1}' })
    vim.cmd("Data")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "{", '  "a": 1,', '  "b": 2', "}" }, lines)
  end)

  it(":Data lines works against a yaml-filetype buffer", function()
    vim.bo[bufnr].filetype = "yaml"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user:", "  id: 1" })
    vim.cmd("Data lines")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "user.id: 1" }, lines)
  end)

  it("an unrecognized filetype leaves the buffer untouched and errors clearly", function()
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "just some text" })
    vim.cmd("Data")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "just some text" }, lines)
  end)
end)
