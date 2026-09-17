-- Test code: when something here comes back nil -- a require, a sink
-- resolution -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- Every `disable-next-line: undefined-field` below suppresses assert.* --
-- luassert's augmentation of the global `assert` table (workspace.check-
-- ThirdParty is off, so no busted/luassert stub is injected) -- not a real gap.
-- TESTS/scope_sink_spec.lua — data.scope.sink target resolution

local sink = require("data.scope.sink")

--- A minimal buffer source, as data.scope.source would return one.
---@return Data.Source
local function buffer_source()
  return { kind = "buffer", lines = { "{}" }, bufnr = 1, s0 = 0, e0 = 0 }
end

--- A register source. `ranged` mirrors an invocation that also carried an
--- explicit range, which is the only case `--inplace` accepts here.
---@param ranged boolean
---@return Data.Source
local function register_source(ranged)
  return {
    kind = "register",
    lines = { "{}" },
    bufnr = 1,
    reg = "+",
    s0 = ranged and 0 or nil,
    e0 = ranged and 0 or nil,
  }
end

describe("data.scope.sink.resolve -- defaults", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("defaults a buffer source to in-place", function()
    local s = sink.resolve(buffer_source(), {})
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("inplace", s.kind)
  end)

  it("defaults a register source to a split", function()
    local s = sink.resolve(register_source(false), {})
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("split", s.kind, "reading a register means not touching the buffer")
  end)

  it("--split overrides the buffer default", function()
    local s = sink.resolve(buffer_source(), { split = true })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("split", s.kind)
  end)

  it("--out-reg resolves to the named register", function()
    local s = sink.resolve(buffer_source(), { out_reg = "q" })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("register", s.kind)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("q", s.reg)
  end)

  it("a bare --out-reg falls back to the configured default register", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "z" } })
    local s = sink.resolve(buffer_source(), { out_reg = true })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("z", s.reg)
  end)
end)

describe("data.scope.sink.resolve -- refusals", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("rejects two targets at once", function()
    local s, problem = sink.resolve(buffer_source(), { split = true, inplace = true })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(s)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(problem.msg:find("mutually exclusive", 1, true))
  end)

  it("rejects --inplace on a register source with no range", function()
    local s, problem = sink.resolve(register_source(false), { inplace = true })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(
      s,
      "replacing a whole file with register contents is never an accident worth allowing"
    )
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(problem.msg:find("explicit range", 1, true))
  end)

  it("allows --inplace on a register source that carried a range", function()
    local s = sink.resolve(register_source(true), { inplace = true })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("inplace", s.kind)
  end)

  it("rejects a read-only --out-reg register", function()
    local s, problem = sink.resolve(buffer_source(), { out_reg = "%" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(s)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(problem.msg:find("read-only", 1, true))
  end)
end)

describe("data.scope.sink.write", function()
  local bufnr

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "old" })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("replaces the source span in place", function()
    local source = { kind = "buffer", lines = { "old" }, bufnr = bufnr, s0 = 0, e0 = 0 }
    local ok = sink.write({ kind = "inplace" }, source, { "new" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(ok)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "new" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("refuses an in-place write into a non-modifiable buffer", function()
    vim.bo[bufnr].modifiable = false
    local source = { kind = "buffer", lines = { "old" }, bufnr = bufnr, s0 = 0, e0 = 0 }
    local ok, problem = sink.write({ kind = "inplace" }, source, { "new" })
    vim.bo[bufnr].modifiable = true
    ---@diagnostic disable-next-line: undefined-field
    assert.is_false(ok)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(problem.msg:find("modifiable", 1, true))
  end)

  it("writes to a register and says how much it wrote", function()
    vim.fn.setreg("q", "", "c")
    local source = { kind = "buffer", lines = { "old" }, bufnr = bufnr, s0 = 0, e0 = 0 }
    local ok, _, note = sink.write({ kind = "register", reg = "q" }, source, { "a", "b" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(ok)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("a\nb\n", vim.fn.getreg("q"))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(note:find("register 'q'", 1, true))
  end)

  it("opens a scratch split and leaves the source buffer alone", function()
    local source = { kind = "register", lines = { "{}" }, bufnr = bufnr, reg = "+" }
    local before = vim.api.nvim_get_current_win()
    local ok = sink.write({ kind = "split" }, source, { "a", "b" }, { filetype = "json" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(ok)

    local result_buf = vim.api.nvim_get_current_buf()
    ---@diagnostic disable-next-line: undefined-field
    assert.are_not.equals(bufnr, result_buf, "the result must not land in the source buffer")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a", "b" }, vim.api.nvim_buf_get_lines(result_buf, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("json", vim.bo[result_buf].filetype)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("nofile", vim.bo[result_buf].buftype)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "old" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
    if vim.api.nvim_win_is_valid(before) then
      vim.api.nvim_set_current_win(before)
    end
  end)
end)
