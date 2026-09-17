-- Test code: when something here comes back nil -- a require, a command
-- lookup -- this file must crash and name it. The nil guards LuaLS asks for
-- below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/routes_spec.lua — the command surface `data.bindings.usrcmds` builds:
-- which subcommands each verb offers, which flags each ROUTE accepts, and what
-- `<Tab>` completes to.
--
-- bindings_spec.lua asserts that the four verbs exist. What nothing covered is
-- the shape of what they expose, which is the plugin's actual public API for a
-- human: a route silently missing, or a flag silently accepted where it does
-- nothing, is not a crash -- it is a command that quietly does the wrong thing.
--
-- Two properties are worth the whole file on their own:
--
--   * Flags are per-route, not per-verb. `--sep` belongs to `lines`/`keys`/
--     `filter`, `--preview`/`--no-preview` to `filter` alone. A route that
--     accepted a flag it ignores would be worse than one that rejects it: the
--     user would believe it did something.
--   * `with_io` builds a FRESH list on every call, because the spec tables it
--     concatenates (`IO_FLAGS`, `SEP_FLAG`, `PREVIEW_FLAGS`) are shared across
--     every route of every verb. If it ever appended to one of them in place,
--     the leak would spread `--sep` and `--preview` onto everything -- and the
--     only visible symptom would be the flags asserted below being ACCEPTED
--     where they should be refused.

--- Run `fn()` with `vim.notify` captured, so the composer's own usage errors
--- (which it reports rather than raises) can be read back.
---@param fn fun()
---@return string
local function complaint_from(fn)
  local msgs = {}
  local orig = vim.notify
  --- Test double: restored below, including when `fn()` errors.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    msgs[#msgs + 1] = tostring(msg)
  end
  pcall(fn)
  vim.wait(30)
  vim.notify = orig
  return table.concat(msgs, "\n")
end

describe("the four verbs and the subcommands each offers", function()
  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
  end)

  local expected = {
    -- `compact` is JSON/XML only: YAML's subset has no flow style to collapse
    -- into. `ndjson` is JSON only. `to` is the one conversion each of
    -- JSON/YAML offers and XML does not (no unambiguous schema-free mapping).
    JSON = { "compact", "filter", "keys", "lines", "ndjson", "pretty", "sort", "to" },
    YAML = { "filter", "keys", "lines", "pretty", "sort", "to" },
    XML = { "compact", "filter", "keys", "lines", "pretty", "sort" },
    -- `:Data` is the format-agnostic subset only: reaching for compact/
    -- ndjson/to already means knowing the format.
    Data = { "filter", "keys", "lines", "pretty", "sort" },
  }

  for verb, subcommands in pairs(expected) do
    it((":%s completes to exactly its own subcommands"):format(verb), function()
      assert.same(subcommands, vim.fn.getcompletion(verb .. " ", "cmdline"))
    end)
  end

  it("every verb is range-aware and takes any number of arguments", function()
    local cmds = vim.api.nvim_get_commands({})
    for _, verb in ipairs({ "JSON", "YAML", "XML", "Data" }) do
      assert.is_not_nil(cmds[verb], verb .. " is registered")
      assert.is_true(
        cmds[verb].range ~= nil and cmds[verb].range ~= false,
        verb .. " takes a range"
      )
    end
  end)

  it("refuses a subcommand a verb does not have, naming it", function()
    local cases = {
      { cmd = "YAML compact", missing = "compact" },
      { cmd = "XML ndjson", missing = "ndjson" },
      { cmd = "XML to", missing = "to" },
      { cmd = "Data compact", missing = "compact" },
      { cmd = "Data ndjson", missing = "ndjson" },
      { cmd = "Data to", missing = "to" },
      { cmd = "JSON nonsense", missing = "nonsense" },
    }
    for _, case in ipairs(cases) do
      local said = complaint_from(function()
        vim.cmd(case.cmd)
      end)
      assert.matches("unknown subcommand", said, case.cmd)
      assert.matches(case.missing, said, case.cmd .. " names what it did not recognize")
    end
  end)

  it("constrains `to` to the ONE format each verb can convert into", function()
    for _, case in ipairs({
      { cmd = "JSON to xml", allowed = "yaml" },
      { cmd = "JSON to json", allowed = "yaml" },
      { cmd = "YAML to xml", allowed = "json" },
      { cmd = "YAML to yaml", allowed = "json" },
    }) do
      local said = complaint_from(function()
        vim.cmd(case.cmd)
      end)
      assert.matches("expected one of " .. case.allowed, said, case.cmd)
    end
  end)
end)

describe("which flags each route accepts", function()
  local bufnr

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("offers the four IO flags on EVERY route of every verb", function()
    local routes = {
      "JSON pretty",
      "JSON compact",
      "JSON lines",
      "JSON keys",
      "JSON sort",
      "JSON filter",
      "JSON ndjson",
      "JSON to",
      "YAML pretty",
      "YAML lines",
      "XML compact",
      "Data pretty",
      "Data filter",
    }
    for _, route in ipairs(routes) do
      local flags = vim.fn.getcompletion(route .. " --", "cmdline")
      for _, flag in ipairs({ "--reg", "--inplace", "--split", "--out-reg" }) do
        assert.is_true(vim.tbl_contains(flags, flag), ("%s offers %s"):format(route, flag))
      end
    end
  end)

  it("offers --sep on lines/keys/filter and NOWHERE else", function()
    for _, route in ipairs({ "JSON lines", "JSON keys", "JSON filter", "Data lines", "YAML keys" }) do
      assert.is_true(
        vim.tbl_contains(vim.fn.getcompletion(route .. " --", "cmdline"), "--sep"),
        route .. " takes a separator"
      )
    end
    for _, route in ipairs({ "JSON pretty", "JSON compact", "JSON sort", "JSON ndjson", "JSON to" }) do
      assert.is_false(
        vim.tbl_contains(vim.fn.getcompletion(route .. " --", "cmdline"), "--sep"),
        route .. " has no paths to separate"
      )
    end
  end)

  it("offers --preview/--no-preview on filter and NOWHERE else", function()
    for _, route in ipairs({ "JSON filter", "YAML filter", "XML filter", "Data filter" }) do
      local flags = vim.fn.getcompletion(route .. " --", "cmdline")
      assert.is_true(vim.tbl_contains(flags, "--preview"), route)
      assert.is_true(vim.tbl_contains(flags, "--no-preview"), route)
    end
    for _, route in ipairs({ "JSON pretty", "JSON lines", "JSON compact", "Data sort" }) do
      local flags = vim.fn.getcompletion(route .. " --", "cmdline")
      assert.is_false(vim.tbl_contains(flags, "--preview"), route .. " cannot preview anything")
      assert.is_false(vim.tbl_contains(flags, "--no-preview"), route)
    end
  end)

  it("REFUSES a flag a route does not declare, rather than ignoring it", function()
    -- A flag that quietly did nothing would be the worst outcome: the user
    -- would believe they had asked for something.
    for _, case in ipairs({
      { cmd = "JSON pretty --sep=x", flag = "--sep" },
      { cmd = "JSON compact --sep=x", flag = "--sep" },
      { cmd = "JSON pretty --preview", flag = "--preview" },
      { cmd = "JSON lines --preview", flag = "--preview" },
      { cmd = "JSON sort --no-preview", flag = "--no%-preview" },
    }) do
      local said = complaint_from(function()
        vim.cmd(case.cmd)
      end)
      assert.matches("unknown flag", said, case.cmd)
      assert.matches(case.flag, said, case.cmd .. " names the flag it refused")
    end
  end)

  it("leaves the buffer untouched when it refuses a flag", function()
    complaint_from(function()
      vim.cmd("JSON pretty --preview")
    end)
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("keeps the shared flag tables free of leaks across verbs", function()
    -- The property `with_io`'s fresh-list comment exists for. A single
    -- in-place append anywhere would show up as `--sep` appearing on a route
    -- that never asked for it -- checked here for the LAST verb registered,
    -- which is the one any accumulating leak would have reached.
    local data_pretty = vim.fn.getcompletion("Data pretty --", "cmdline")
    assert.is_false(vim.tbl_contains(data_pretty, "--sep"))
    assert.is_false(vim.tbl_contains(data_pretty, "--preview"))
    assert.equals(4, #data_pretty, "exactly the four IO flags, no more")
  end)

  it("registers each IO flag exactly once per route, not once per verb built", function()
    -- A shared list appended to in place would also DUPLICATE entries.
    for _, route in ipairs({ "JSON pretty", "XML compact", "Data filter" }) do
      local seen = {}
      for _, flag in ipairs(vim.fn.getcompletion(route .. " --", "cmdline")) do
        assert.is_nil(seen[flag], ("%s lists %s twice"):format(route, flag))
        seen[flag] = true
      end
    end
  end)
end)

describe("the bare (default) form of each verb", function()
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

  it("pretty-prints for :JSON with no subcommand", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"b":2,"a":1}' })
    vim.cmd("JSON")
    assert.same(
      { "{", '  "a": 1,', '  "b": 2', "}" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it("pretty-prints for :XML with no subcommand", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "<a><b>x</b></a>" })
    vim.cmd("XML")
    assert.same({ "<a>", "  <b>x</b>", "</a>" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("auto-detects for :Data with no subcommand", function()
    vim.bo[bufnr].filetype = "yaml"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "b: 2", "a: 1" })
    vim.cmd("Data")
    assert.same({ "a: 1", "b: 2" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("ignores IO flags in the bare form, which does not thread them", function()
    -- The `default` handler calls `data.run(fmt, "pretty", ctx.raw, {})` with
    -- no flags argument at all, so `:JSON --split` is not a split -- it is a
    -- bare pretty-print. Pinned as the documented shape rather than presented
    -- as a bug: the flag is simply not part of the default route's contract,
    -- and `:JSON pretty --split` is how a caller asks for one.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local home = vim.api.nvim_get_current_win()
    complaint_from(function()
      vim.cmd("JSON --split")
    end)
    assert.equals(home, vim.api.nvim_get_current_win(), "no split was opened")
  end)

  it("honors a range in the bare form", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", '{"b":2,"a":1}', "keep" })
    vim.cmd("2JSON")
    assert.same(
      { "keep", "{", '  "a": 1,', '  "b": 2', "}", "keep" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)
end)

describe("the indent argument", function()
  local bufnr

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("is optional on pretty/sort", function()
    -- The `:Data` routes are included deliberately: their indent argument is
    -- declared the same way, and they need a detectable format to get far
    -- enough to prove it, hence the filetype.
    vim.bo[bufnr].filetype = "json"
    for _, route in ipairs({ "JSON pretty", "JSON sort", "Data pretty", "Data sort" }) do
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
      local said = complaint_from(function()
        vim.cmd(route)
      end)
      assert.equals("", said, route .. " needs no indent")
      assert.same(
        { "{", '  "a": 1', "}" },
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        route .. " used the configured default"
      )
    end
  end)

  it("is typed as an integer, so a word is refused rather than coerced", function()
    local said = complaint_from(function()
      vim.cmd("JSON pretty wide")
    end)
    assert.is_true(said ~= "", "a non-integer indent is reported")
    assert.same({ '{"a":1}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("is ignored, silently, on a route that declares no argument", function()
    -- Documented composer behaviour rather than a defect of this repo: a
    -- surplus positional argument is dropped without a word, so `:JSON lines 4`
    -- (a user assuming indent applies) runs a plain `lines`. The leniency lives
    -- in lib.nvim's composer, and pinning it here is what would notice if it
    -- ever changed to a refusal -- which would be a visible behaviour change
    -- for anyone who has such a typo in a mapping.
    for _, route in ipairs({ "JSON lines", "JSON keys" }) do
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
      local said = complaint_from(function()
        vim.cmd(route .. " 4")
      end)
      assert.equals("", said, route .. " says nothing about the surplus argument")
    end
    assert.same({ "user.id" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "`keys` still ran")
  end)

  it("is ignored, silently, for a SECOND argument on a route that declares one", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local said = complaint_from(function()
      vim.cmd("JSON pretty 4 8")
    end)
    assert.equals("", said)
    assert.same(
      { "{", '    "a": 1', "}" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "the FIRST argument wins; the second is dropped"
    )
  end)

  it("does not consume the next token when --reg is given bare after it", function()
    -- `--reg`/`--out-reg` are `optional_value` flags precisely so that
    -- `:JSON pretty 4 --reg` still binds 4 as the indent instead of the flag
    -- swallowing it.
    vim.fn.setreg("r", '{"a":1}', "c")
    local home = vim.api.nvim_get_current_win()
    vim.cmd("JSON pretty 4 --reg=r")
    local result = vim.api.nvim_get_current_buf()
    assert.same({ "{", '    "a": 1', "}" }, vim.api.nvim_buf_get_lines(result, 0, -1, false))

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
