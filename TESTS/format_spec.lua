---@diagnostic disable: need-check-nil
-- TESTS/format_spec.lua — data.format (formatter registry)

describe("data.format.get", function()
  local formats

  before_each(function()
    package.loaded["data.format"] = nil
    formats = require("data.format")
  end)

  it("resolves json/yaml/xml to their formatter modules", function()
    assert.equals(require("data.format.json"), formats.get("json"))
    assert.equals(require("data.format.yaml"), formats.get("yaml"))
    assert.equals(require("data.format.xml"), formats.get("xml"))
  end)

  it("returns nil for an unregistered format name", function()
    assert.is_nil(formats.get("toml"))
  end)

  it("every registered formatter exposes decode and render", function()
    for name, formatter in pairs(formats.formats) do
      assert.equals("function", type(formatter.decode), name .. ".decode")
      assert.equals("function", type(formatter.render), name .. ".render")
    end
  end)
end)
