-- Test code: when something here comes back nil -- a require, a decision --
-- this file must crash and name it. The nil guards LuaLS asks for below would
-- hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/preview_failure_spec.lua — data.preview's refusal arms and its view
-- resolution, driven against a diff.nvim DOUBLE.
--
-- preview_spec.lua drives the REAL diff.nvim and therefore skips wholesale
-- when it is absent; what it cannot reach is the case where diff.nvim is
-- present but renders nothing. That case is the module's whole safety story:
-- `on_decision(nil, problem)` means "could not preview", which a caller must
-- treat as DO NOT WRITE and never as consent -- because the point of the flag
-- is to not overwrite anything unseen. Zero new windows is how the module
-- detects it, so a double that opens no window is the only way to test it.
--
-- Safe to stub via `package.loaded`: `data.preview.confirm` requires diff
-- inside the function (`local ok, diff = pcall(require, "diff")`), not at load
-- time.

--- Run `confirm` with `diff` standing in for diff.nvim, returning the decision
--- pair and how often it arrived. Restores the real module afterwards.
---@param diff table
---@param answer? string|nil # what vim.ui.select picks, when it is reached
---@return boolean raised_nothing
---@return boolean|nil apply
---@return Data.Problem|nil problem
---@return integer decisions
local function with_diff(diff, answer)
  local had_diff = package.loaded["diff"]
  local orig_select = vim.ui.select
  package.loaded["diff"] = diff
  --- Test double: restored below.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(_choices, _opts, cb)
    cb(answer)
  end

  local apply, problem, decisions = nil, nil, 0
  local ok = pcall(require("data.preview").confirm, {
    before = { "keep: 1", "drop: 2" },
    after = { "keep: 1" },
    label = "json filter",
    prompt = "replace?",
  }, function(a, p)
    apply, problem, decisions = a, p, decisions + 1
  end)

  vim.ui.select = orig_select
  package.loaded["diff"] = had_diff
  return ok, apply, problem, decisions
end

describe("data.preview.available", function()
  it("answers by whether diff.nvim can be required, nothing more", function()
    local had = package.loaded["diff"]
    package.loaded["diff"] = { run = function() end }
    assert.is_true(require("data.preview").available())
    package.loaded["diff"] = had
  end)

  it("is false when diff.nvim cannot be loaded", function()
    local had = package.loaded["diff"]
    package.loaded["diff"] = nil
    package.preload["diff"] = function()
      error("simulated: diff.nvim not installed")
    end

    local got = require("data.preview").available()

    package.preload["diff"] = nil
    package.loaded["diff"] = had
    assert.is_false(got)
  end)

  it("returns a plain boolean, not pcall's extra values", function()
    -- `return (pcall(require, "diff"))` is parenthesized on purpose: without
    -- it, the module's own return would leak the required module as a second
    -- value, and a caller writing `local ok, err = available()` would read the
    -- module as an error.
    local had = package.loaded["diff"]
    package.loaded["diff"] = { run = function() end }
    local a, b = require("data.preview").available()
    package.loaded["diff"] = had
    assert.equals("boolean", type(a))
    assert.is_nil(b, "exactly one return value")
  end)
end)

describe("data.preview.confirm -- refusals, which are never a yes", function()
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

  it("refuses when diff.nvim renders NO window", function()
    -- The arm preview_spec.lua cannot reach with the real plugin: diff.nvim
    -- present, and no preview on screen (an internal error, or two sides it
    -- decided were identical). Counting new windows is how the module knows.
    local ok, apply, problem, decisions = with_diff({ run = function() end })
    assert.is_true(ok)
    assert.is_nil(apply, "nil is 'could not preview', which is not consent")
    assert.matches("did not render a preview", problem.msg)
    assert.matches("nothing was written", problem.msg)
    assert.equals("error", problem.level)
    assert.equals(1, decisions)
  end)

  it("refuses when diff.run throws, with the same message", function()
    local ok, apply, problem = with_diff({
      run = function()
        error("simulated: diff.run blew up")
      end,
    })
    assert.is_true(ok, "a third-party failure must not raise past our async callback")
    assert.is_nil(apply)
    assert.matches("did not render a preview", problem.msg)
  end)

  it("refuses when diff.nvim has no `run` at all", function()
    local ok, apply, problem = with_diff({})
    assert.is_true(ok)
    assert.is_nil(apply)
    assert.matches("did not render a preview", problem.msg)
  end)

  it("never reaches the prompt when it cannot render", function()
    -- Asking "apply?" with nothing on screen to look at would be the worst
    -- outcome of all: a decision the user cannot make, taken anyway.
    local had_diff = package.loaded["diff"]
    local orig_select = vim.ui.select
    local prompted = false
    package.loaded["diff"] = { run = function() end }
    --- Test double: restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_c, _o, cb)
      prompted = true
      cb("Apply")
    end

    require("data.preview").confirm({
      before = { "a" },
      after = { "b" },
      label = "json filter",
      prompt = "?",
    }, function() end)

    vim.ui.select = orig_select
    package.loaded["diff"] = had_diff
    assert.is_false(prompted, "no window means no question")
  end)

  it("cleans up its holder buffers even when the render failed", function()
    local before = #vim.api.nvim_list_bufs()
    with_diff({
      run = function()
        error("simulated failure")
      end,
    })
    assert.equals(before, #vim.api.nvim_list_bufs(), "both holders are gone either way")
  end)
end)

describe("data.preview.confirm -- the buffer specifier handed to diff.nvim", function()
  local home_win

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
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

  --- The `diff.run` argument produced for a configured `preview.view`.
  ---@param configured? string
  ---@return string
  local function spec_for(configured)
    if configured then
      package.loaded["data.config"] = nil
      require("data.config").setup({ preview = { view = configured } })
    end
    local seen
    with_diff({
      run = function(spec)
        seen = spec
        vim.cmd("new")
      end,
    }, "Discard")
    return seen
  end

  it("passes both sides as explicit buffer ids, never `current`", function()
    -- Load-bearing for the teardown: explicit specifiers make diff.nvim
    -- materialize both sides into windows of its own and leave the origin
    -- window out of the diff, which is why closing only NEW windows is
    -- correct. `source=current` would break that.
    local spec = spec_for()
    assert.matches("source=%d+", spec)
    assert.matches("target=%d+", spec)
    assert.is_nil(spec:find("current", 1, true), "never the current buffer")
  end)

  it("asks for buffer output rather than letting diff.nvim choose", function()
    assert.matches("output=buffer", spec_for())
  end)

  it("names the source and target as two DIFFERENT buffers", function()
    local spec = spec_for()
    local source = tonumber(spec:match("source=(%d+)"))
    local target = tonumber(spec:match("target=(%d+)"))
    assert.is_not_nil(source)
    assert.is_not_nil(target)
    assert.are_not.equals(source, target)
  end)

  for _, view in ipairs({ "inline", "float", "vsplit", "split", "tab" }) do
    it(("passes the configured view '%s' through"):format(view), function()
      assert.matches("view=" .. view, spec_for(view))
    end)
  end

  it("falls back to inline for a view diff.nvim does not have", function()
    -- The config validator checks types, not enums, so a typo reaches here;
    -- inline is the safe default because it is the one view every diff.nvim
    -- version renders correctly (see the module's own doc comment).
    assert.matches("view=inline", spec_for("rihgt"))
  end)

  it("falls back to inline for a non-string view", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ preview = { view = 5 } })
    local seen
    with_diff({
      run = function(spec)
        seen = spec
        vim.cmd("new")
      end,
    }, "Discard")
    assert.matches("view=inline", seen)
  end)
end)

describe("data.preview.confirm -- the holder buffer names the diff header shows", function()
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

  --- The two holder buffer names, read from inside `diff.run` -- the only
  --- moment they still exist, since `confirm` deletes them immediately after.
  ---@param before string[]
  ---@param after string[]
  ---@return string source_name
  ---@return string target_name
  local function holder_names(before, after)
    local names = {}
    local had_diff = package.loaded["diff"]
    local orig_select = vim.ui.select
    package.loaded["diff"] = {
      run = function(spec)
        names.source = vim.api.nvim_buf_get_name(tonumber(spec:match("source=(%d+)")))
        names.target = vim.api.nvim_buf_get_name(tonumber(spec:match("target=(%d+)")))
        vim.cmd("new")
      end,
    }
    --- Test double: restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_c, _o, cb)
      cb("Discard")
    end

    require("data.preview").confirm({
      before = before,
      after = after,
      label = "json filter",
      prompt = "?",
    }, function() end)

    vim.ui.select = orig_select
    package.loaded["diff"] = had_diff
    return names.source, names.target
  end

  it("carries the label, the side, and the line count", function()
    -- The name is not hygiene: diff.nvim labels a buffer specifier by its
    -- buffer name, and that label lands on the ---/+++ lines right above a
    -- prompt asking whether to destroy one of the two sides.
    local source, target = holder_names({ "a", "b", "c" }, { "a" })
    assert.matches("data://json filter %(before, 3 lines%)$", source)
    assert.matches("data://json filter %(after, 1 line%)$", target)
  end)

  it("says 'line' not 'lines' at exactly one", function()
    local source, target = holder_names({ "only" }, { "only", "plus" })
    assert.matches("1 line%)$", source)
    assert.matches("2 lines%)$", target)
  end)

  it("says '0 lines' for an empty side", function()
    local _, target = holder_names({ "a" }, {})
    assert.matches("0 lines%)$", target)
  end)

  it("holds exactly the lines it was given", function()
    local seen
    local had_diff = package.loaded["diff"]
    local orig_select = vim.ui.select
    package.loaded["diff"] = {
      run = function(spec)
        local b = tonumber(spec:match("source=(%d+)"))
        seen = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        vim.cmd("new")
      end,
    }
    --- Test double: restored below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_c, _o, cb)
      cb("Discard")
    end

    require("data.preview").confirm({
      before = { "one", "two", "three" },
      after = { "one" },
      label = "json filter",
      prompt = "?",
    }, function() end)

    vim.ui.select = orig_select
    package.loaded["diff"] = had_diff
    assert.same({ "one", "two", "three" }, seen)
  end)
end)

describe("data.preview.confirm -- the decision it reports", function()
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

  local rendering_diff = {
    run = function()
      vim.cmd("new")
    end,
  }

  it("reports true only for exactly 'Apply'", function()
    local _, apply, problem = with_diff(rendering_diff, "Apply")
    assert.is_true(apply)
    assert.is_nil(problem)
  end)

  it("reports false for 'Discard'", function()
    local _, apply, problem = with_diff(rendering_diff, "Discard")
    assert.is_false(apply, "a no, not a 'could not preview'")
    assert.is_nil(problem)
  end)

  it("reports false for a cancelled prompt", function()
    local _, apply, problem = with_diff(rendering_diff, nil)
    assert.is_false(apply)
    assert.is_nil(problem)
  end)

  it("reports false for any other answer, rather than guessing", function()
    local _, apply = with_diff(rendering_diff, "Maybe")
    assert.is_false(apply)
  end)

  it("closes the window it opened before reporting either way", function()
    for _, answer in ipairs({ "Apply", "Discard" }) do
      local before = #vim.api.nvim_list_wins()
      with_diff(rendering_diff, answer)
      assert.equals(before, #vim.api.nvim_list_wins(), ("no window left after %s"):format(answer))
    end
  end)

  it("reports exactly once, never twice", function()
    local _, _, _, decisions = with_diff(rendering_diff, "Apply")
    assert.equals(1, decisions)
  end)
end)
