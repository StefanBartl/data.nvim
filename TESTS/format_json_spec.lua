---@diagnostic disable: need-check-nil
-- TESTS/format_json_spec.lua — data.format.json

local json_fmt = require("data.format.json")

describe("data.format.json.decode", function()
  it("decodes a plain object", function()
    local value, err = json_fmt.decode('{"a":1,"b":"x"}')
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(err)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(1, value.a)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("x", value.b)
  end)

  it("reports an error instead of throwing on malformed input", function()
    local value, err = json_fmt.decode("{not json")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(value)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)

describe("data.format.json.render", function()
  local value = { user = { id = 1, name = "Ana" }, level = "error" }

  it("pretty: multi-line, sorted keys, default 2-space indent", function()
    local lines = json_fmt.render(value, "pretty")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(#lines > 1, "pretty output spans multiple lines")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals('  "level": "error",', lines[2])
  end)

  it("pretty: honors an explicit indent width", function()
    local lines = json_fmt.render(value, "pretty", { indent = 4 })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals('    "level": "error",', lines[2])
  end)

  it("compact: exactly one line", function()
    local lines = json_fmt.render(value, "compact")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(1, #lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals('{"level":"error","user":{"id":1,"name":"Ana"}}', lines[1])
  end)

  it("sort: identical to pretty (no source key order survives decode)", function()
    local pretty_lines = json_fmt.render(value, "pretty")
    local sort_lines = json_fmt.render(value, "sort")
    ---@diagnostic disable-next-line: undefined-field
    assert.same(pretty_lines, sort_lines)
  end)

  it("lines: one 'path: value' per leaf, nested keys dotted, sorted", function()
    local lines = json_fmt.render(value, "lines")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user.id: 1", "user.name: Ana" }, lines)
  end)

  it("lines: a custom separator is threaded through path_flatten", function()
    local lines = json_fmt.render(value, "lines", { sep = "/" })
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user/id: 1", "user/name: Ana" }, lines)
  end)

  it("keys: only the dotted paths, no values", function()
    local lines = json_fmt.render(value, "keys")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level", "user.id", "user.name" }, lines)
  end)

  it("null: vim.json.decode's NULL sentinel displays as the literal 'null'", function()
    local decoded = json_fmt.decode('{"a":null}')
    local lines = json_fmt.render(decoded, "lines")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: null" }, lines)
  end)

  it("an unknown mode is reported as an error, not a crash", function()
    local lines, err = json_fmt.render(value, "nonsense")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)
