---@module 'data.bindings.usrcmds'
--- `:JSON`/`:YAML`/`:XML` -- one compound command per format, each
--- `<action> [args] [flags]` (range-aware: no range = whole buffer or an
--- enclosing fenced block, see `data.scope.resolve`; a range or visual
--- selection = only those lines), built via lib.nvim's composer
--- (`:Verb sub …` + `<Tab>` completion + Markdown docgen).
---
--- Every format verb shares one route factory (`make_routes`) since their
--- core actions are identical apart from `compact` -- JSON and XML support
--- it, YAML doesn't (see `data.format.yaml`'s doc comment: its subset has no
--- single-line flow-style form to collapse into). Two more actions are
--- format-specific and opted into per verb: `ndjson` (JSON only) and `to`
--- (JSON<->YAML conversion, not offered on XML -- see `data.convert`'s doc
--- comment for why).
---
--- `filter` is offered on every format verb, unconditionally, same as
--- `lines`/`keys`/`sort`: it filters the exact same `path_flatten` output
--- those already render, so there is nothing format-specific about it --
--- see `data.filter`.
---
--- `:Data` is a separate, format-auto-detecting verb: the same `pretty`/
--- `lines`/`keys`/`sort`/`filter` subset, but with the format auto-detected
--- instead of named by the verb -- see `data.detect`/`data.run_auto`.
--- `compact`/`ndjson`/`to` stay off it; reaching for one of those already
--- means knowing the format.

local composer = require("lib.nvim.bindings.usercmd.composer")

local M = {}

---@internal
--- Shared indent arg for `pretty`/`sort`.
---@type Lib.UserCmd.Composer.ArgSpec[]
local INDENT_ARG = { { name = "indent", type = "INT", optional = true } }

---@internal
--- Shared path-separator flag for `lines`/`keys`.
---@type Lib.UserCmd.Composer.FlagSpec[]
local SEP_FLAG = { { name = "sep", type = "STRING" } }

---@internal
--- Source/target flags, offered on every route of every verb: where the
--- input comes from (`--reg`) and where the result goes (`--inplace`,
--- `--split`, `--out-reg`). See `data.scope.source`/`data.scope.sink` --
--- including why the register *target* is `--out-reg` and not `--reg`,
--- which the concept used for both.
---
--- `--reg`/`--out-reg` are `optional_value` rather than plain value flags:
--- the bare form means "the configured default register", and that flavor
--- never consumes the next token, so `:JSON pretty 4 --reg` still binds `4`
--- as the indent.
---@type Lib.UserCmd.Composer.FlagSpec[]
local IO_FLAGS = {
  { name = "reg", type = "STRING", optional_value = true },
  { name = "inplace", bool = true },
  { name = "split", bool = true },
  { name = "out-reg", type = "STRING", optional_value = true },
}

---@internal
--- Preview flags, offered on `filter` and nowhere else. `filter` is the one
--- action that loses data, and the one already built to survive an async gap
--- between resolving a scope and writing it -- see `data.preview`'s own doc
--- comment for both halves of that. Declaring them only here means
--- `:JSON pretty --preview` is a "unknown flag" error rather than a flag
--- that quietly does nothing.
---@type Lib.UserCmd.Composer.FlagSpec[]
local PREVIEW_FLAGS = {
  { name = "preview", bool = true },
  { name = "no-preview", bool = true },
}

---@internal
--- `extra` plus the shared IO flags, as a fresh list -- the spec tables
--- above are shared across every route of every verb, so appending to one
--- in place would leak into all of them.
---@param ... Lib.UserCmd.Composer.FlagSpec[]
---@return Lib.UserCmd.Composer.FlagSpec[]
local function with_io(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    vim.list_extend(out, list)
  end
  vim.list_extend(out, IO_FLAGS)
  return out
end

---@internal
--- Read the source/target flags off a dispatched route's context.
---@param ctx Lib.UserCmd.Composer.Ctx
---@return Data.IOFlags
local function io_flags(ctx)
  return {
    reg = ctx.flags.reg,
    inplace = ctx.flags.inplace,
    split = ctx.flags.split,
    out_reg = ctx.flags["out-reg"],
    preview = ctx.flags.preview,
    no_preview = ctx.flags["no-preview"],
  }
end

---@internal
--- Build the route table for one format verb.
---@param fmt string # "json"|"yaml"|"xml", passed straight through to `data.run`
---@param include_compact boolean # see the module doc comment
---@param include_ndjson boolean # JSON only
---@param to_format? string # the one conversion target this verb offers ("yaml" for json, "json" for yaml), nil = none
---@return Lib.UserCmd.Composer.Route[]
local function make_routes(fmt, include_compact, include_ndjson, to_format)
  local data = require("data")

  local routes = {
    {
      path = { "pretty" },
      range = true,
      args = INDENT_ARG,
      flags = with_io(),
      desc = "Pretty-print (default 2-space indent; pretty 4 for 4)",
      run = function(ctx)
        data.run(fmt, "pretty", ctx.raw, { indent = ctx.args.indent }, io_flags(ctx))
      end,
    },
  }

  if include_compact then
    routes[#routes + 1] = {
      path = { "compact" },
      range = true,
      flags = with_io(),
      desc = "Collapse onto one line",
      run = function(ctx)
        data.run(fmt, "compact", ctx.raw, {}, io_flags(ctx))
      end,
    }
  end

  routes[#routes + 1] = {
    path = { "lines" },
    range = true,
    flags = with_io(SEP_FLAG),
    desc = "One 'path: value' per leaf, nested keys dotted (--sep to override)",
    run = function(ctx)
      data.run(fmt, "lines", ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
    end,
  }
  routes[#routes + 1] = {
    path = { "keys" },
    range = true,
    flags = with_io(SEP_FLAG),
    desc = "List only the (dotted) key paths, no values",
    run = function(ctx)
      data.run(fmt, "keys", ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
    end,
  }
  routes[#routes + 1] = {
    path = { "sort" },
    range = true,
    args = INDENT_ARG,
    flags = with_io(),
    desc = "Pretty-print with object keys sorted (see data.format.<fmt> for why this equals 'pretty' today)",
    run = function(ctx)
      data.run(fmt, "sort", ctx.raw, { indent = ctx.args.indent }, io_flags(ctx))
    end,
  }
  routes[#routes + 1] = {
    path = { "filter" },
    range = true,
    flags = with_io(SEP_FLAG, PREVIEW_FLAGS),
    desc = "Interactively filter flattened path/value entries (requires pickers.nvim; --preview to diff before replacing)",
    run = function(ctx)
      data.filter(fmt, ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
    end,
  }

  if include_ndjson then
    routes[#routes + 1] = {
      path = { "ndjson" },
      range = true,
      args = INDENT_ARG,
      flags = with_io(),
      desc = "Pretty-print each line as its own JSON object; malformed lines are left untouched",
      run = function(ctx)
        data.run(fmt, "ndjson", ctx.raw, { indent = ctx.args.indent }, io_flags(ctx))
      end,
    }
  end

  if to_format then
    routes[#routes + 1] = {
      path = { "to" },
      range = true,
      args = { { name = "format", type = "STRING", enum = { to_format } } },
      flags = with_io(),
      desc = ("Convert to %s"):format(to_format),
      run = function(ctx)
        data.convert(fmt, to_format, ctx.raw, {}, io_flags(ctx))
      end,
    }
  end

  return routes
end

---@internal
--- Register one format verb (range-aware; normal + visual).
---@param fmt string # "json"|"yaml"|"xml"
---@param cmd_name string # "JSON"|"YAML"|"XML"
---@param include_compact boolean
---@param include_ndjson boolean
---@param to_format? string
---@return nil
local function make_verb(fmt, cmd_name, include_compact, include_ndjson, to_format)
  local data = require("data")

  composer.verb(cmd_name, {
    desc = ("%s format/filter (range-aware; no range = whole buffer)"):format(cmd_name),
    default = function(ctx)
      data.run(fmt, "pretty", ctx.raw, {})
    end,
    routes = make_routes(fmt, include_compact, include_ndjson, to_format),
  })
end

---@internal
--- Route table for `:Data`: the format-agnostic subset every one of
--- `:JSON`/`:YAML`/`:XML` already supports unconditionally (`pretty`/
--- `lines`/`keys`/`sort`/`filter`) -- `compact`/`ndjson`/`to` stay off this
--- verb since they're already format-specific by nature, which is exactly
--- the case a user reaching for `:Data` already knows the answer to. See
--- `data.detect`/`data.run_auto`.
---@return Lib.UserCmd.Composer.Route[]
local function make_data_routes()
  local data = require("data")

  return {
    {
      path = { "pretty" },
      range = true,
      args = INDENT_ARG,
      flags = with_io(),
      desc = "Pretty-print, format auto-detected (fenced block, register contents, or filetype)",
      run = function(ctx)
        data.run_auto("pretty", ctx.raw, { indent = ctx.args.indent }, io_flags(ctx))
      end,
    },
    {
      path = { "lines" },
      range = true,
      flags = with_io(SEP_FLAG),
      desc = "One 'path: value' per leaf, format auto-detected (--sep to override)",
      run = function(ctx)
        data.run_auto("lines", ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
      end,
    },
    {
      path = { "keys" },
      range = true,
      flags = with_io(SEP_FLAG),
      desc = "Only the (dotted) key paths, format auto-detected",
      run = function(ctx)
        data.run_auto("keys", ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
      end,
    },
    {
      path = { "sort" },
      range = true,
      args = INDENT_ARG,
      flags = with_io(),
      desc = "Pretty-print with object keys sorted, format auto-detected",
      run = function(ctx)
        data.run_auto("sort", ctx.raw, { indent = ctx.args.indent }, io_flags(ctx))
      end,
    },
    {
      path = { "filter" },
      range = true,
      flags = with_io(SEP_FLAG, PREVIEW_FLAGS),
      desc = "Interactively filter flattened path/value entries, format auto-detected (requires pickers.nvim; --preview to diff before replacing)",
      run = function(ctx)
        data.run_auto("filter", ctx.raw, { sep = ctx.flags.sep }, io_flags(ctx))
      end,
    },
  }
end

--- Create the `:JSON`, `:YAML`, `:XML`, and `:Data` verbs.
---@return nil
function M.setup()
  make_verb("json", "JSON", true, true, "yaml")
  make_verb("yaml", "YAML", false, false, "json")
  make_verb("xml", "XML", true, false, nil)

  composer.verb("Data", {
    desc = "Format/filter with json/yaml/xml auto-detected from a fenced block or filetype (range-aware; no range = whole buffer)",
    default = function(ctx)
      require("data").run_auto("pretty", ctx.raw, {})
    end,
    routes = make_data_routes(),
  })
end

return M
