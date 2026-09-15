---@module 'data.bindings.usrcmds'
--- `:JSON`/`:YAML`/`:XML` -- one compound command per format, each
--- `<action> [args] [flags]` (range-aware: no range = whole buffer or an
--- enclosing fenced block, see `data.scope.resolve`; a range or visual
--- selection = only those lines), built via lib.nvim's composer
--- (`:Verb sub …` + `<Tab>` completion + Markdown docgen).
---
--- All three verbs share one route factory (`make_routes`) since their core
--- actions are identical apart from `compact` -- JSON and XML support it,
--- YAML doesn't (see `data.format.yaml`'s doc comment: its subset has no
--- single-line flow-style form to collapse into). Two more actions are
--- format-specific and opted into per verb: `ndjson` (JSON only) and `to`
--- (JSON<->YAML conversion, not offered on XML -- see `data.convert`'s doc
--- comment for why).

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
      desc = "Pretty-print (default 2-space indent; pretty 4 for 4)",
      run = function(ctx)
        data.run(fmt, "pretty", ctx.raw, { indent = ctx.args.indent })
      end,
    },
  }

  if include_compact then
    routes[#routes + 1] = {
      path = { "compact" },
      range = true,
      desc = "Collapse onto one line",
      run = function(ctx)
        data.run(fmt, "compact", ctx.raw, {})
      end,
    }
  end

  routes[#routes + 1] = {
    path = { "lines" },
    range = true,
    flags = SEP_FLAG,
    desc = "One 'path: value' per leaf, nested keys dotted (--sep to override)",
    run = function(ctx)
      data.run(fmt, "lines", ctx.raw, { sep = ctx.flags.sep })
    end,
  }
  routes[#routes + 1] = {
    path = { "keys" },
    range = true,
    flags = SEP_FLAG,
    desc = "List only the (dotted) key paths, no values",
    run = function(ctx)
      data.run(fmt, "keys", ctx.raw, { sep = ctx.flags.sep })
    end,
  }
  routes[#routes + 1] = {
    path = { "sort" },
    range = true,
    args = INDENT_ARG,
    desc = "Pretty-print with object keys sorted (see data.format.<fmt> for why this equals 'pretty' today)",
    run = function(ctx)
      data.run(fmt, "sort", ctx.raw, { indent = ctx.args.indent })
    end,
  }

  if include_ndjson then
    routes[#routes + 1] = {
      path = { "ndjson" },
      range = true,
      args = INDENT_ARG,
      desc = "Pretty-print each line as its own JSON object; malformed lines are left untouched",
      run = function(ctx)
        data.run(fmt, "ndjson", ctx.raw, { indent = ctx.args.indent })
      end,
    }
  end

  if to_format then
    routes[#routes + 1] = {
      path = { "to" },
      range = true,
      args = { { name = "format", type = "STRING", enum = { to_format } } },
      desc = ("Convert to %s"):format(to_format),
      run = function(ctx)
        data.convert(fmt, to_format, ctx.raw, {})
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

--- Create the `:JSON`, `:YAML`, and `:XML` verbs.
---@return nil
function M.setup()
  make_verb("json", "JSON", true, true, "yaml")
  make_verb("yaml", "YAML", false, false, "json")
  make_verb("xml", "XML", true, false, nil)
end

return M
