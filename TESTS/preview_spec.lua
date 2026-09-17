-- Test code: when something here comes back nil -- a require, a buffer
-- lookup, a decision -- this file must crash and name it. The nil guards
-- LuaLS asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- Every `disable-next-line: undefined-field` below suppresses assert.* --
-- luassert's augmentation of the global `assert` table (workspace.check-
-- ThirdParty is off, so no busted/luassert stub is injected) -- not a real gap.
-- TESTS/preview_spec.lua — data.preview and :JSON filter --preview

describe("data.preview.confirm -- diff.nvim absent", function()
  it("refuses rather than writing unseen", function()
    -- Simulated absence via package.preload, not by removing the real plugin
    -- from the rtp -- this test must fail the same way whether or not
    -- diff.nvim happens to be installed on this machine.
    local had = package.loaded["diff"]
    package.loaded["diff"] = nil
    package.preload["diff"] = function()
      error("simulated: diff.nvim not on rtp")
    end

    local got_apply, got_problem
    require("data.preview").confirm({
      before = { "a" },
      after = { "b" },
      label = "json filter",
      before_label = "before",
      after_label = "after",
      prompt = "?",
    }, function(apply, problem)
      got_apply, got_problem = apply, problem
    end)

    package.preload["diff"] = nil
    package.loaded["diff"] = had

    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(got_apply, "nil means 'could not preview', which callers must not treat as yes")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(got_problem.msg:find("diff.nvim", 1, true))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(got_problem.msg:find("nothing was written", 1, true))
  end)
end)

describe("data.preview.confirm", function()
  -- Optional soft dependency, same "sibling checkout" convention the
  -- fenced-scope and filter specs use (see scripts/minimal_init.lua's
  -- DIFF_DIR). Zero `it`s registered below is the correct "skipped" outcome
  -- when diff.nvim isn't present in this test environment.
  if not pcall(require, "diff") then
    return
  end

  local orig_select, home_win

  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
    orig_select = vim.ui.select
    home_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    vim.ui.select = orig_select
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home_win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home_win) then
      vim.api.nvim_set_current_win(home_win)
    end
  end)

  it("renders the two sides as a unified diff and applies on 'Apply'", function()
    local got
    --- Test double: restored via `orig_select` in `after_each`.
    ---@diagnostic disable-next-line: duplicate-set-field
    local seen
    vim.ui.select = function(_choices, _opts, cb)
      seen = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
      cb("Apply")
    end

    require("data.preview").confirm({
      before = { "keep: 1", "drop: 2" },
      after = { "keep: 1" },
      label = "json filter",
      before_label = "before -- 2 line(s) in scope",
      after_label = "after -- 1 line(s) kept",
      prompt = "replace?",
    }, function(apply)
      got = apply
    end)

    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(got)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(vim.tbl_contains(seen, "-drop: 2"), "the removed line must be visible")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(vim.tbl_contains(seen, " keep: 1"), "the kept line must be visible as context")
  end)

  it("relabels the header so the two sides are identifiable, not buffer numbers", function()
    local seen
    --- Test double: restored via `orig_select` in `after_each`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_choices, _opts, cb)
      seen = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
      cb("Discard")
    end

    require("data.preview").confirm({
      before = { "a" },
      after = { "b" },
      label = "json filter",
      before_label = "before -- 1 line(s) in scope",
      after_label = "after -- 1 line(s) kept",
      prompt = "?",
    }, function() end)

    ---@diagnostic disable-next-line: undefined-field
    assert.equals("--- before -- 1 line(s) in scope", seen[1])
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("+++ after -- 1 line(s) kept", seen[2])
  end)

  it("reports 'Discard' and a cancelled prompt alike as a no", function()
    for _, choice in ipairs({ "Discard", vim.NIL }) do
      local got = "unset"
      --- Test double: restored via `orig_select` in `after_each`.
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.select = function(_choices, _opts, cb)
        cb(choice ~= vim.NIL and choice or nil)
      end
      require("data.preview").confirm({
        before = { "a" },
        after = { "b" },
        label = "json filter",
        before_label = "before",
        after_label = "after",
        prompt = "?",
      }, function(apply)
        got = apply
      end)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(got, "a decision that isn't 'Apply' is a no, never a nil 'could not preview'")
    end
  end)

  it("leaves no holder or preview buffers behind", function()
    local before_count = #vim.api.nvim_list_bufs()
    --- Test double: restored via `orig_select` in `after_each`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_choices, _opts, cb)
      cb("Discard")
    end

    require("data.preview").confirm({
      before = { "a", "b", "c" },
      after = { "a" },
      label = "json filter",
      before_label = "before",
      after_label = "after",
      prompt = "?",
    }, function() end)

    ---@diagnostic disable-next-line: undefined-field
    assert.equals(
      before_count,
      #vim.api.nvim_list_bufs(),
      "the two holder buffers and the diff buffer are all transient"
    )
  end)
end)

describe(":JSON filter --preview", function()
  -- Needs both optional dependencies: pickers.nvim to build the clause stack
  -- at all, diff.nvim to render the preview.
  if not (pcall(require, "pickers.refine") and pcall(require, "diff")) then
    return
  end

  local bufnr, home_win, orig_select, orig_input

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    home_win = vim.api.nvim_get_current_win()
    orig_select, orig_input = vim.ui.select, vim.ui.input
  end)

  after_each(function()
    vim.ui.select, vim.ui.input = orig_select, orig_input
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

  --- Script one `path contains <term>` refine clause, then answer the preview
  --- prompt with `verdict`. One `vim.ui.select` double serves both prompts:
  --- pickers.refine's choices are tables, the preview's are the two strings
  --- "Apply"/"Discard", so they are told apart by shape rather than by call
  --- order -- which would otherwise have to encode how many rounds refine
  --- happens to take.
  ---@param term string
  ---@param verdict string|nil
  local function script(term, verdict)
    local refine_rounds = 0
    --- Test double: restored via `orig_select` in `after_each`.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(choices, _opts, cb)
      if type(choices[1]) == "string" then
        return cb(verdict)
      end
      refine_rounds = refine_rounds + 1
      if refine_rounds > 1 then
        return cb(nil)
      end
      for _, c in ipairs(choices) do
        if c.kind == "add" and c.field == "path" and c.negate == false then
          return cb(c)
        end
      end
      cb(nil)
    end
    --- Test double: same rationale.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.input = function(_opts, cb)
      cb(term)
    end
  end

  it("applies the filter when the preview is accepted", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"user":{"id":1,"name":"x"},"level":"error"}',
    })
    script("user", "Apply")
    vim.cmd("JSON filter --preview")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "user.id: 1", "user.name: x" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("leaves the scope untouched when the preview is discarded", function()
    local src = { '{"user":{"id":1,"name":"x"},"level":"error"}' }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, src)
    script("user", "Discard")
    vim.cmd("JSON filter --preview")
    ---@diagnostic disable-next-line: undefined-field
    assert.same(src, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("--no-preview overrides a preview.filter = true config", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ preview = { filter = true } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"user":{"id":1},"level":"error"}',
    })
    -- A verdict of nil would be a "no" if the preview ran at all; the filter
    -- applying anyway is what proves it did not.
    script("user", nil)
    vim.cmd("JSON filter --no-preview")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("preview.filter = true previews without the flag", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ preview = { filter = true } })

    local src = { '{"user":{"id":1},"level":"error"}' }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, src)
    script("user", "Discard")
    vim.cmd("JSON filter")
    ---@diagnostic disable-next-line: undefined-field
    assert.same(src, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("--preview with --split is ignored with a warning, not silently", function()
    local calls = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      calls[#calls + 1] = tostring(msg)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"user":{"id":1},"level":"error"}',
    })
    script("user", nil)
    vim.cmd("JSON filter --preview --split")
    vim.wait(20)
    vim.notify = orig_notify

    local warned = false
    for _, m in ipairs(calls) do
      if m:find("in-place", 1, true) then
        warned = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(warned, "a flag that cannot apply must say so")
  end)

  it("--preview and --no-preview together are a contradiction, not a ranking", function()
    local calls = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      calls[#calls + 1] = tostring(msg)
    end

    local src = { '{"a":1}' }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, src)
    vim.cmd("JSON filter --preview --no-preview")
    vim.wait(20)
    vim.notify = orig_notify

    ---@diagnostic disable-next-line: undefined-field
    assert.same(src, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    local complained = false
    for _, m in ipairs(calls) do
      if m:find("mutually exclusive", 1, true) then
        complained = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(complained)
  end)
end)
