---@diagnostic disable: need-check-nil
-- TESTS/format_yaml_spec.lua — data.format.yaml

local yaml_fmt = require("data.format.yaml")

describe("data.format.yaml.decode", function()
  it("decodes a plain map", function()
    local value, err = yaml_fmt.decode("a: 1\nb: x\n")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(err)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(1, value.a)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("x", value.b)
  end)

  it("reports an error instead of throwing on bad indentation", function()
    local value, err = yaml_fmt.decode("a: 1\n  b: 2\n")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(value)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)

describe("data.format.yaml.render", function()
  local value = { user = { id = 1, name = "Ana" }, level = "error" }

  it("pretty: multi-line, sorted keys, default 2-space indent", function()
    local lines = yaml_fmt.render(value, "pretty")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user:", "  id: 1", "  name: Ana" }, lines)
  end)

  it("pretty: honors an explicit indent width", function()
    local lines = yaml_fmt.render(value, "pretty", { indent = 4 })
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user:", "    id: 1", "    name: Ana" }, lines)
  end)

  it("sort: identical to pretty (no source key order survives decode)", function()
    local pretty_lines = yaml_fmt.render(value, "pretty")
    local sort_lines = yaml_fmt.render(value, "sort")
    ---@diagnostic disable-next-line: undefined-field
    assert.same(pretty_lines, sort_lines)
  end)

  it("lines: one 'path: value' per leaf, nested keys dotted, sorted", function()
    local lines = yaml_fmt.render(value, "lines")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level: error", "user.id: 1", "user.name: Ana" }, lines)
  end)

  it("keys: only the dotted paths, no values", function()
    local lines = yaml_fmt.render(value, "keys")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "level", "user.id", "user.name" }, lines)
  end)

  it("compact is not supported and reports an error, not a crash", function()
    local lines, err = yaml_fmt.render(value, "compact")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)

  it("an unknown mode is reported as an error, not a crash", function()
    local lines, err = yaml_fmt.render(value, "nonsense")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)
