-- webview/views/mini.lua - Mini status view fragments.

local M = {}

function M.headerControls(options)
    options = options or {}
    return '<button class="header-icon-button compact-mode-toggle mini-enlarge-toggle" data-action="compact.mode.set" data-mode="peek" type="button" aria-label="Enlarge to peek status" title="Enlarge to peek">' ..
        (options.enlargeIcon or "") ..
        "</button>"
end

return M
