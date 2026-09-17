-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/malformed_spec.lua — what every format does with input that is empty,
-- truncated, byte-order-marked, CRLF-terminated, pathologically deep, or
-- otherwise not the document the user thought it was.
--
-- The existing format_*_spec.lua files cover well-formed input plus one
-- malformed example per format. This file is the other side: the failure
-- surface a support log pasted out of a ticket tool actually has. The rule
-- throughout is that a bad document must be *reported*, with the scope left
-- exactly as it was -- reporting nothing and silently changing the scope is
-- the one outcome nothing else in the suite would have caught.

local json_fmt = require("data.format.json")
local yaml_fmt = require("data.format.yaml")
local xml_fmt = require("data.format.xml")

--- A UTF-8 byte-order mark, built from bytes rather than written literally.
--- Whether a raw BOM in a source file survives to mean a BOM depends on every
--- layer that touched the file, and getting that wrong produces a test that
--- passes for the wrong reason -- same discipline as oneline_spec.lua's `BS`.
local BOM = string.char(239, 187, 191)

--- Capture every `vim.notify` call made during `fn()`, pumping the event loop
--- briefly afterwards so a `vim.schedule`-deferred notify (every `data.init`
--- report is scheduled -- see its own doc comment) has actually run.
---@param fn fun()
---@return string[]
local function capture_notify(fn)
  local msgs = {}
  local orig = vim.notify
  --- Test double: restored below, including when `fn()` errors.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    msgs[#msgs + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.wait(30)
  vim.notify = orig
  if not ok then
    error(err, 0)
  end
  return msgs
end

---@param msgs string[]
---@param needle string
---@return boolean
local function said(msgs, needle)
  for _, m in ipairs(msgs) do
    if m:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("data.format.json.decode -- malformed input reports rather than throws", function()
  local cases = {
    { name = "an empty string", text = "" },
    { name = "whitespace only", text = "   \n  " },
    { name = "a truncated object", text = '{"a":' },
    { name = "a truncated array", text = "[1,2" },
    { name = "a trailing comma in an object", text = '{"a":1,}' },
    { name = "a trailing comma in an array", text = "[1,2,]" },
    { name = "single-quoted keys", text = "{'a':1}" },
    { name = "a trailing // comment", text = '{"a":1} // note' },
    { name = "a leading UTF-8 BOM", text = BOM .. '{"a":1}' },
  }

  for _, case in ipairs(cases) do
    it(("%s is reported, not thrown"):format(case.name), function()
      local value, err = json_fmt.decode(case.text)
      assert.is_nil(value)
      assert.is_not_nil(err, "a malformed document must come back as (nil, err)")
      assert.matches("invalid JSON", err)
    end)
  end

  it("tolerates CRLF inside an otherwise well-formed document", function()
    local value, err = json_fmt.decode('{"a":\r\n1}')
    assert.is_nil(err)
    assert.equals(1, value.a)
  end)

  it("keeps the LAST of two duplicate keys, silently -- Lua has no other option", function()
    local value = json_fmt.decode('{"a":1,"a":2}')
    assert.equals(2, value.a)
  end)
end)

describe("data.format.json -- the truthy null trap", function()
  -- `vim.json.decode("null")` returns a *userdata* sentinel, not Lua nil, so a
  -- `if not parsed then` guard never fires for it -- a mistake that has
  -- produced real bugs in sibling plugins. data.nvim is safe because every
  -- call site branches on the returned `err` instead, and `lib.nvim.json`
  -- normalizes the sentinel into `lib.lua.null`. Both halves are pinned here:
  -- if either changes, a top-level `null` starts being treated as a failure.

  it("a top-level null decodes to a TRUTHY sentinel with no error", function()
    local value, err = json_fmt.decode("null")
    assert.is_nil(err, "`null` is a valid JSON document, not a decode failure")
    assert.is_truthy(value, "the sentinel is truthy -- `if not value` would be wrong here")
    assert.is_true(require("lib.lua.null").is_null(value), "normalized to lib.lua.null")
  end)

  it("renders a top-level null back as the literal null", function()
    local value = json_fmt.decode("null")
    assert.same({ "null" }, json_fmt.render(value, "pretty"))
    assert.same({ "null" }, json_fmt.render(value, "compact"))
  end)

  it("a nested null survives decode -> compact -> decode as null", function()
    local value = json_fmt.decode('{"a":null,"b":1}')
    local compact = json_fmt.render(value, "compact")
    assert.same({ '{"a":null,"b":1}' }, compact)
  end)

  it(":JSON pretty on a lone `null` rewrites it rather than reporting a failure", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "null" })

    local msgs = capture_notify(function()
      vim.cmd("JSON pretty")
    end)

    assert.same({ "null" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.is_false(said(msgs, "decode failed"), "a valid `null` document is not a decode failure")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("data.format.json -- non-standard numbers the decoder accepts", function()
  -- Asymmetry worth knowing about rather than discovering in a ticket: the
  -- decoder is more permissive than the encoder, so a document can be read
  -- and then refuse to be written back. It is reported cleanly either way,
  -- which is the part that matters.

  it("accepts NaN on the way in", function()
    local value, err = json_fmt.decode("NaN")
    assert.is_nil(err)
    assert.is_true(value ~= value, "NaN is the one value not equal to itself")
  end)

  it("accepts -Infinity on the way in", function()
    local value, err = json_fmt.decode("-Infinity")
    assert.is_nil(err)
    assert.equals(-math.huge, value)
  end)

  it("then refuses to encode NaN, with a named error instead of invalid JSON", function()
    local lines, err = json_fmt.render((json_fmt.decode("NaN")), "compact")
    assert.is_nil(lines)
    assert.matches("NaN", err)
  end)

  it(":JSON compact on NaN reports a render failure and leaves the scope alone", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "NaN" })

    local msgs = capture_notify(function()
      vim.cmd("JSON compact")
    end)

    assert.same({ "NaN" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.is_true(
      said(msgs, "render failed"),
      "the failure is named as a render one, not a decode"
    )
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("data.format.json -- pathologically deep input", function()
  -- `data.util.safe_call` exists as the belt to the decoders' own
  -- recursion-depth suspenders (see its doc comment). This is the suspenders
  -- half: the guard fires as a reported error, so `safe_call` never has to
  -- catch a real stack overflow.

  it("accepts nesting right up to the guard's limit", function()
    local text = string.rep('{"a":', 64) .. "1" .. string.rep("}", 64)
    local value, err = json_fmt.decode(text)
    assert.is_nil(err, "64 levels is inside the guard")
    assert.is_not_nil(value)
  end)

  it("reports one level past it instead of overflowing the stack", function()
    local text = string.rep('{"a":', 65) .. "1" .. string.rep("}", 65)
    local value, err = json_fmt.decode(text)
    assert.is_nil(value)
    assert.matches("max nesting depth", err)
    assert.matches("64", err, "the effective limit is the null-normalizer's 64, not the parser's")
  end)

  it("stays a clean report all the way out through :JSON", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    local text = string.rep('{"a":', 400) .. "1" .. string.rep("}", 400)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { text })

    local msgs = capture_notify(function()
      vim.cmd("JSON pretty")
    end)

    assert.same({ text }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.is_true(said(msgs, "max nesting depth"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("data.format.json -- values the encoder cannot represent", function()
  it("reports an unencodable Lua value rather than emitting broken JSON", function()
    local lines, err = json_fmt.render({ a = print }, "compact")
    assert.is_nil(lines)
    assert.matches("function", err)
  end)

  it("clamps a non-numeric indent to the default instead of throwing", function()
    -- The formatter's own clamp, distinct from `data.init`'s `resolve_indent`
    -- (which additionally warns). A direct API caller reaches only this one.
    assert.same({ "{", '  "a": 1', "}" }, json_fmt.render({ a = 1 }, "pretty", { indent = "wide" }))
    assert.same({ "{", '  "a": 1', "}" }, json_fmt.render({ a = 1 }, "pretty", { indent = 0 }))
    assert.same({ "{", '  "a": 1', "}" }, json_fmt.render({ a = 1 }, "pretty", { indent = -3 }))
  end)
end)

describe("the `lines`/`keys` shape for a document with no keys at all", function()
  -- Documented quirk rather than a defect, pinned because it looks like one:
  -- `path_flatten` treats a scalar root as a single leaf with an empty path,
  -- so the rendered line has nothing to the left of the separator.

  it("a scalar root renders as a path-less entry", function()
    assert.same({ ": hello" }, json_fmt.render("hello", "lines"))
    assert.same({ ": 42" }, json_fmt.render(42, "lines"))
  end)

  it("a null root renders as a path-less null", function()
    assert.same({ ": null" }, json_fmt.render((json_fmt.decode("null")), "lines"))
  end)

  it("keys of a scalar root is a single empty line", function()
    assert.same({ "" }, json_fmt.render("hello", "keys"))
  end)

  it("a boolean leaf renders via tostring, not as a quoted string", function()
    assert.same({ "f: false", "t: true" }, json_fmt.render({ t = true, f = false }, "lines"))
  end)
end)

describe("data.format.yaml -- malformed and degenerate input", function()
  it("decodes an empty document to an empty table, not an error", function()
    local value, err = yaml_fmt.decode("")
    assert.is_nil(err)
    assert.same({}, value)
  end)

  it("decodes a whitespace-only document to an empty table too", function()
    local value, err = yaml_fmt.decode("   \n  \n")
    assert.is_nil(err)
    assert.same({}, value)
  end)

  it("renders an empty document as ZERO lines", function()
    -- The mechanism behind the in-place deletion pinned further down: an
    -- empty document has no representation, so `render` returns an empty
    -- list rather than a blank line.
    assert.same({}, yaml_fmt.render({}, "pretty"))
  end)

  it("tolerates CRLF", function()
    local value, err = yaml_fmt.decode("a: 1\r\nb: 2\r\n")
    assert.is_nil(err)
    assert.equals(1, value.a)
    assert.equals(2, value.b)
  end)

  it("reports a scalar it cannot encode", function()
    local lines, err = yaml_fmt.render(nil, "pretty")
    assert.is_nil(lines)
    assert.is_not_nil(err)
  end)

  it("renders numbers and booleans in `lines` via tostring", function()
    assert.same({ "b: true", "n: 1.5" }, yaml_fmt.render({ n = 1.5, b = true }, "lines"))
  end)

  it("BUG: a tab-indented child is silently promoted to a top-level key", function()
    -- The YAML spec forbids tabs for indentation, so refusing the document
    -- would be right. What happens instead is worse than refusing: the
    -- parent key `a` disappears entirely and its child is re-parented to the
    -- document root, with no error -- silent data loss on a document a user
    -- would reasonably expect to be rejected. The defect is in
    -- `lib.lua.yaml.simple_parse`, not in this repo; pinned here because
    -- :YAML is where a user meets it.
    local value, err = yaml_fmt.decode("a:\n\tb: 1\n")
    assert.is_nil(err, "BUG: reported as a perfectly good parse")
    assert.same({ b = 1 }, value, "BUG: `a` is gone and `b` was promoted to the root")
  end)
end)

describe("data.format.xml -- malformed and degenerate input", function()
  local cases = {
    { name = "an empty string", text = "", needle = "root element" },
    { name = "whitespace only", text = "  \n ", needle = "root element" },
    { name = "a leading UTF-8 BOM", text = BOM .. "<a/>", needle = "root element" },
    { name = "an unterminated element", text = "<a><b>", needle = "unterminated" },
    { name = "a mismatched closing tag", text = "<a><b></c></a>", needle = "" },
  }

  for _, case in ipairs(cases) do
    it(("%s is reported, not thrown"):format(case.name), function()
      local value, err = xml_fmt.decode(case.text)
      assert.is_nil(value)
      assert.is_not_nil(err)
      if case.needle ~= "" then
        assert.matches(case.needle, err)
      end
    end)
  end

  it("skips an XML declaration and decodes the root that follows it", function()
    local value, err = xml_fmt.decode('<?xml version="1.0"?><a/>')
    assert.is_nil(err)
    assert.equals("a", value.tag)
  end)

  it("tolerates CRLF between elements", function()
    local value, err = xml_fmt.decode("<a>\r\n<b>x</b>\r\n</a>")
    assert.is_nil(err)
    assert.equals("b", value.children[1].tag)
  end)

  it("reports a value that is not an element table at all", function()
    local lines, err = xml_fmt.render({}, "pretty")
    assert.is_nil(lines)
    assert.matches("tag", err)
  end)

  it("renders a numeric text node via tostring", function()
    local value = { tag = "a", attrs = {}, children = { 5 } }
    assert.same({ "attrs: {}", "children.1: 5", "tag: a" }, xml_fmt.render(value, "lines"))
  end)
end)

describe("BUG: a UTF-8 BOM is never stripped, and only YAML fails quietly", function()
  -- `data.scope.register.read` already normalizes CRLF away, with the
  -- rationale that it "is an artifact of where the text came from, not
  -- content" and that the register scope exists for "I copied this out of a
  -- ticket tool" on Windows. A BOM is the same artifact from the same source,
  -- and nothing strips it -- not the register read, not any decoder.
  --
  -- For JSON and XML the consequence is only a confusing message (an error
  -- about character 1 / position 1, where the user sees a perfectly good
  -- brace). For YAML it is a wrong result reported as a success: the BOM
  -- becomes part of the first key's NAME.

  it("json: reports a failure pointing at character 1", function()
    local value, err = json_fmt.decode(BOM .. '{"a":1}')
    assert.is_nil(value)
    assert.matches("character 1", err)
  end)

  it("xml: reports a missing root element at position 1", function()
    local value, err = xml_fmt.decode(BOM .. "<a/>")
    assert.is_nil(value)
    assert.matches("position 1", err)
  end)

  it("BUG: yaml glues the BOM onto the first key and reports success", function()
    local value, err = yaml_fmt.decode(BOM .. "a: 1")
    assert.is_nil(err, "BUG: no error at all")
    assert.is_nil(value.a, "BUG: the key the user wrote is not there")
    assert.equals(1, value[BOM .. "a"], "BUG: the BOM is part of the key name")
  end)

  it("BUG: so :YAML lines emits a corrupt key path with no warning", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { BOM .. "a: 1" })

    local msgs = capture_notify(function()
      vim.cmd("YAML lines")
    end)

    assert.same({ BOM .. "a: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.is_false(said(msgs, "decode failed"), "BUG: nothing is reported")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("BUG: and data.detect cannot classify BOM'd text for :Data --reg", function()
    -- Same root cause reaching a different feature: `from_text` looks at the
    -- first non-blank BYTE, and the BOM's bytes are not blank.
    local detect = require("data.detect")
    assert.is_nil(detect.from_text(BOM .. '{"a":1}'), "BUG: would be json without the BOM")
    assert.is_nil(detect.from_text(BOM .. "a: 1"), "BUG: would be yaml without the BOM")
    assert.is_nil(detect.from_text(BOM .. "<a/>"), "BUG: would be xml without the BOM")
    assert.equals("json", detect.from_text('{"a":1}'), "control: the same text without a BOM")
  end)
end)

describe("BUG: :YAML over a blank scope silently DELETES it", function()
  -- The one outcome this whole file exists to catch: a document that was not
  -- what the user thought, changing the buffer, reporting nothing.
  --
  -- Chain: whitespace decodes to `{}` (no error), `render` turns `{}` into
  -- ZERO lines, and `data.scope.sink`'s in-place write replaces the span with
  -- those zero lines -- which deletes it. JSON and XML refuse the very same
  -- input with a decode error and leave the scope alone, so this is a
  -- per-format inconsistency as well as a data-loss path.

  local bufnr

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("BUG: a blank line inside a selection is removed, without a word", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep me", "   ", "keep me too" })

    local msgs = capture_notify(function()
      vim.cmd("2YAML pretty")
    end)

    assert.same(
      { "keep me", "keep me too" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      "BUG: the selected line is gone, not reformatted"
    )
    assert.is_false(said(msgs, "decode failed"), "BUG: and nothing was reported")
  end)

  it("BUG: a multi-line blank selection is removed wholesale", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "  ", "\t", "  ", "b" })

    capture_notify(function()
      vim.cmd("2,4YAML pretty")
    end)

    assert.same({ "a", "b" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "BUG: three lines")
  end)

  it("control: :JSON refuses the identical scope and leaves it intact", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep me", "   ", "keep me too" })

    local msgs = capture_notify(function()
      vim.cmd("2JSON pretty")
    end)

    assert.same(
      { "keep me", "   ", "keep me too" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.is_true(said(msgs, "decode failed"), "JSON gets this right")
  end)

  it("control: :XML refuses it too", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep me", "   ", "keep me too" })

    local msgs = capture_notify(function()
      vim.cmd("2XML pretty")
    end)

    assert.same(
      { "keep me", "   ", "keep me too" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.is_true(said(msgs, "decode failed"))
  end)
end)

describe("a failed write leaves the scope byte-identical", function()
  -- data.nvim never touches the filesystem, so it has no half-written file to
  -- roll back. The equivalent property is this one: whatever goes wrong, the
  -- scope is either fully replaced or not touched at all -- there is no
  -- partial write. The three ways a write can fail are each driven directly.

  it("an unencodable value never reaches the buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "original" })
    local sink = require("data.scope.sink")
    local source = { kind = "buffer", lines = { "original" }, bufnr = bufnr, s0 = 0, e0 = 0 }

    local ok, problem = sink.write({ kind = "inplace" }, source, { "has\nnewline" })

    assert.is_false(ok)
    assert.matches("could not write the result", problem.msg)
    assert.same({ "original" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("a vanished buffer is named, not written to", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    local sink = require("data.scope.sink")
    local source = { kind = "buffer", lines = { "x" }, bufnr = bufnr, s0 = 0, e0 = 0 }

    local ok, problem = sink.write({ kind = "inplace" }, source, { "y" })

    assert.is_false(ok)
    assert.matches("no longer valid", problem.msg)
  end)

  it("a locked buffer is named, not written to", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "original" })
    vim.bo[bufnr].modifiable = false
    local sink = require("data.scope.sink")
    local source = { kind = "buffer", lines = { "original" }, bufnr = bufnr, s0 = 0, e0 = 0 }

    local ok, problem = sink.write({ kind = "inplace" }, source, { "y" })
    vim.bo[bufnr].modifiable = true

    assert.is_false(ok)
    assert.matches("modifiable", problem.msg)
    assert.same({ "original" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
