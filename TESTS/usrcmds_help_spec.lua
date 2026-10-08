-- Test code: when something here comes back nil -- a require, a handle lookup -- this file must
-- crash and name it. The nil guards LuaLS asks for below would hide the very failure this spec
-- exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/usrcmds_help_spec.lua -- every flag and positional argument of `:JSON`/`:YAML`/`:XML`/
-- `:Data` has a line in the option float.
--
-- lib.nvim's help float (the option cheatsheet on the command line) shows one line per
-- `--flag` / `key=`, taken from the `desc` of its spec, and one for the next positional argument
-- (`to <format>`; the `[indent]` of `pretty`/`sort`/`ndjson` is a built-in INT and explains itself).
-- This pins that nothing of any of the four verbs ships without one, and that the lines stay what
-- the float expects: one short line, no trailing full stop.

local VERBS = { "JSON", "YAML", "XML", "Data" }

describe("the option float of the format verbs", function()
  local composer = require("lib.nvim.bindings.usercmd.composer")
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
  end)

  for _, verb in ipairs(VERBS) do
    it((":%s leaves no flag without a description"):format(verb), function()
      local missing = {}
      for _, m in ipairs(composer.help.undocumented(verb)) do
        missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
      end
      assert.equals("", table.concat(missing, ", "))
    end)

    it((":%s leaves no positional argument without a description"):format(verb), function()
      local missing = {}
      for _, m in ipairs(composer.help.undocumented(verb, { args = true })) do
        missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
      end
      assert.equals("", table.concat(missing, ", "))
    end)

    it((":%s keeps every argument text to one short line"):format(verb), function()
      local handle = composer.registry()[verb]
      assert.is_truthy(handle)
      for _, route in ipairs(handle:spec().routes or {}) do
        for _, arg in ipairs(route.args or {}) do
          local texts = { arg.desc }
          for _, text in pairs(arg.enum_desc or {}) do
            texts[#texts + 1] = text
          end
          for _, text in ipairs(texts) do
            local what = ("%s of %s %s"):format(arg.name, verb, table.concat(route.path, " "))
            assert.is_nil(text:find("\n", 1, true), what .. " is one line")
            assert.is_true(#text <= 80, what .. " stays short")
            assert.is_nil(text:find("%.$"), what .. " has no trailing full stop")
          end
        end
      end
    end)

    it((":%s keeps every description to one short line"):format(verb), function()
      local handle = composer.registry()[verb]
      assert.is_truthy(handle)
      local seen = 0
      for _, route in ipairs(handle:spec().routes or {}) do
        for _, flag in ipairs(route.flags or {}) do
          seen = seen + 1
          local text = entries.flag_desc(route, flag) or ""
          local what = ("--%s of %s %s"):format(flag.name, verb, table.concat(route.path, " "))
          assert.is_true(text ~= "", what .. " shows a text")
          assert.is_nil(text:find("\n", 1, true), what .. " is one line")
          assert.is_true(#text <= 80, what .. " stays short")
          assert.is_nil(text:find("%.$"), what .. " has no trailing full stop")
        end
      end
      assert.is_true(seen > 0, "the routes' flags were actually walked")
    end)
  end
end)
