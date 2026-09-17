-- Test code: when something here comes back nil -- a require, a wrapped call
-- -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/safe_call_spec.lua — data.util.safe_call, the `pcall` wrapper both
-- data.init and data.filter route every decode/render/path_flatten call
-- through. It had no spec of its own: it was only ever exercised indirectly,
-- by the two specs that simulate a throwing decoder.
--
-- Its whole reason to exist is a shape distinction, so that is what this
-- pins. `lib.nvim.safe_api.safe_call` normalizes to `(ok, result, err)` and
-- keeps only the FIRST return value -- but every function wrapped here returns
-- its own `(value, err)` pair on an ordinary, non-throwing failure, and that
-- second value must survive the wrap. A regression to the lib.nvim helper
-- would silently turn every reported decode error into a nil error message.

local safe_call = require("data.util.safe_call")

describe("data.util.safe_call -- the non-throwing path", function()
  it("passes a single return value straight through", function()
    local result, err = safe_call(function()
      return "value"
    end)
    assert.equals("value", result)
    assert.is_nil(err)
  end)

  it("passes a (nil, err) failure pair through, BOTH halves", function()
    -- The distinction the module exists for. A wrapper that kept only the
    -- first return value would report `nil` as the reason for every decode
    -- failure in the plugin.
    local result, err = safe_call(function()
      return nil, "invalid JSON: something specific"
    end)
    assert.is_nil(result)
    assert.equals("invalid JSON: something specific", err)
  end)

  it("passes a (value, err) pair through when a function returns both", function()
    local result, err = safe_call(function()
      return "partial", "but also a warning"
    end)
    assert.equals("partial", result)
    assert.equals("but also a warning", err)
  end)

  it("drops a THIRD return value, which no caller here has", function()
    -- Documented limit rather than a defect: the two call sites wrap
    -- `decode`/`render`/`path_flatten`, all of which return two values. Pinned
    -- so that adding a third-value contract upstream shows up here first.
    local a, b, c = safe_call(function()
      return 1, 2, 3
    end)
    assert.equals(1, a)
    assert.equals(2, b)
    assert.is_nil(c)
  end)

  it("returns nothing for a function that returns nothing", function()
    local result, err = safe_call(function() end)
    assert.is_nil(result)
    assert.is_nil(err)
  end)
end)

describe("data.util.safe_call -- the throwing path", function()
  it("collapses a thrown string into the same (nil, err) shape", function()
    local result, err = safe_call(function()
      error("boom")
    end)
    assert.is_nil(result)
    assert.matches("boom", err)
  end)

  it("keeps the file:line prefix Lua adds, which names the culprit", function()
    local result, err = safe_call(function()
      error("boom")
    end)
    assert.is_nil(result)
    assert.matches("safe_call_spec%.lua:%d+", err, "the report says where it came from")
  end)

  it("stringifies a thrown non-string rather than returning a table as the error", function()
    -- Every caller formats `err` into a notification with `%s`, so a table
    -- error has to become a string HERE -- not at the notify site, where it
    -- would be one more thing that can throw.
    local result, err = safe_call(function()
      error({ code = 42 })
    end)
    assert.is_nil(result)
    assert.equals("string", type(err))
  end)

  it("catches an error raised at level 0 (no position prefix)", function()
    local result, err = safe_call(function()
      error("bare message", 0)
    end)
    assert.is_nil(result)
    assert.equals("bare message", err)
  end)

  it("catches a stack overflow from unbounded recursion", function()
    -- The case the module's doc comment names as the reason it exists: the
    -- belt to the decoders' own recursion-depth suspenders.
    --
    -- The recursive call is deliberately NOT in tail position. `return
    -- forever(n + 1)` would be a tail call, which LuaJIT turns into a jump --
    -- the stack never grows, nothing ever overflows, and the test hangs
    -- forever instead of failing. Consuming the result after the call is what
    -- keeps a real frame per level.
    local function forever(n)
      local deeper = forever(n + 1)
      return deeper + 1
    end
    local result, err = safe_call(forever, 1)
    assert.is_nil(result)
    assert.matches("stack overflow", err)
  end)

  it("catches an error thrown from a nested call, not only the top frame", function()
    local function inner()
      error("from the bottom")
    end
    local function outer()
      inner()
    end
    local result, err = safe_call(outer)
    assert.is_nil(result)
    assert.matches("from the bottom", err)
  end)
end)

describe("data.util.safe_call -- argument forwarding", function()
  it("forwards up to three arguments, in order", function()
    local seen
    safe_call(function(a, b, c)
      seen = { a, b, c }
    end, "one", 2, { three = true })
    assert.equals("one", seen[1])
    assert.equals(2, seen[2])
    assert.is_true(seen[3].three)
  end)

  it("forwards exactly three, and a fourth is silently dropped", function()
    -- Pinned as the documented limit: the signature is `(fn, a, b, c)`. The
    -- widest real call is `render(value, mode, opts)`, which is three.
    local seen
    safe_call(function(...)
      seen = { select("#", ...), ... }
    end, 1, 2, 3, 4)
    assert.equals(3, seen[1], "a fourth argument does not reach fn")
  end)

  it("forwards nil arguments as nil rather than as a shorter call", function()
    local seen
    safe_call(function(...)
      seen = select("#", ...)
    end, nil, nil, nil)
    assert.equals(3, seen, "three nils, not zero arguments")
  end)

  it("works for the real shapes both call sites use", function()
    local json_fmt = require("data.format.json")

    local value, derr = safe_call(json_fmt.decode, '{"a":1}')
    assert.is_nil(derr)
    assert.equals(1, value.a)

    local lines, rerr = safe_call(json_fmt.render, value, "compact", {})
    assert.is_nil(rerr)
    assert.same({ '{"a":1}' }, lines)

    local bad, berr = safe_call(json_fmt.decode, "{not json")
    assert.is_nil(bad)
    assert.matches("invalid JSON", berr, "a reported failure, not a thrown one, still arrives")
  end)
end)
