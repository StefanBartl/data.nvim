-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/api_spec.lua — `data.run`/`convert`/`filter`/`run_auto`/`setup` called
-- DIRECTLY, as a Lua caller would, rather than through the `:JSON`/`:YAML`/
-- `:XML`/`:Data` user commands.
--
-- Everything in usrcmds_spec.lua/usrcmds_io_spec.lua reaches these functions
-- through the composer, which means the composer is also what supplies the
-- `cmd` table, coerces the indent argument, and rejects a bad flag. A plugin
-- calling `require("data").run(...)` gets none of that, so this file pins the
-- contract at the function boundary: the shape of `cmd`, what the return value
-- is (nothing -- every outcome is reported, not returned), and that no arm
-- raises past the caller.

--- Capture every `vim.notify` call made during `fn()`, pumping the event loop
--- briefly afterwards so a `vim.schedule`-deferred report has actually run.
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

--- Run `fn()` with lib.nvim's `kit.select` replaced by a double that answers
--- with the item at `idx` (nil: the picker is dismissed). Returns every
--- options table the double was opened with.
---@param idx integer|nil
---@param fn fun()
---@return table[]
local function with_select_answer(idx, fn)
  local kit = require("lib.nvim.ui.kit")
  local orig = kit.select
  local seen = {}
  kit.select = function(o)
    seen[#seen + 1] = o
    if idx then
      o.on_select(o.items[idx], idx)
    elseif o.on_cancel then
      o.on_cancel()
    end
  end
  local ok, err = pcall(fn)
  kit.select = orig
  if not ok then
    error(err, 0)
  end
  return seen
end

--- A `Lib.UserCommand.Args` table with no range, which is what a direct caller
--- has to pass. The composer builds one of these; nothing else does.
---@return Lib.UserCommand.Args
local function no_range()
  return { range = 0, line1 = 1, line2 = 1 }
end

--- The same with an explicit 1-based inclusive range.
---@param line1 integer
---@param line2 integer
---@return Lib.UserCommand.Args
local function ranged(line1, line2)
  return { range = 2, line1 = line1, line2 = line2 }
end

describe("data.run -- the direct-call contract", function()
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
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("returns nothing at all -- the result goes to the sink, not to the caller", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local returned = require("data").run("json", "pretty", no_range())
    assert.is_nil(returned, "every outcome is delivered or reported, never returned")
    assert.same({ "{", '  "a": 1', "}" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("acts on the current buffer, which it reads itself rather than being told", function()
    -- `run` takes no bufnr: it calls `nvim_get_current_buf` internally. A
    -- caller that wants a different buffer has to make it current first, and
    -- that is worth pinning because the signature does not say so.
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(other, 0, -1, false, { '{"b":2}' })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    require("data").run("json", "compact", no_range())

    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.same({ '{"b":2}' }, vim.api.nvim_buf_get_lines(other, 0, -1, false), "untouched")
    vim.api.nvim_buf_delete(other, { force = true })
  end)

  it("honors an explicit range in the cmd table", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", '{"a":1,"b":2}', "keep" })
    require("data").run("json", "compact", ranged(2, 2))
    assert.same(
      { "keep", '{"a":1,"b":2}', "keep" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("reports an unknown format instead of raising", function()
    local msgs = capture_notify(function()
      require("data").run("toml", "pretty", no_range())
    end)
    assert.is_true(said(msgs, "unknown format 'toml'"))
  end)

  it("reports an unknown render mode through the formatter's own message", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local msgs = capture_notify(function()
      require("data").run("json", "nonsense", no_range())
    end)
    assert.is_true(said(msgs, "render failed"))
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("accepts a nil opts/flags pair", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local ok = pcall(function()
      require("data").run("json", "compact", no_range(), nil, nil)
    end)
    assert.is_true(ok)
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("warns and falls back on an indent the composer would have rejected", function()
    -- The composer types `{indent:INT}`, so a string can only ever arrive
    -- here from a direct caller. `resolve_indent` is what tells "you typed
    -- something wrong" apart from "you typed nothing".
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local msgs = capture_notify(function()
      require("data").run("json", "pretty", no_range(), { indent = "wide" })
    end)
    assert.is_true(said(msgs, "invalid indent"))
    assert.same({ "{", '  "a": 1', "}" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("treats an empty-string sep as absent, not as an empty separator", function()
    -- The composer's `--sep=` parses to `""`, which is truthy in Lua; a direct
    -- caller can pass the same thing. Either way the configured default has
    -- to win.
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ json = { sep = "/" } })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })

    require("data").run("json", "lines", no_range(), { sep = "" })

    assert.same({ "user/id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("routes the target flags exactly as the command layer does", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.fn.setreg("q", "", "c")

    require("data").run("json", "compact", no_range(), {}, { out_reg = "q" })

    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "buffer untouched")
    assert.equals('{"a":1}\n', vim.fn.getreg("q"))
  end)

  it("reads a register source when told to, without a command line in sight", function()
    local home = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "do not touch" })
    vim.fn.setreg("r", '{"b":2,"a":1}', "c")

    require("data").run("json", "pretty", no_range(), {}, { reg = "r" })

    assert.same({ "do not touch" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    local result = vim.api.nvim_get_current_buf()
    assert.are_not.equals(bufnr, result)
    assert.same(
      { "{", '  "a": 1,', '  "b": 2', "}" },
      vim.api.nvim_buf_get_lines(result, 0, -1, false)
    )

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home) then
      vim.api.nvim_set_current_win(home)
    end
  end)
end)

describe("data.convert -- the direct-call contract", function()
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
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("converts json to yaml in place", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    require("data").convert("json", "yaml", no_range())
    assert.same({ "user:", "  id: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("names the UNKNOWN side when the source format is the bad one", function()
    local msgs = capture_notify(function()
      require("data").convert("toml", "json", no_range())
    end)
    assert.is_true(said(msgs, "unknown format 'toml'"))
  end)

  it("names the UNKNOWN side when the target format is the bad one", function()
    local msgs = capture_notify(function()
      require("data").convert("json", "toml", no_range())
    end)
    assert.is_true(said(msgs, "unknown format 'toml'"), "not 'json', which is perfectly known")
  end)

  it("resolves indent against the TARGET format's config, not the source's", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ json = { indent = 8 }, yaml = { indent = 4 } })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })

    require("data").convert("json", "yaml", no_range())

    assert.same(
      { "user:", "    id: 1" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "yaml.indent = 4 applies, json.indent = 8 does not"
    )
  end)

  it("reports a conversion whose target cannot represent the value", function()
    -- A YAML document that decodes to a bare scalar has no JSON rendering
    -- failure, so the reportable case is the other direction: a value the
    -- target encoder refuses.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "NaN" })
    local msgs = capture_notify(function()
      require("data").convert("json", "yaml", no_range())
    end)
    assert.is_true(said(msgs, "conversion failed"), "named as a conversion, not a render")
    assert.same({ "NaN" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("labels a --split result with the TARGET format's filetype", function()
    local home = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    require("data").convert("json", "yaml", no_range(), {}, { split = true })

    local result = vim.api.nvim_get_current_buf()
    assert.equals("yaml", vim.bo[result].filetype)

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= home and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if vim.api.nvim_win_is_valid(home) then
      vim.api.nvim_set_current_win(home)
    end
  end)
end)

describe("data.run_auto -- the direct-call contract", function()
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
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("detects the format and dispatches to run", function()
    vim.bo[bufnr].filetype = "json"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"b":2,"a":1}' })
    require("data").run_auto("pretty", no_range())
    assert.same(
      { "{", '  "a": 1,', '  "b": 2', "}" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("asks for the format when none is detected and goes on with the pick (UI-05)", function()
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"b":2,"a":1}' })
    local asked
    local msgs = capture_notify(function()
      asked = with_select_answer(1, function()
        require("data").run_auto("pretty", no_range())
      end)
    end)
    assert.equals(1, #asked)
    assert.same({ "json", "yaml", "xml" }, asked[1].items)
    assert.matches("could not determine a format", asked[1].title)
    assert.is_nil(asked[1].title:find("use :JSON", 1, true))
    assert.is_false(said(msgs, "could not determine a format"))
    assert.same(
      { "{", '  "a": 1,', '  "b": 2', "}" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("does nothing further when the format question is dismissed", function()
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "prose" })
    local asked
    local msgs = capture_notify(function()
      asked = with_select_answer(nil, function()
        require("data").run_auto("pretty", no_range())
      end)
    end)
    assert.equals(1, #asked)
    assert.same({}, msgs)
    assert.same({ "prose" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("falls back to vim.ui.select when lib.nvim's kit does not load", function()
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "b: 2", "a: 1" })
    local had_kit = package.loaded["lib.nvim.ui.kit"]
    local orig_preload = package.preload["lib.nvim.ui.kit"]
    package.loaded["lib.nvim.ui.kit"] = nil
    package.preload["lib.nvim.ui.kit"] = function()
      error("kit unavailable")
    end
    local orig_select = vim.ui.select
    local prompts = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(items, o, cb)
      prompts[#prompts + 1] = o.prompt
      cb(items[2], 2)
    end
    local ok, err = pcall(require("data").run_auto, "sort", no_range())
    vim.ui.select = orig_select
    package.preload["lib.nvim.ui.kit"] = orig_preload
    package.loaded["lib.nvim.ui.kit"] = had_kit
    assert.is_true(ok, err)
    assert.equals(1, #prompts)
    assert.matches("which format", prompts[1])
    assert.same({ "a: 1", "b: 2" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("names an empty filetype as <empty> in the question rather than printing nothing", function()
    vim.bo[bufnr].filetype = ""
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "prose" })
    local asked = with_select_answer(nil, function()
      require("data").run_auto("pretty", no_range())
    end)
    assert.matches("<empty>", asked[1].title)
  end)

  it("asks about an unclassifiable register and goes on with the same register", function()
    vim.fn.setreg("r", "just some prose", "c")
    local data = require("data")
    local orig_run = data.run
    local runs = {}
    data.run = function(fmt, action, _, _, flags)
      runs[#runs + 1] = { fmt = fmt, action = action, reg = flags and flags.reg }
    end
    local ok, err = pcall(function()
      local asked = with_select_answer(2, function()
        data.run_auto("keys", no_range(), {}, { reg = "r" })
      end)
      assert.matches("from register 'r'", asked[1].title)
    end)
    data.run = orig_run
    assert.is_true(ok, err)
    assert.same({ { fmt = "yaml", action = "keys", reg = "r" } }, runs)
  end)

  it("reports a --reg whose name is not a single character", function()
    local msgs = capture_notify(function()
      require("data").run_auto("pretty", no_range(), {}, { reg = "clipboard" })
    end)
    assert.is_true(said(msgs, "single character"))
  end)

  it("reports a --reg that is empty, from the detect path", function()
    -- `run_auto` reads the register twice: once to sniff the format, once for
    -- the source. This is the first read's failure arm, which the command
    -- layer's own coverage reaches only for an unclassifiable register.
    vim.fn.setreg("r", "", "c")
    local msgs = capture_notify(function()
      require("data").run_auto("pretty", no_range(), {}, { reg = "r" })
    end)
    assert.is_true(said(msgs, "is empty"))
  end)

  it("routes `filter` to data.filter rather than to run", function()
    -- Without pickers.nvim this is the reported-failure arm; with it, the
    -- interactive one. Either way `run` must not be handed "filter" as a
    -- render mode, which would report an unknown-mode render failure instead.
    vim.bo[bufnr].filetype = "json"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local had = package.loaded["pickers.refine"]
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      error("simulated: pickers.nvim not installed")
    end

    local msgs = capture_notify(function()
      require("data").run_auto("filter", no_range())
    end)

    package.preload["pickers.refine"] = nil
    package.loaded["pickers.refine"] = had
    assert.is_true(said(msgs, "requires pickers.nvim"), "reached data.filter, not data.run")
    assert.is_false(said(msgs, "render failed"))
  end)
end)

describe("data.filter -- the arms reachable without pickers.nvim", function()
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
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("reports an unknown format before doing anything else", function()
    local msgs = capture_notify(function()
      require("data").filter("toml", no_range())
    end)
    assert.is_true(said(msgs, "unknown format 'toml'"))
  end)

  it("reports a decode failure before opening any prompt", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "{not json" })
    local msgs = capture_notify(function()
      require("data").filter("json", no_range())
    end)
    assert.is_true(said(msgs, "decode failed"))
    assert.same({ "{not json" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("prefixes every filter report with the format and the action", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local msgs = capture_notify(function()
      require("data").filter("json", no_range(), {}, { preview = true, no_preview = true })
    end)
    local found = false
    for _, m in ipairs(msgs) do
      if m:find("JSON filter: ", 1, true) and m:find("mutually exclusive", 1, true) then
        found = true
      end
    end
    assert.is_true(found, "a bare 'mutually exclusive' would not say which command said it")
  end)
end)

describe("data.setup", function()
  it("is idempotent: a second call re-registers the verbs without erroring", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    local after_first = vim.tbl_count(vim.api.nvim_get_commands({}))

    local ok = pcall(function()
      require("data").setup()
    end)

    assert.is_true(ok)
    assert.equals(
      after_first,
      vim.tbl_count(vim.api.nvim_get_commands({})),
      "four verbs, however often setup runs"
    )
  end)

  it("RESETS rather than accumulating: DEFAULTS is the merge base every time", function()
    -- Pinned because the opposite has been a real bug in a sibling plugin
    -- (replacer.nvim's `setup` merged onto its own previous result, so a
    -- second call could not clear a value). Here the second call starts from
    -- DEFAULTS again, so an option only set by the FIRST call is gone.
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup({ json = { indent = 4 } })
    require("data").setup({ yaml = { indent = 6 } })

    local config = require("data.config")
    assert.equals(2, config.get("json.indent"), "the first call's json.indent did not survive")
    assert.equals(6, config.get("yaml.indent"), "only the second call's options are in effect")
  end)

  it("tolerates a non-table argument", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    local ok = pcall(function()
      require("data").setup("nonsense")
    end)
    assert.is_true(ok)
    assert.equals(2, require("data.config").get("json.indent"))
  end)

  it("exposes exactly the documented public surface", function()
    -- The contract another plugin would code against. Anything added here is
    -- a deliberate API decision; anything removed is a breaking change.
    package.loaded["data"] = nil
    local data = require("data")
    for _, name in ipairs({ "setup", "run", "convert", "filter", "run_auto" }) do
      assert.equals("function", type(data[name]), name .. " is part of the public API")
    end
  end)
end)
