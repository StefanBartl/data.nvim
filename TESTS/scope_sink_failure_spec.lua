-- Test code: when something here comes back nil -- a require, a sink
-- resolution -- this file must crash and name it. The nil guards LuaLS asks
-- for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/scope_sink_failure_spec.lua — the arms of data.scope.sink that only
-- fire when something goes wrong, plus the two bits of bookkeeping the happy
-- path depends on.
--
-- scope_sink_spec.lua covers target resolution and the three successful
-- writes. What was left: every failure arm of `write_split` (an outdated
-- lib.nvim, a helper that throws), the `target.split` direction mapping
-- including its deliberate fallback, and the scratch-name counter -- which
-- exists precisely because `nvim_buf_set_name` fails on a name another buffer
-- already holds, so a second `--split` would otherwise collide with the first.
--
-- This plugin performs NO filesystem I/O of any kind (no readfile/writefile,
-- no mkdir, no uv.fs_*), so the "unwritable path / unmakeable parent
-- directory" failure family that dominates its siblings simply does not exist
-- here. These are its equivalents: the write targets that can refuse.

local sink = require("data.scope.sink")

--- A buffer source over `bufnr`, as data.scope.source would return one.
---@param bufnr integer
---@return Data.Source
local function buffer_source(bufnr)
  return { kind = "buffer", lines = { "old" }, bufnr = bufnr, s0 = 0, e0 = 0 }
end

describe("data.scope.sink.write -- the split target's failure arms", function()
  local home_win

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    home_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    package.loaded["lib.nvim.window"] = nil
    pcall(require, "lib.nvim.window")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home_win) then
      vim.api.nvim_set_current_win(home_win)
    end
  end)

  it("names an outdated lib.nvim rather than calling a nil field", function()
    -- The module is present but the helper is not: the realistic shape of this
    -- failure, and the one where a bare `window.open_scratch_split(...)` would
    -- raise "attempt to call a nil value" instead of saying what to update.
    package.loaded["lib.nvim.window"] = {}

    local ok, problem = sink.write({ kind = "split" }, buffer_source(0), { "x" }, {})

    assert.is_false(ok)
    assert.matches("open_scratch_split not found", problem.msg)
    assert.matches("outdated", problem.msg)
    assert.equals("error", problem.level)
  end)

  it("names an outright missing lib.nvim.window the same way", function()
    package.loaded["lib.nvim.window"] = nil
    package.preload["lib.nvim.window"] = function()
      error("simulated: lib.nvim.window is not installed")
    end

    local ok, problem = sink.write({ kind = "split" }, buffer_source(0), { "x" }, {})

    package.preload["lib.nvim.window"] = nil
    assert.is_false(ok)
    assert.matches("open_scratch_split not found", problem.msg)
  end)

  it("catches a helper that throws and quotes what it said", function()
    package.loaded["lib.nvim.window"] = {
      open_scratch_split = function()
        error("simulated: no room for a split")
      end,
    }

    local ok, problem = sink.write({ kind = "split" }, buffer_source(0), { "x" }, {})

    assert.is_false(ok)
    assert.matches("could not open result split", problem.msg)
    assert.matches("no room for a split", problem.msg, "the underlying reason survives")
  end)

  it("opens no window when the helper fails", function()
    local before = #vim.api.nvim_list_wins()
    package.loaded["lib.nvim.window"] = {
      open_scratch_split = function()
        error("simulated failure")
      end,
    }

    sink.write({ kind = "split" }, buffer_source(0), { "x" }, {})

    assert.equals(before, #vim.api.nvim_list_wins(), "a failed split leaves no half-open window")
  end)
end)

describe("data.scope.sink.write -- the register target's failure arm", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("catches a setreg that throws and names the register", function()
    local orig = vim.fn.setreg
    --- Test double: restored immediately below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.setreg = function()
      error("Vim:E123 simulated")
    end

    local ok, problem = sink.write({ kind = "register", reg = "q" }, buffer_source(0), { "x" })
    vim.fn.setreg = orig

    assert.is_false(ok)
    assert.matches("could not write register 'q'", problem.msg)
  end)

  it("refuses a read-only register at write time too, not only at resolve time", function()
    -- `resolve` already rejects these, but `write` is reachable directly (and
    -- from `data.filter`'s async callback, arbitrarily later), so it checks
    -- again rather than trusting that resolve ran.
    for _, name in ipairs({ ":", ".", "%", "#", "=" }) do
      local ok, problem = sink.write({ kind = "register", reg = name }, buffer_source(0), { "x" })
      assert.is_false(ok, ("register '%s' must be refused"):format(name))
      assert.matches("read%-only", problem.msg)
    end
  end)
end)

describe("data.scope.sink -- the target.split direction mapping", function()
  local home_win

  before_each(function()
    home_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home_win) then
      vim.api.nvim_set_current_win(home_win)
    end
  end)

  --- Record the `split` option `open_scratch_split` is actually handed for a
  --- configured `target.split` value. Stubbing the helper is the only way to
  --- see it: the resulting window geometry does not say which of `nil` and a
  --- named direction produced it.
  ---@param configured string
  ---@return any
  local function split_option_for(configured)
    package.loaded["data.config"] = nil
    require("data.config").setup({ target = { split = configured } })
    local seen
    package.loaded["lib.nvim.window"] = {
      open_scratch_split = function(_lines, opts)
        seen = opts
        return vim.api.nvim_create_buf(false, true)
      end,
    }
    sink.write({ kind = "split" }, buffer_source(0), { "x" }, { filetype = "json" })
    package.loaded["lib.nvim.window"] = nil
    pcall(require, "lib.nvim.window")
    return seen
  end

  for _, dir in ipairs({ "above", "below", "left", "right" }) do
    it(("passes '%s' straight through"):format(dir), function()
      assert.equals(dir, split_option_for(dir).split)
    end)
  end

  it("maps 'auto' to nil, which is the helper's own honor-splitbelow behavior", function()
    assert.is_nil(split_option_for("auto").split)
  end)

  it("maps an unrecognized direction to nil rather than passing a typo along", function()
    -- The config validator checks types, not enums, so a typo reaches here.
    assert.is_nil(split_option_for("rihgt").split)
  end)

  it("always asks for a modifiable result buffer", function()
    assert.is_true(split_option_for("right").modifiable, "so a line can be trimmed before yanking")
  end)

  it("threads the filetype through unchanged", function()
    assert.equals("json", split_option_for("right").filetype)
  end)
end)

describe("data.scope.sink -- scratch buffer naming", function()
  local home_win

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    home_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home_win) then
      vim.api.nvim_set_current_win(home_win)
    end
  end)

  it("gives two splits with the SAME label distinct names", function()
    -- The whole reason the monotonic counter exists: `nvim_buf_set_name`
    -- fails on a name another buffer already carries, and every `--split` run
    -- opens its own buffer on purpose.
    local names = {}
    for _ = 1, 3 do
      sink.write({ kind = "split" }, buffer_source(0), { "x" }, { label = "json pretty" })
      names[#names + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    end

    assert.equals(3, #names)
    for i, name in ipairs(names) do
      assert.matches("data://json pretty", name, ("name %d carries the label"):format(i))
    end
    assert.are_not.equals(names[1], names[2], "two identical labels must not collide")
    assert.are_not.equals(names[2], names[3])
  end)

  it("leaves the buffer unnamed when no label was given", function()
    sink.write({ kind = "split" }, buffer_source(0), { "x" }, {})
    assert.equals("", vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
  end)
end)

describe("data.scope.sink.resolve -- flag values that are not simply truthy", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("treats out_reg = false as 'no register target'", function()
    -- `flags.out_reg ~= nil and flags.out_reg ~= false` rather than a plain
    -- truthiness test, because the bare-flag form binds `true` and an absent
    -- one can arrive as either nil or false depending on the caller.
    local s = sink.resolve({ kind = "buffer", lines = {}, bufnr = 1, s0 = 0, e0 = 0 }, {
      out_reg = false,
    })
    assert.equals("inplace", s.kind, "the buffer default still applies")
  end)

  it("treats out_reg = '' as the configured default register, like a bare flag", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "z" } })
    local s = sink.resolve({ kind = "buffer", lines = {}, bufnr = 1, s0 = 0, e0 = 0 }, {
      out_reg = "",
    })
    assert.equals("register", s.kind)
    assert.equals("z", s.reg)
  end)

  it("lists all three offending flags when all three are given", function()
    local s, problem = sink.resolve({ kind = "buffer", lines = {}, bufnr = 1, s0 = 0, e0 = 0 }, {
      inplace = true,
      split = true,
      out_reg = "q",
    })
    assert.is_nil(s)
    for _, flag in ipairs({ "--inplace", "--split", "--out%-reg" }) do
      assert.matches(flag, problem.msg, "the message names every flag that was given")
    end
  end)

  it("reports a multi-character --out-reg name", function()
    local s, problem = sink.resolve({ kind = "buffer", lines = {}, bufnr = 1, s0 = 0, e0 = 0 }, {
      out_reg = "clipboard",
    })
    assert.is_nil(s)
    assert.matches("single character", problem.msg)
  end)

  it("defaults a register source WITH a range to a split, not to in-place", function()
    -- Recording the span does not mean using it: `--reg` still means "do not
    -- touch the buffer I am sitting in" unless --inplace is asked for.
    local s = sink.resolve(
      { kind = "register", lines = {}, bufnr = 1, reg = "+", s0 = 0, e0 = 0 },
      {}
    )
    assert.equals("split", s.kind)
  end)
end)
