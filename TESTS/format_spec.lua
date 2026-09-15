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

  it(
    "a formatter whose own lib.nvim dependency is missing is dropped, not fatal to the registry",
    function()
      -- Simulated absence via package.preload, not by removing the real
      -- module from the rtp -- same convention filter_spec.lua/detect_spec.lua
      -- use for their own soft dependencies.
      package.loaded["data.format.xml"] = nil
      package.preload["data.format.xml"] = function()
        error("simulated: lib.lua.xml missing from this lib.nvim install")
      end
      package.loaded["data.format"] = nil

      local ok, reloaded = pcall(require, "data.format")

      package.preload["data.format.xml"] = nil
      package.loaded["data.format.xml"] = nil
      package.loaded["data.format"] = nil

      assert.is_true(ok, "the registry itself must not fail to load")
      assert.is_nil(reloaded.get("xml"), "xml is absent, not a crashed require")
      assert.is_not_nil(reloaded.get("json"), "json is unaffected by xml's failure")
      assert.is_not_nil(reloaded.get("yaml"), "yaml is unaffected by xml's failure")
    end
  )
end)
