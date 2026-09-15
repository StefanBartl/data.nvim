-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/config_spec.lua — data.config

describe("data.config", function()
  local config

  before_each(function()
    -- Fresh module instance: `options` is a module-level singleton, and a
    -- stale merge from a previous test would mask the bug this spec exists
    -- to catch.
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    config = require("data.config")
  end)

  it("starts with the shipped defaults before setup() is ever called", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("json.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("json.sep"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("yaml.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("yaml.sep"))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_false(config.get("keymaps.preset"))
  end)

  it("deep-merges a partial override, leaving untouched defaults in place", function()
    config.setup({ json = { indent = 4 } })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(4, config.get("json.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("json.sep"), "sep survives an override that only touches indent")
  end)

  it("tolerates setup(nil) / setup() with no argument", function()
    config.setup(nil)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("json.indent"))
  end)
end)
