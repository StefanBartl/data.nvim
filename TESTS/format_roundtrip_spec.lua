-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/format_roundtrip_spec.lua — decode(render(decode(text))) == decode(text)
--
-- The existing format_{json,yaml,xml}_spec.lua files are entirely example-
-- based (one fixed input, one fixed expected output). This file instead
-- checks an invariant across a spread of varied fixtures per format: decode
-- a document, render it back out, decode that again, and assert the two
-- decoded values are structurally identical -- a class of bug (e.g. a
-- rendering step that quietly drops or reorders data) that a single
-- hand-picked example could miss.

local json_fmt = require("data.format.json")
local yaml_fmt = require("data.format.yaml")
local xml_fmt = require("data.format.xml")

describe("data.format.json round-trip (decode -> compact render -> decode)", function()
  local fixtures = {
    '{"a":1,"b":"two","c":true,"d":null}',
    '{"nested":{"a":{"b":{"c":[1,2,3]}}}}',
    '{"empty_obj":{},"empty_arr":[]}',
    '[1,"two",false,null,{"five":5}]',
    '{"unicode":"caf\\u00e9","escaped":"line1\\nline2\\ttab"}',
  }

  for i, text in ipairs(fixtures) do
    it(("fixture %d round-trips unchanged"):format(i), function()
      local value1, derr1 = json_fmt.decode(text)
      assert.is_nil(derr1)

      local rendered, rerr = json_fmt.render(value1, "compact")
      assert.is_nil(rerr)

      local value2, derr2 = json_fmt.decode(rendered[1])
      assert.is_nil(derr2)

      assert.same(value1, value2)
    end)
  end
end)

describe("data.format.yaml round-trip (decode -> pretty render -> decode)", function()
  -- yaml.render has no "compact" mode (see format_yaml_spec.lua) -- "pretty"
  -- is the only round-trippable mode.
  local fixtures = {
    "a: 1\nb: two\nc: true\n",
    "nested:\n  a:\n    b:\n      c: 1\n",
    "list:\n  - 1\n  - 2\n  - 3\n",
    "empty_obj: {}\n",
  }

  for i, text in ipairs(fixtures) do
    it(("fixture %d round-trips unchanged"):format(i), function()
      local value1, derr1 = yaml_fmt.decode(text)
      assert.is_nil(derr1)

      local rendered, rerr = yaml_fmt.render(value1, "pretty")
      assert.is_nil(rerr)

      local value2, derr2 = yaml_fmt.decode(table.concat(rendered, "\n"))
      assert.is_nil(derr2)

      assert.same(value1, value2)
    end)
  end
end)

describe("BUG: the JSON round-trip above cannot see an empty object becoming an array", function()
  -- `assert.same` compares table CONTENTS, and an empty object and an empty
  -- array have identical (that is, no) contents in Lua. Fixture 3 above
  -- (`{"empty_obj":{},"empty_arr":[]}`) therefore passes while the document's
  -- shape is in fact being changed -- exactly the class of bug the round-trip
  -- invariant was written to catch, slipping through its equality relation.
  --
  -- The distinction is NOT lost information: `vim.json.decode` marks an empty
  -- object with `vim.empty_dict()`'s metatable and leaves an empty array
  -- plain, and `lib.nvim.json.decode`'s null normalization carries that
  -- metatable through. `lib.lua.json.encode` then ignores it and writes `[]`
  -- for both -- so `:JSON pretty` on a config file silently rewrites every
  -- empty object as an empty array, which for most consumers of that file is
  -- a type change and not a formatting change. The defect is in lib.nvim's
  -- encoder; this pins the consequence at data.nvim's own surface.

  it("decode keeps the two apart", function()
    local value = json_fmt.decode('{"o":{},"a":[]}')
    assert.is_not_nil(getmetatable(value.o), "an empty object carries vim.empty_dict's metatable")
    assert.is_nil(getmetatable(value.a), "an empty array carries none")
  end)

  it("BUG: compact render collapses both onto []", function()
    local value = json_fmt.decode('{"o":{},"a":[]}')
    assert.same(
      { '{"a":[],"o":[]}' },
      json_fmt.render(value, "compact"),
      "BUG: `o` became an array"
    )
  end)

  it("BUG: so the round trip preserves the contents but not the shape", function()
    local value1 = json_fmt.decode('{"o":{},"a":[]}')
    local value2 = json_fmt.decode((json_fmt.render(value1, "compact"))[1])
    assert.same(value1, value2, "contents match, which is why the fixture above passes")
    assert.is_not_nil(getmetatable(value1.o))
    assert.is_nil(getmetatable(value2.o), "BUG: the empty object did not survive the round trip")
  end)

  it("BUG: and `lines` labels an empty object leaf as an array, unlike yaml", function()
    -- `data.format.yaml`'s own `display` deliberately special-cases an empty
    -- table to `{}` rather than letting the encoder decide. `format/json.lua`
    -- does not, so the two sibling helpers disagree about the same value.
    local value = json_fmt.decode('{"o":{}}')
    assert.same({ "o: []" }, json_fmt.render(value, "lines"), "BUG: an object shown as an array")
    assert.same(
      { "o: {}" },
      yaml_fmt.render({ o = {} }, "lines"),
      "yaml says {} for the same value"
    )
  end)
end)

describe("data.format.xml round-trip (decode -> compact render -> decode)", function()
  local fixtures = {
    '<user id="1"><name>Ana</name></user>',
    "<a><b><c>1</c><c>2</c></b></a>",
    "<empty></empty>",
    '<root a="1" b="2"><child/></root>',
    "<items><item>x</item><item>y</item><item>z</item></items>",
  }

  for i, text in ipairs(fixtures) do
    it(("fixture %d round-trips unchanged"):format(i), function()
      local value1, derr1 = xml_fmt.decode(text)
      assert.is_nil(derr1)

      local rendered, rerr = xml_fmt.render(value1, "compact")
      assert.is_nil(rerr)

      local value2, derr2 = xml_fmt.decode(rendered[1])
      assert.is_nil(derr2)

      assert.same(value1, value2)
    end)
  end
end)
