-- Test code: when something here comes back nil -- a require, a decode, a
-- buffer lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- Every `disable-next-line: undefined-field` below suppresses assert.* --
-- luassert's augmentation of the global `assert` table (workspace.check-
-- ThirdParty is off, so no busted/luassert stub is injected) -- not a real gap.
-- TESTS/usrcmds_io_spec.lua — the --reg / --inplace / --split / --out-reg
-- source and target flags, end to end through the real user commands.

--- Capture every `vim.notify` call made during `fn()`, pumping the event
--- loop briefly afterwards so a `vim.schedule`-deferred notify (every
--- `data.init` warning/error is scheduled -- see its own doc comment for
--- why) has actually run before this returns.
---@param fn fun()
---@return {msg: string, level: integer}[]
local function capture_notify(fn)
  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level)
    calls[#calls + 1] = { msg = msg, level = level }
  end

  local ok, err = pcall(fn)
  vim.wait(20)
  vim.notify = orig

  if not ok then
    error(err, 0)
  end
  return calls
end

--- Whether any captured notification contains `needle`.
---@param calls {msg: string, level: integer}[]
---@param needle string
---@return boolean
local function notified(calls, needle)
  for _, c in ipairs(calls) do
    if type(c.msg) == "string" and c.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe(":JSON --reg / --split / --out-reg", function()
  local bufnr, home_win

  before_each(function()
    -- Same fresh-module dance as usrcmds_spec.lua: the composer registers
    -- each verb once, so a stale `data.bindings.usrcmds` would redefine it.
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    home_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    -- A --split test leaves its own window focused; close everything that
    -- isn't the window this spec started in before deleting the buffer.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home_win) then
      vim.api.nvim_set_current_win(home_win)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("--reg reads the register and opens a split, leaving the buffer untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "do not touch me" })
    vim.fn.setreg("r", '{"b":2,"a":1}', "c")

    vim.cmd("JSON pretty --reg=r")

    ---@diagnostic disable-next-line: undefined-field
    assert.same(
      { "do not touch me" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "a register source must never write into the buffer it was invoked from"
    )

    local result = vim.api.nvim_get_current_buf()
    ---@diagnostic disable-next-line: undefined-field
    assert.are_not.equals(bufnr, result)
    ---@diagnostic disable-next-line: undefined-field
    assert.same(
      { "{", '  "a": 1,', '  "b": 2', "}" },
      vim.api.nvim_buf_get_lines(result, 0, -1, false)
    )
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("json", vim.bo[result].filetype)
  end)

  it("--split sends a buffer-scope result to a split instead of overwriting", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    vim.cmd("JSON pretty --split")

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    local result = vim.api.nvim_get_current_buf()
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}" }, vim.api.nvim_buf_get_lines(result, 0, -1, false))
  end)

  it("--out-reg writes the result into a register and reports it", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.fn.setreg("q", "", "c")

    local calls = capture_notify(function()
      vim.cmd("JSON pretty --out-reg=q")
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals('{\n  "a": 1\n}\n', vim.fn.getreg("q"))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(
      notified(calls, "register 'q'"),
      "a register write is invisible unless it says so"
    )
  end)

  it("--reg --inplace replaces an explicit range with the formatted register", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "before", "REPLACE ME", "after" })
    vim.fn.setreg("r", '{"a":1}', "c")

    vim.cmd("2,2JSON compact --reg=r --inplace")

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "before", '{"a":1}', "after" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("--reg --inplace without a range refuses instead of overwriting the buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "me" })
    vim.fn.setreg("r", '{"a":1}', "c")

    local calls = capture_notify(function()
      vim.cmd("JSON pretty --reg=r --inplace")
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "keep", "me" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(notified(calls, "explicit range"))
  end)

  it("two target flags at once are refused, not silently ranked", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    local calls = capture_notify(function()
      vim.cmd("JSON pretty --split --inplace")
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(notified(calls, "mutually exclusive"))
  end)

  it("an empty register is reported and nothing is written", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "untouched" })
    vim.fn.setreg("r", "", "c")

    local calls = capture_notify(function()
      vim.cmd("JSON pretty --reg=r")
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "untouched" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(notified(calls, "is empty"))
  end)

  it("a read-only buffer is still a valid --split source", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.bo[bufnr].modifiable = false

    vim.cmd("JSON pretty --split")
    local result = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].modifiable = true

    ---@diagnostic disable-next-line: undefined-field
    assert.same(
      { "{", '  "a": 1', "}" },
      vim.api.nvim_buf_get_lines(result, 0, -1, false),
      "'modifiable' only ever governed the in-place write, not reading the scope"
    )
  end)

  it("a lines result split does not claim the source format's filetype", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })

    vim.cmd("JSON lines --split")
    local result = vim.api.nvim_get_current_buf()

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(result, 0, -1, false))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("", vim.bo[result].filetype, "flattened path/value text is not JSON")
  end)

  it(":JSON to yaml --split labels the result as YAML, not JSON", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    vim.cmd("JSON to yaml --split")
    local result = vim.api.nvim_get_current_buf()

    ---@diagnostic disable-next-line: undefined-field
    assert.equals("yaml", vim.bo[result].filetype)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: 1" }, vim.api.nvim_buf_get_lines(result, 0, -1, false))
  end)
end)

describe(":Data --reg", function()
  local bufnr, home_win

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
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
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("detects the format from the register, not the buffer's filetype", function()
    -- The buffer says XML; the register holds JSON. The register wins,
    -- because the buffer's filetype says nothing about text that never came
    -- from it.
    vim.bo[bufnr].filetype = "xml"
    vim.fn.setreg("r", '{"a":1}', "c")

    vim.cmd("Data pretty --reg=r")
    local result = vim.api.nvim_get_current_buf()

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}" }, vim.api.nvim_buf_get_lines(result, 0, -1, false))
  end)

  it("reports a register it cannot classify instead of guessing", function()
    vim.fn.setreg("r", "just some prose", "c")

    local calls = capture_notify(function()
      vim.cmd("Data pretty --reg=r")
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(notified(calls, "could not determine a format from register"))
  end)
end)

describe("data.detect.from_text", function()
  local detect = require("data.detect")

  it("classifies by the first non-blank character", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("json", detect.from_text('  \n {"a":1}'))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("json", detect.from_text("[1,2]"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("xml", detect.from_text("<root/>"))
  end)

  it("classifies YAML by its document marker, sequence dash or mapping line", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("yaml", detect.from_text("---\na: 1"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("yaml", detect.from_text("- one\n- two"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("yaml", detect.from_text("user: ana"))
  end)

  it("stays linear on a long blank first line", function()
    -- Regression: the first non-blank line used to be found with
    -- `[^\r\n]*%S[^\r\n]*`. That pattern cannot cross a newline, so on a
    -- whitespace-only first line it scanned the whole run, backtracked for a
    -- `%S` that was not there, and restarted one byte along -- O(n^2), 876 ms
    -- at 16k spaces and a frozen editor well before a register gets large.
    -- The bound below is ~1000x the linear cost and ~1/600th of the old
    -- quadratic one, so it separates the two without being timing-sensitive.
    local text = string.rep(" ", 200000) .. "\n" .. '{"a":1}'
    local started = vim.loop.hrtime()
    local fmt = detect.from_text(text)
    local elapsed_ms = (vim.loop.hrtime() - started) / 1e6

    ---@diagnostic disable-next-line: undefined-field
    assert.equals("json", fmt)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(
      elapsed_ms < 200,
      ("took %.1f ms -- the quadratic scan is back"):format(elapsed_ms)
    )
  end)

  it("returns nil rather than guessing at prose or an empty string", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(detect.from_text("just some prose"))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(detect.from_text("   \n  "))
  end)
end)
