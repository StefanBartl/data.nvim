-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/usrcmds_spec.lua — the :JSON command, end to end against a real buffer.

--- Capture every `vim.notify` call made during `fn()`, pumping the event
--- loop briefly afterwards so a `vim.schedule`-deferred notify (every
--- `data.init`/`data.config` warning/error is scheduled, not synchronous --
--- see their own doc comments for why) has actually run before this
--- returns. Restores the real `vim.notify` regardless of whether `fn()`
--- errors.
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

describe(":JSON", function()
  local bufnr

  before_each(function()
    -- Fresh module instances: data.bindings.usrcmds registers the :JSON
    -- usercmd once via lib.nvim's composer registry, and re-requiring
    -- data.init without clearing it would try to redefine the same command
    -- every test, masking a setup() bug that only shows up on a second call.
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

  it("bare :JSON pretty-prints the whole buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"b":2,"a":1}' })
    vim.cmd("JSON")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1,', '  "b": 2', "}" }, lines)
  end)

  it(":JSON compact collapses onto one line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "{", '  "a": 1', "}" })
    vim.cmd("JSON compact")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, lines)
  end)

  it(":JSON pretty 4 uses a 4-space indent", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.cmd("JSON pretty 4")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '    "a": 1', "}" }, lines)
  end)

  it(":JSON pretty 0 warns about the invalid indent and falls back to the default", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local calls = capture_notify(function()
      vim.cmd("JSON pretty 0")
    end)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}" }, lines, "falls back to the default 2-space indent")

    local found = false
    for _, c in ipairs(calls) do
      if c.msg:match("invalid indent") then
        found = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(found, "expected a warning naming the invalid indent")
  end)

  it("a visual-selection range only rewrites the selected lines", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "before",
      '{"a":1}',
      "after",
    })
    vim.cmd("2JSON compact")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "before", '{"a":1}', "after" }, lines, "single-line range round-trips unchanged")
  end)

  it(":JSON lines flattens nested keys onto dotted-path lines", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1},"level":"error"}' })
    vim.cmd("JSON lines")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user.id: 1" }, lines)
  end)

  it("malformed JSON leaves the buffer untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "{not json" })
    vim.cmd("JSON")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{not json" }, lines)
  end)

  it("config.json.indent is honored when no explicit indent arg is given", function()
    -- Regression: config.<fmt>.indent/sep used to be merged and typed but
    -- never actually read by data.run(), so a user-set json.indent had no
    -- effect whatsoever unless spelled out on every single invocation.
    package.loaded["data"] = nil
    package.loaded["data.config"] = nil
    package.loaded["data.bindings"] = nil
    package.loaded["data.bindings.usrcmds"] = nil
    require("data").setup({ json = { indent = 4 } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.cmd("JSON pretty")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '    "a": 1', "}" }, lines)
  end)

  it("config.json.sep is honored when --sep is given with no value", function()
    -- Regression: `opts.sep or defaults.sep` treated an empty string (what
    -- `--sep=` with nothing after the `=` parses to) as "given", silently
    -- winning over the configured default instead of falling back to it.
    package.loaded["data"] = nil
    package.loaded["data.config"] = nil
    package.loaded["data.bindings"] = nil
    package.loaded["data.bindings.usrcmds"] = nil
    require("data").setup({ json = { sep = "/" } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1}}' })
    vim.cmd("JSON lines --sep=")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "user/id: 1" }, lines)
  end)

  it("an unexpected runtime error during decode is caught, not raised past vim.cmd()", function()
    -- Regression: formatter.decode/render used to be called with no pcall,
    -- so a runtime error (e.g. a decoder's recursion-depth guard tripping,
    -- or any other unforeseen throw) would surface as a raw Vim error
    -- instead of the graceful notify-and-leave-untouched every other
    -- failure path in this module gets.
    local json_fmt = require("data.format.json")
    local original_decode = json_fmt.decode
    json_fmt.decode = function()
      error("boom: simulated unexpected decode failure")
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    local cmd_ok = pcall(vim.cmd, "JSON")
    json_fmt.decode = original_decode

    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(cmd_ok, "vim.cmd('JSON') itself does not raise -- the error is caught")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, lines, "buffer is left untouched when decode throws unexpectedly")
  end)

  it(":JSON ndjson pretty-prints each line as its own object", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}', '{"b":2}' })
    vim.cmd("JSON ndjson")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}", "{", '  "b": 2', "}" }, lines)
  end)

  it(":JSON ndjson leaves a line that fails to decode unchanged and warns once", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}', "not json", '{"b":2}' })
    vim.cmd("JSON ndjson")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}", "not json", "{", '  "b": 2', "}" }, lines)
  end)

  it(":JSON ndjson escalates its warning when most lines fail to decode", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "not json 1", "not json 2", '{"a":1}' })
    local calls = capture_notify(function()
      vim.cmd("JSON ndjson")
    end)

    local found = false
    for _, c in ipairs(calls) do
      if c.msg:match("may not actually be ndjson") then
        found = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(found, "expected the escalated message at a 2/3 skip ratio")
  end)

  it(":JSON ndjson keeps blank lines as-is", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}', "", '{"b":2}' })
    vim.cmd("JSON ndjson")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "a": 1', "}", "", "{", '  "b": 2', "}" }, lines)
  end)

  it(":JSON to yaml converts the scope to YAML", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"user":{"id":1},"level":"error"}' })
    vim.cmd("JSON to yaml")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user:", "  id: 1" }, lines)
  end)
end)

describe(":YAML", function()
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

  it("bare :YAML pretty-prints the whole buffer, sorted keys", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "b: 2", "a: 1" })
    vim.cmd("YAML")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: 1", "b: 2" }, lines)
  end)

  it("has no :YAML compact route -- unknown subcommand, buffer untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a: 1" })
    vim.cmd("YAML compact")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same(
      { "a: 1" },
      lines,
      "an unmatched route never reaches data.run, so the buffer is untouched"
    )
  end)

  it(":YAML lines flattens nested keys onto dotted-path lines", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user:", "  id: 1", "level: error" })
    vim.cmd("YAML lines")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user.id: 1" }, lines)
  end)

  it("malformed YAML (bad indentation) leaves the buffer untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a: 1", "  b: 2" })
    vim.cmd("YAML")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: 1", "  b: 2" }, lines)
  end)

  it(":YAML to json converts the scope to JSON", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "level: error", "user:", "  id: 1" })
    vim.cmd("YAML to json")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "level": "error",', '  "user": {', '    "id": 1', "  }", "}" }, lines)
  end)
end)

describe(":XML", function()
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

  it("bare :XML pretty-prints the whole buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '<a id="1"><b>x</b></a>' })
    vim.cmd("XML")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '<a id="1">', "  <b>x</b>", "</a>" }, lines)
  end)

  it(":XML compact collapses onto one line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '<a id="1">', "  <b>x</b>", "</a>" })
    vim.cmd("XML compact")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '<a id="1"><b>x</b></a>' }, lines)
  end)

  it(":XML keys flattens the raw element tree", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "<a><b>1</b></a>" })
    vim.cmd("XML keys")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({
      "attrs",
      "children.1.attrs",
      "children.1.children.1",
      "children.1.tag",
      "tag",
    }, lines)
  end)

  it("malformed XML (mismatched closing tag) leaves the buffer untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "<a><b></c></a>" })
    vim.cmd("XML")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "<a><b></c></a>" }, lines)
  end)
end)
