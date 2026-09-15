---@module 'data.bindings.keymaps'
--- No default keymaps: data.nvim's JSON actions are Ex commands
--- (`:JSON pretty`/`compact`/`lines`/`keys`/`sort`), not motions or toggles,
--- so there is no natural single-key binding to ship as a preset the way
--- cascade.nvim or emojis.nvim do. This module exists (`NEW-08`) as the place
--- a `keymaps.preset` would be wired up if one is added later -- see
--- `data.config.DEFAULTS`.

local M = {}

--- Bind the preset keymaps, if `cfg.keymaps.preset` is enabled.
---@param _cfg DataConfig
---@return nil
function M.setup(_cfg)
  -- Reserved: no preset keymaps are defined yet.
end

return M
