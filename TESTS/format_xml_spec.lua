---@diagnostic disable: need-check-nil
-- TESTS/format_xml_spec.lua — data.format.xml

local xml_fmt = require("data.format.xml")

describe("data.format.xml.decode", function()
  it("decodes a simple element tree", function()
    local value, err = xml_fmt.decode('<user id="1"><name>Ana</name></user>')
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(err)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("user", value.tag)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("1", value.attrs.id)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("Ana", value.children[1].children[1])
  end)

  it("reports an error instead of throwing on malformed input", function()
    local value, err = xml_fmt.decode("<a><b></c></a>")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(value)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)

describe("data.format.xml.render", function()
  local value = {
    tag = "user",
    attrs = { id = "1" },
    children = { { tag = "name", attrs = {}, children = { "Ana" } } },
  }

  it("pretty: multi-line, default 2-space indent", function()
    local lines = xml_fmt.render(value, "pretty")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '<user id="1">', "  <name>Ana</name>", "</user>" }, lines)
  end)

  it("pretty: honors an explicit indent width", function()
    local lines = xml_fmt.render(value, "pretty", { indent = 4 })
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '<user id="1">', "    <name>Ana</name>", "</user>" }, lines)
  end)

  it("compact: exactly one line", function()
    local lines = xml_fmt.render(value, "compact")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '<user id="1"><name>Ana</name></user>' }, lines)
  end)

  it(
    "sort: identical to pretty (attributes are always sorted; element order never changes)",
    function()
      local pretty_lines = xml_fmt.render(value, "pretty")
      local sort_lines = xml_fmt.render(value, "sort")
      ---@diagnostic disable-next-line: undefined-field
      assert.same(pretty_lines, sort_lines)
    end
  )

  it("lines: flattens the raw element tree, not a JSON-like objectification", function()
    local lines = xml_fmt.render(value, "lines")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({
      "attrs.id: 1",
      "children.1.attrs: {}",
      "children.1.children.1: Ana",
      "children.1.tag: name",
      "tag: user",
    }, lines)
  end)

  it("keys: only the dotted paths, no values", function()
    local lines = xml_fmt.render(value, "keys")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({
      "attrs.id",
      "children.1.attrs",
      "children.1.children.1",
      "children.1.tag",
      "tag",
    }, lines)
  end)

  it("an unknown mode is reported as an error, not a crash", function()
    local lines, err = xml_fmt.render(value, "nonsense")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_not_nil(err)
  end)
end)
