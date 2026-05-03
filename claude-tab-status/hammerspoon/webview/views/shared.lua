-- webview/views/shared.lua - Shared HTML primitives for the status webview.

local M = {}

function M.iconTemplate(id, icon)
    return [[<div class="icon-template" id="]] .. id .. [[" aria-hidden="true">]] .. (icon or "") .. [[</div>]]
end

return M
