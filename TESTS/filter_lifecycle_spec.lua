-- Test code: when something here comes back nil -- a require, an extmark, a
-- buffer lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/filter_lifecycle_spec.lua — the extmark `data.init`'s `M.filter`
-- anchors its scope to, across every way a filter run can end.
--
-- filter_spec.lua proves the extmark TRACKS the scope (an edit above it during
-- the prompt, and the result still lands in the right place). What nothing
-- covered is its other half: that it is always cleaned up again. It lives in a
-- module-level namespace, so a leaked mark is permanent for the session --
-- invisible, but it keeps shifting with every edit and the next run's
-- bookkeeping has a stranger in it. Every exit path is walked here and the
-- namespace checked afterwards.
--
-- `data.filter` and `data.preview` are replaced with doubles, which is what
-- makes the awkward paths (a buffer closed mid-preview, two identical sides,
-- a filter that errors) reachable at all -- and makes this file independent of
-- whether pickers.nvim and diff.nvim happen to be installed. Both are safe to
-- stub through `package.loaded` because `M.filter` requires them at CALL time,
-- not as load-time upvalues.

local FILTER_NS = vim.api.nvim_create_namespace("data.nvim/filter")

--- Capture every `vim.notify` call made during `fn()`, pumping the loop so a
--- scheduled report has actually fired.
---@param fn fun()
---@return string[]
local function capture_notify(fn)
  local msgs = {}
  local orig = vim.notify
  --- Test double: restored below, including when `fn()` errors.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    msgs[#msgs + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.wait(30)
  vim.notify = orig
  if not ok then
    error(err, 0)
  end
  return msgs
end

---@param msgs string[]
---@param needle string
---@return boolean
local function said(msgs, needle)
  for _, m in ipairs(msgs) do
    if m:find(needle, 1, true) then
      return true
    end
  end
  return false
end

--- A `data.filter` double whose `run` hands `on_done(out, err)` straight back,
--- optionally doing something to the buffer first (which is what makes the
--- "closed while the prompt was open" paths reachable).
---@param out string[]|nil
---@param err string|nil
---@param during? fun()
---@return table
local function filter_double(out, err, during)
  return {
    run = function(_formatter, _value, _opts, on_done)
      if during then
        during()
      end
      on_done(out, err)
    end,
  }
end

--- A `data.preview` double that answers `confirm` with `(apply, problem)`,
--- optionally doing something to the buffer first.
---@param apply boolean|nil
---@param problem Data.Problem|nil
---@param during? fun()
---@return table
local function preview_double(apply, problem, during)
  return {
    available = function()
      return true
    end,
    confirm = function(_opts, on_decision)
      if during then
        during()
      end
      on_decision(apply, problem)
    end,
  }
end

describe("data.filter's extmark -- every exit path cleans it up", function()
  local bufnr, had_filter, had_preview

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    had_preview = package.loaded["data.preview"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1},"level":"error"}' })
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    package.loaded["data.preview"] = had_preview
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  ---@return integer
  local function marks_left()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return 0
    end
    return #vim.api.nvim_buf_get_extmarks(bufnr, FILTER_NS, 0, -1, {})
  end

  it("a committed filter leaves no mark", function()
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.equals(0, marks_left())
  end)

  it("a cancelled filter (nil, nil) leaves no mark and says nothing", function()
    package.loaded["data.filter"] = filter_double(nil, nil)
    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end)
    assert.equals(0, #msgs, "cancelling before any clause is not worth a notification")
    assert.equals(0, marks_left())
  end)

  it("a filter that matched NOTHING warns, writes nothing, and leaves no mark", function()
    package.loaded["data.filter"] = filter_double({}, nil)
    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end)
    assert.is_true(said(msgs, "no entries matched"))
    assert.same(
      { '{"user":{"id":1},"level":"error"}' },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.equals(0, marks_left())
  end)

  it("a filter that ERRORED reports it and leaves no mark", function()
    package.loaded["data.filter"] = filter_double(nil, "something went wrong inside refine")
    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end)
    assert.is_true(said(msgs, "something went wrong inside refine"))
    assert.is_true(said(msgs, "JSON filter: "), "prefixed with the action that failed")
    assert.equals(0, marks_left())
  end)

  it("a discarded preview leaves no mark", function()
    package.loaded["data.config"] = nil
    package.loaded["data"] = nil
    require("data.config").setup()
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = preview_double(false, nil)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })
    end)

    assert.is_true(said(msgs, "discarded -- scope left unchanged"))
    assert.same(
      { '{"user":{"id":1},"level":"error"}' },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.equals(0, marks_left())
  end)

  it("an applied preview leaves no mark", function()
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = preview_double(true, nil)

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })

    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.equals(0, marks_left())
  end)

  it("a preview that could not be rendered reports it and leaves no mark", function()
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = preview_double(nil, {
      msg = "diff.nvim did not render a preview -- nothing was written",
      level = "error",
    })

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })
    end)

    assert.is_true(said(msgs, "did not render a preview"))
    assert.same(
      { '{"user":{"id":1},"level":"error"}' },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "a refusal to preview is a refusal to write"
    )
    assert.equals(0, marks_left())
  end)

  it("no mark is created at all for a --split target", function()
    -- A target that writes somewhere which did not exist when the prompt
    -- opened needs no tracking, and creating one anyway would leak into the
    -- buffer the command merely ran in.
    local home = vim.api.nvim_get_current_win()
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { split = true })

    assert.equals(0, marks_left())
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home) then
      vim.api.nvim_set_current_win(home)
    end
  end)

  it("no mark is created for an --out-reg target either", function()
    vim.fn.setreg("q", "", "c")
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { out_reg = "q" })

    assert.equals("user.id: 1\n", vim.fn.getreg("q"))
    assert.equals(0, marks_left())
  end)

  it("ten runs in a row leave the namespace as empty as they found it", function()
    -- A leak of one mark per run is exactly the shape that stays invisible
    -- until a session has been open for a day.
    for i = 1, 10 do
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
      package.loaded["data.filter"] = filter_double(i % 2 == 0 and { "user.id: 1" } or nil, nil)
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end
    assert.equals(0, marks_left())
  end)
end)

describe("data.filter -- the buffer disappearing mid-run", function()
  local bufnr, had_filter, had_preview

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    had_preview = package.loaded["data.preview"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    package.loaded["data.preview"] = had_preview
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reports a buffer closed while the CLAUSE PROMPT was open", function()
    local victim = bufnr
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil, function()
      vim.api.nvim_buf_delete(victim, { force = true })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end)

    assert.is_true(said(msgs, "buffer was closed before the filter finished"))
    assert.is_true(said(msgs, "discarding the result"))
  end)

  it("reports a buffer closed while the PREVIEW was open -- a separate arm", function()
    -- Two arbitrarily long gaps, two checks. This is the second one, which
    -- nothing reached before: the first check passed, the preview opened, and
    -- the buffer went away while the user was deciding.
    local victim = bufnr
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = preview_double(true, nil, function()
      vim.api.nvim_buf_delete(victim, { force = true })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })
    end)

    assert.is_true(said(msgs, "buffer was closed during the preview"))
    assert.is_true(said(msgs, "discarding the result"))
  end)

  it("raises nothing in either case", function()
    for _, which in ipairs({ "prompt", "preview" }) do
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(b)
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { '{"user":{"id":1}}' })
      package.loaded["data"] = nil
      local kill = function()
        vim.api.nvim_buf_delete(b, { force = true })
      end
      package.loaded["data.filter"] =
        filter_double({ "user.id: 1" }, nil, which == "prompt" and kill or nil)
      package.loaded["data.preview"] = preview_double(true, nil, which == "preview" and kill or nil)

      local ok = pcall(function()
        capture_notify(function()
          require("data").filter(
            "json",
            { range = 0, line1 = 1, line2 = 1 },
            {},
            { preview = which == "preview" }
          )
        end)
      end)

      assert.is_true(ok, ("closing the buffer during the %s must not raise"):format(which))
    end
  end)
end)

describe("data.filter -- when the preview would show nothing", function()
  local bufnr, had_filter, had_preview

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    had_preview = package.loaded["data.preview"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    package.loaded["data.preview"] = had_preview
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("skips the preview entirely when both sides are identical", function()
    -- diff.nvim would report "No differences found" and open no window,
    -- leaving a prompt with no preview behind it -- so the write happens
    -- directly instead.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user.id: 1" })
    local confirmed = false
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = {
      available = function()
        return true
      end,
      confirm = function(_opts, on_decision)
        confirmed = true
        on_decision(false, nil)
      end,
    }

    -- A yaml scope whose `lines` rendering equals the scope itself.
    require("data").filter("yaml", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })

    assert.is_false(confirmed, "nothing to show, nothing to decide")
    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it(
    "warns that --preview cannot apply to a --split target, rather than ignoring it quietly",
    function()
      local home = vim.api.nvim_get_current_win()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
      local confirmed = false
      package.loaded["data"] = nil
      package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
      package.loaded["data.preview"] = {
        available = function()
          return true
        end,
        confirm = function(_opts, on_decision)
          confirmed = true
          on_decision(true, nil)
        end,
      }

      local msgs = capture_notify(function()
        require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, {
          preview = true,
          split = true,
        })
      end)

      assert.is_true(said(msgs, "only applies to an in-place result"))
      assert.is_false(confirmed, "the before side is still on screen anyway")
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= home and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      if vim.api.nvim_win_is_valid(home) then
        vim.api.nvim_set_current_win(home)
      end
    end
  )

  it("refuses --preview together with --no-preview instead of ranking them", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    local ran = false
    package.loaded["data"] = nil
    package.loaded["data.filter"] = {
      run = function()
        ran = true
      end,
    }

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, {
        preview = true,
        no_preview = true,
      })
    end)

    assert.is_true(said(msgs, "mutually exclusive"))
    assert.is_false(ran, "the contradiction is caught before any work is done")
  end)

  it("honors preview.filter = true with no flag given", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    local confirmed = false
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ preview = { filter = true } })
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = {
      available = function()
        return true
      end,
      confirm = function(_opts, on_decision)
        confirmed = true
        on_decision(false, nil)
      end,
    }

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })

    assert.is_true(confirmed, "the configured default previews without the flag")
  end)

  it("lets --no-preview override preview.filter = true", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    local confirmed = false
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ preview = { filter = true } })
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = {
      available = function()
        return true
      end,
      confirm = function(_opts, on_decision)
        confirmed = true
        on_decision(false, nil)
      end,
    }

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { no_preview = true })

    assert.is_false(confirmed)
    assert.same({ "user.id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)

describe("data.filter -- the span the result is written to", function()
  local bufnr, had_filter, had_preview

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    had_preview = package.loaded["data.preview"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    package.loaded["data.preview"] = had_preview
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("follows the scope when lines are inserted ABOVE it during the prompt", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "head", '{"user":{"id":1}}', "tail" })
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "INSERTED" })
    end)

    require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })

    assert.same(
      { "INSERTED", "head", "user.id: 1", "tail" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("follows it across a SECOND shift during the preview", function()
    -- The span is re-read from the mark on both sides of the preview, not
    -- just once before it opened.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "head", '{"user":{"id":1}}', "tail" })
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "FIRST" })
    end)
    package.loaded["data.preview"] = preview_double(true, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "SECOND" })
    end)

    require("data").filter("json", { range = 2, line1 = 2, line2 = 2 }, {}, { preview = true })

    assert.same(
      { "SECOND", "FIRST", "head", "user.id: 1", "tail" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "both shifts are accounted for"
    )
  end)

  it("shows the preview the scope's CURRENT content after a character-level edit", function()
    -- A `nvim_buf_set_text` edit inside the scope keeps the extmark intact, so
    -- the re-read picks up the new content. (The line-wise case does NOT --
    -- see the BUG block at the end of this file.)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    local seen_before
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil, function()
      vim.api.nvim_buf_set_text(bufnr, 0, 14, 0, 15, { "9" })
    end)
    package.loaded["data.preview"] = {
      available = function()
        return true
      end,
      confirm = function(opts, on_decision)
        seen_before = opts.before
        on_decision(false, nil)
      end,
    }

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })

    assert.same({ '{"user":{"id":9}}' }, seen_before, "the edited content, re-read from the mark")
  end)

  it("labels the preview with the format and action", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    local seen
    package.loaded["data"] = nil
    package.loaded["data.filter"] = filter_double({ "user.id: 1" }, nil)
    package.loaded["data.preview"] = {
      available = function()
        return true
      end,
      confirm = function(opts, on_decision)
        seen = opts
        on_decision(false, nil)
      end,
    }

    require("data").filter("json", { range = 0, line1 = 1, line2 = 1 }, {}, { preview = true })

    assert.equals("json filter", seen.label)
    assert.matches("JSON filter: replace 1 line%(s%) with 1%?", seen.prompt)
  end)
end)

describe("BUG: replacing the scope LINE-WISE mid-prompt inverts the extmark", function()
  -- The extmark exists to survive exactly this: an arbitrary edit during the
  -- unbounded gap while the clause prompt is open. `data.init`'s own doc
  -- comment promises it tracks the scope "shrinking/growing with edits inside
  -- it the same way any other extmark does". For one common kind of edit it
  -- does not.
  --
  -- The mark is created as `(s0, 0)` to `(e0 + 1, 0)`. When
  -- `nvim_buf_set_lines` replaces EXACTLY that span, Neovim moves the start
  -- past the replacement while collapsing the end, leaving start > end:
  -- measured as `s0 = 1, end_row = 0` for a one-line scope, so `M.filter`
  -- computes `e0 = end_row - 1 = -1` and asks for the span `[1, 0)`.
  -- `nvim_buf_set_lines` rejects that, and the pcall in
  -- `data.scope.sink.write_inplace` turns it into
  --
  --   JSON filter: could not write the result: 'start' is higher than 'end'
  --
  -- The filter result is DISCARDED, and the message names an API constraint
  -- rather than anything the user did or can do -- which is the very outcome
  -- that pcall's own comment says it was added to avoid.
  --
  -- The trigger is not exotic: a line-wise `set_lines` over the scope is what
  -- a format-on-save, an applied LSP text edit, or any other plugin rewriting
  -- the buffer does. A CHARACTER-level edit (`set_text`, and `:s///`, which
  -- uses one) leaves the mark intact -- the controls below pin that half, so a
  -- fix has both sides to aim at.

  local bufnr, had_filter

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("BUG: the mark's start ends up past its end", function()
    local ns = vim.api.nvim_create_namespace("data.nvim/filter")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 0, { end_row = 2, end_col = 0 })

    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { '{"a":999}' })

    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true })
    local s0 = mark[1]
    local e0 = mark[3].end_row - 1
    assert.is_true(s0 > e0, ("BUG: start %d is past end %d"):format(s0, e0))
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end)

  it("BUG: so the result is lost, with an API-level message", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { '{"a":999}' })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })
    end)

    assert.same(
      { "H", '{"a":999}', "T" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "BUG: the filter result never arrived"
    )
    assert.is_true(
      said(msgs, "'start' is higher than 'end'"),
      "BUG: an nvim_buf_set_lines constraint, reported to a user who filtered some JSON"
    )
  end)

  it("BUG: the same for a whole-buffer scope of one line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { '{"a":999}' })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 0, line1 = 1, line2 = 1 })
    end)

    assert.same({ '{"a":999}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.is_true(said(msgs, "'start' is higher than 'end'"))
  end)

  it("control: a character-level edit of the scope works", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_text(bufnr, 1, 5, 1, 6, { "9" })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })
    end)

    assert.same({ "H", "FILTERED", "T" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.equals(0, #msgs)
  end)

  it("control: replacing only PART of a multi-line scope works", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", "{", '"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "{" })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 3 })
    end)

    assert.is_false(said(msgs, "'start' is higher than 'end'"), "the mark survives a partial one")
  end)

  it("control: DELETING the scope outright works", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })
    end)

    assert.is_false(said(msgs, "'start' is higher than 'end'"))
    assert.same({ "H", "FILTERED", "T" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("control: an inserted line ABOVE the scope works", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "NEW" })
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })
    end)

    assert.same({ "NEW", "H", "FILTERED", "T" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.equals(0, #msgs)
  end)

  it("control: `:s///` on the scope line leaves the mark usable", function()
    -- Worth spelling out, because it is the edit a USER is most likely to make
    -- while a prompt is open, and it is on the safe side of the divide.
    local ns = vim.api.nvim_create_namespace("data.nvim/filter")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 0, { end_row = 2, end_col = 0 })

    vim.cmd("2s/1/9/")

    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, { details = true })
    assert.equals(1, mark[1])
    assert.equals(2, mark[3].end_row, "start and end both intact")
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end)
end)

describe("data.filter -- the tracking mark disappearing mid-run (ERR-02)", function()
  -- `nvim_buf_get_extmark_by_id` returns an empty list, not an error, when
  -- the id no longer resolves -- e.g. a foreign `nvim_buf_clear_namespace`
  -- call wiping it out while the buffer itself stays perfectly valid. Before
  -- the fix, the resulting nil `source.s0` reached `nvim_buf_get_lines`/
  -- `nvim_buf_set_lines` unchecked and raised a raw API error instead of the
  -- clean notification every other exit path in this function produces.

  local bufnr, had_filter

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    had_filter = package.loaded["data.filter"]
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    package.loaded["data.filter"] = had_filter
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reports cleanly instead of raising when the mark vanishes before the write", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil, function()
      vim.api.nvim_buf_clear_namespace(bufnr, FILTER_NS, 0, -1)
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 })
    end)

    assert.same(
      { "H", '{"a":1}', "T" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "the scope is left untouched, not clobbered from a stale s0/e0"
    )
    assert.is_true(said(msgs, "tracking mark is gone"))
  end)

  it("reports cleanly instead of raising when the mark vanishes during the preview", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "H", '{"a":1}', "T" })
    package.loaded["data.filter"] = filter_double({ "FILTERED" }, nil)
    package.loaded["data.preview"] = preview_double(true, nil, function()
      vim.api.nvim_buf_clear_namespace(bufnr, FILTER_NS, 0, -1)
    end)

    local msgs = capture_notify(function()
      require("data").filter("json", { range = 2, line1 = 2, line2 = 2 }, {}, { preview = true })
    end)

    assert.same(
      { "H", '{"a":1}', "T" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "the scope is left untouched, not clobbered from a stale s0/e0"
    )
    assert.is_true(said(msgs, "tracking mark is gone"))
  end)
end)
