-- Test code: when something here comes back nil -- a require, a scope
-- resolution -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/scope_source_spec.lua — data.scope.source, which had no spec of its
-- own: it was only ever exercised through the command layer, where a failure
-- shows up as a notification rather than as the `(nil, Data.Problem)` pair
-- this module's contract is actually written in.
--
-- The interesting part of that contract is the asymmetry the module's own doc
-- comment argues for: a register source records the buffer span an explicit
-- range picked out, but ONLY when a range was actually given -- because
-- `--reg --inplace` with no range would mean "replace the whole file with the
-- clipboard", and the refusal for that lives one module over, in
-- data.scope.sink, which needs `s0 == nil` to recognize the case.

local source = require("data.scope.source")

describe("data.scope.source.resolve -- a buffer source", function()
  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reads the whole buffer when no range was given", function()
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 })
    assert.is_nil(problem)
    assert.equals("buffer", src.kind)
    assert.same({ "a", "b", "c" }, src.lines)
    assert.equals(0, src.s0)
    assert.equals(2, src.e0)
    assert.equals(bufnr, src.bufnr)
    assert.is_nil(src.reg, "no register is involved")
  end)

  it("reads only the range when one was given", function()
    local src = source.resolve(bufnr, { range = 2, line1 = 2, line2 = 3 })
    assert.same({ "b", "c" }, src.lines)
    assert.equals(1, src.s0)
    assert.equals(2, src.e0)
  end)

  it("reports a range past the end of the buffer as a WARNING, not an error", function()
    -- The only way to reach the empty-lines guard: a scratch buffer always has
    -- at least one (blank) line, so `#lines == 0` needs a span that starts
    -- beyond the last line. Level matters -- "you selected nothing" is not the
    -- same as "your document is broken".
    local src, problem = source.resolve(bufnr, { range = 2, line1 = 10, line2 = 12 })
    assert.is_nil(src)
    assert.equals("warn", problem.level)
    assert.matches("empty range", problem.msg)
  end)

  it("does not report an empty scratch buffer -- it has one blank line", function()
    local empty = vim.api.nvim_create_buf(false, true)
    local src, problem = source.resolve(empty, { range = 0, line1 = 1, line2 = 1 })
    assert.is_nil(problem)
    assert.same({ "" }, src.lines, "one blank line is content as far as this module is concerned")
    vim.api.nvim_buf_delete(empty, { force = true })
  end)

  it("never carries a note for a plain buffer scope", function()
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 })
    assert.is_nil(src.note, "a note is a register-resolution remark, nothing else")
  end)
end)

describe("data.scope.source.resolve -- a register source", function()
  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
    vim.fn.setreg("r", '{"a":1}', "c")
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reads the register and records which one it was", function()
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", {
      reg = "r",
    })
    assert.is_nil(problem)
    assert.equals("register", src.kind)
    assert.same({ '{"a":1}' }, src.lines)
    assert.equals("r", src.reg)
  end)

  it("still records the invoking buffer, because --inplace may target it", function()
    local src = source.resolve(bufnr, { range = 2, line1 = 2, line2 = 2 }, "json", { reg = "r" })
    assert.equals(bufnr, src.bufnr, "the --inplace target, whatever the source was")
  end)

  it("records the span an explicit range picked out", function()
    local src = source.resolve(bufnr, { range = 2, line1 = 2, line2 = 3 }, "json", { reg = "r" })
    assert.equals(1, src.s0)
    assert.equals(2, src.e0)
  end)

  it("leaves the span nil with no range, which is what sink's refusal keys on", function()
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", { reg = "r" })
    assert.is_nil(src.s0, "no scope to replace")
    assert.is_nil(src.e0)
  end)

  it("leaves the span nil for range = 0 even when line1/line2 are set", function()
    -- `range` is the only field that says whether the user gave a range;
    -- line1/line2 are always populated by Neovim (defaulting to the cursor
    -- line), so reading them instead would record a phantom one-line span.
    local src = source.resolve(bufnr, { range = 0, line1 = 2, line2 = 2 }, "json", { reg = "r" })
    assert.is_nil(src.s0)
  end)

  it("reports an invalid register name as an ERROR", function()
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", {
      reg = "clipboard",
    })
    assert.is_nil(src)
    assert.equals("error", problem.level)
    assert.matches("single character", problem.msg)
  end)

  it("reports an empty register as an error", function()
    vim.fn.setreg("r", "", "c")
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", {
      reg = "r",
    })
    assert.is_nil(src)
    assert.equals("error", problem.level)
    assert.matches("empty", problem.msg)
  end)

  it("reports the expression register rather than evaluating it", function()
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", {
      reg = "=",
    })
    assert.is_nil(src)
    assert.matches("expression register", problem.msg)
  end)

  it("passes a clipboard-fallback note through for the caller to surface", function()
    -- `register.name`'s third return value. It is not an error and not a
    -- failure, so it can only arrive as a field on an otherwise-good source --
    -- and if this module dropped it, the substitution would be silent.
    local orig_has = vim.fn.has
    --- Test double: restored immediately below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.has = function(what)
      if what == "clipboard" then
        return 0
      end
      return orig_has(what)
    end
    vim.fn.setreg('"', '{"a":1}', "c")

    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", {
      reg = true,
    })
    vim.fn.has = orig_has

    assert.is_nil(problem)
    assert.equals('"', src.reg, "fell back to the unnamed register")
    assert.matches("no clipboard provider", src.note)
  end)

  it("treats reg = false as 'no register involved', not as a register named false", function()
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json", { reg = false })
    assert.equals("buffer", src.kind)
  end)

  it("tolerates an absent flags table entirely", function()
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    assert.equals("buffer", src.kind)
  end)
end)

describe("data.scope.source.resolve -- the fmt argument gates the fenced fallback", function()
  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reads the whole buffer when no fmt is given, fence or not", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 })
    assert.equals(3, #src.lines, "without a fmt, the fenced fallback is never even attempted")
  end)

  it("scopes to a matching fence when fmt is given (color_my_ascii present)", function()
    if not pcall(require, "color_my_ascii") then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```json", '{"a":1}', "```" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local src = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    assert.same({ '{"a":1}' }, src.lines)
    assert.equals(1, src.s0)
    assert.equals(1, src.e0)
  end)

  it("falls back to the whole buffer for an EMPTY fence", function()
    -- `resolve.lines` rejects a block whose content_end <= content_start, so
    -- an empty fence must not become a zero-line scope (which the caller
    -- would then report as "nothing to process").
    if not pcall(require, "color_my_ascii") then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x", "```json", "```", "y" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local src, problem = source.resolve(bufnr, { range = 0, line1 = 1, line2 = 1 }, "json")
    assert.is_nil(problem)
    assert.equals(4, #src.lines, "the whole buffer, not an empty fence interior")
  end)
end)
