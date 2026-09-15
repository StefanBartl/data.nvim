---@diagnostic disable: need-check-nil
-- TESTS/usrcmds_spec.lua — the :JSON command, end to end against a real buffer.

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
