-- Test code: when something here comes back nil -- a require, a filter run
-- -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/filter_failure_spec.lua — data.filter's failure arms and its clause
-- loop, driven against a pickers.refine DOUBLE rather than the real plugin.
--
-- filter_spec.lua does two things this file deliberately does not: it drives
-- the real pickers.refine end to end (so it skips entirely when pickers.nvim
-- is absent), and it covers the three failures that happen BEFORE refine is
-- reached. Everything past `refine.new` -- a version mismatch, a handle that
-- throws, an inactive handle, the multi-round loop -- is third-party surface
-- this module explicitly promises to turn into `on_done(nil, err)` rather than
-- an error raised past an async UI callback. A double is the only way to make
-- those arms happen at all, and it makes them happen on every machine.
--
-- The double replaces `package.loaded["pickers.refine"]` before `filter.run`
-- is called, which is safe here specifically because data.filter requires it
-- INSIDE `run` (`local ok, refine = pcall(require, "pickers.refine")`) rather
-- than binding it to an upvalue at load time.

local filter = require("data.filter")
local json_fmt = require("data.format.json")

--- Run `filter.run` with `refine` standing in for pickers.refine, returning
--- whether the call itself stayed quiet plus whatever reached `on_done`.
---@param refine table
---@param value? any
---@return boolean raised_nothing
---@return string[]|nil out
---@return string|nil err
---@return integer callbacks # how often on_done fired -- exactly once is the contract
local function with_refine(refine, value)
  local had = package.loaded["pickers.refine"]
  package.loaded["pickers.refine"] = refine

  local out, err, calls = nil, nil, 0
  local ok = pcall(
    filter.run,
    json_fmt,
    value or { user = { id = 1 }, level = "error" },
    {},
    function(o, e)
      out, err, calls = o, e, calls + 1
    end
  )

  package.loaded["pickers.refine"] = had
  return ok, out, err, calls
end

--- A refine double whose handle is built from the pieces a test cares about.
---@param handle table
---@return table
local function refine_returning(handle)
  return {
    new = function()
      return handle
    end,
  }
end

describe("data.filter.run -- a pickers.refine that does not behave", function()
  it("reports a refine.new that throws, through on_done", function()
    local ok, out, err, calls = with_refine({
      new = function()
        error("simulated: refine.new signature changed")
      end,
    })
    assert.is_true(ok, "the failure must not raise past filter.run")
    assert.is_nil(out)
    assert.matches("signature changed", err)
    assert.equals(1, calls, "on_done fires exactly once")
  end)

  it("reports a prompt that throws, through on_done", function()
    local ok, out, err, calls = with_refine(refine_returning({
      prompt = function()
        error("simulated: prompt blew up")
      end,
    }))
    assert.is_true(ok)
    assert.is_nil(out)
    assert.matches("prompt blew up", err)
    assert.equals(1, calls)
  end)

  it("reports an apply that throws, through on_done", function()
    local ok, out, err, calls = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function()
        error("simulated: apply blew up")
      end,
    }))
    assert.is_true(ok)
    assert.is_nil(out)
    assert.matches("apply blew up", err)
    assert.equals(1, calls)
  end)

  it("reports an is_active that throws, through on_done", function()
    local ok, out, err = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        error("simulated: is_active blew up")
      end,
    }))
    assert.is_true(ok)
    assert.is_nil(out)
    assert.matches("is_active blew up", err)
  end)

  it("reports a refine module missing its `new` entirely", function()
    -- What a genuinely incompatible pickers.nvim version looks like: the
    -- module loads, the function is not there, and calling nil must not be
    -- the way the user finds out.
    local ok, out, err = with_refine({})
    assert.is_true(ok)
    assert.is_nil(out)
    assert.is_not_nil(err)
  end)

  it("reports an apply that returns something other than a list", function()
    local ok, out, err = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function()
        return "not a list"
      end,
    }))
    assert.is_true(ok)
    -- `ipairs` over a string raises, which the pcall around apply catches.
    assert.is_nil(out)
    assert.is_not_nil(err)
  end)
end)

describe("data.filter.run -- the clause loop's stop condition", function()
  it("treats an inactive handle as 'no filter', reporting nil WITHOUT an error", function()
    -- Cancelled before any clause was added: nothing to do, and explicitly
    -- not an error -- the caller distinguishes this from a failure by the nil
    -- err, and reports nothing at all for it.
    local ok, out, err, calls = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return false
      end,
    }))
    assert.is_true(ok)
    assert.is_nil(out)
    assert.is_nil(err, "a cancelled prompt is not a failure")
    assert.equals(1, calls)
  end)

  it("re-opens the prompt after every round that CHANGED the stack", function()
    -- The loop's actual contract: `on_done` fires on every round, so a
    -- change-less round is the only unambiguous stop signal. Three rounds
    -- here: two that change, one that does not.
    local rounds = 0
    local ok, out, err = with_refine({
      new = function()
        return {
          prompt = function(_self, on_change, on_done)
            rounds = rounds + 1
            if rounds <= 2 then
              on_change()
            end
            on_done()
          end,
          is_active = function()
            return true
          end,
          apply = function(_self, items)
            return items
          end,
        }
      end,
    })
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals(3, rounds, "two changing rounds, then the change-less one that commits")
    assert.is_not_nil(out)
  end)

  it("commits on the FIRST round when nothing changed", function()
    local rounds = 0
    local _, out = with_refine({
      new = function()
        return {
          prompt = function(_self, _on_change, on_done)
            rounds = rounds + 1
            on_done()
          end,
          is_active = function()
            return true
          end,
          apply = function(_self, items)
            return items
          end,
        }
      end,
    })
    assert.equals(1, rounds)
    assert.is_not_nil(out)
  end)

  it("reports an empty result as an empty LIST, not as nil", function()
    -- The caller has to tell "nothing matched" (warn, write nothing) apart
    -- from "cancelled" (silence). An empty table versus nil is the only thing
    -- carrying that difference.
    local _, out, err = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function()
        return {}
      end,
    }))
    assert.same({}, out, "an empty list, which is not nil")
    assert.is_nil(err)
  end)
end)

describe("data.filter.run -- the items handed to pickers.refine", function()
  it("gives every leaf both a path and its rendered line", function()
    local seen
    with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function(_self, items)
        seen = items
        return items
      end,
    }))

    assert.equals(2, #seen, "two leaves: user.id and level")
    local by_path = {}
    for _, item in ipairs(seen) do
      by_path[item.path] = item.line
    end
    assert.equals("level: error", by_path["level"])
    assert.equals("user.id: 1", by_path["user.id"])
  end)

  it("keeps items and rendered lines in the SAME order", function()
    -- `to_refine_items` zips two independent `path_flatten` traversals by
    -- index. If those ever diverged, every clause would match against another
    -- leaf's text -- a wrong result rather than an error.
    local seen
    with_refine(
      refine_returning({
        prompt = function(_self, _on_change, on_done)
          on_done()
        end,
        is_active = function()
          return true
        end,
        apply = function(_self, items)
          seen = items
          return items
        end,
      }),
      { alpha = 1, beta = 2, gamma = 3, delta = 4, epsilon = 5 }
    )

    for _, item in ipairs(seen) do
      assert.matches("^" .. vim.pesc(item.path) .. ": ", item.line, "line belongs to its own path")
    end
  end)

  it("exposes both fields to the clause builder", function()
    local fields
    with_refine({
      new = function(opts)
        fields = opts.fields
        return {
          prompt = function(_self, _on_change, on_done)
            on_done()
          end,
          is_active = function()
            return false
          end,
        }
      end,
    })

    assert.equals("function", type(fields.path), "path clauses")
    assert.equals("function", type(fields.line), "clauses against the rendered text")
    assert.equals("a.b", fields.path({ path = "a.b", line = "a.b: 1" }))
    assert.equals("a.b: 1", fields.line({ path = "a.b", line = "a.b: 1" }))
  end)

  it("returns the surviving items' LINES, not the item tables", function()
    local _, out = with_refine(refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function(_self, items)
        return { items[1] }
      end,
    }))
    assert.equals(1, #out)
    assert.equals("string", type(out[1]), "the caller delivers lines to a buffer")
  end)

  it("threads the configured separator into the flattened paths", function()
    local seen
    local had = package.loaded["pickers.refine"]
    package.loaded["pickers.refine"] = refine_returning({
      prompt = function(_self, _on_change, on_done)
        on_done()
      end,
      is_active = function()
        return true
      end,
      apply = function(_self, items)
        seen = items
        return items
      end,
    })
    filter.run(json_fmt, { user = { id = 1 } }, { sep = "/" }, function() end)
    package.loaded["pickers.refine"] = had

    assert.equals("user/id", seen[1].path)
    assert.equals("user/id: 1", seen[1].line, "the rendered line uses the same separator")
  end)
end)
