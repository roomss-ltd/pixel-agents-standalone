-- webview/views/detail.lua - Full detail status view fragments.

local M = {}

function M.headerControls(options)
    options = options or {}
    return '<button class="header-icon-button collapse-toggle" data-action="expand.toggle" type="button" aria-label="Collapse widget" title="Collapse">' ..
        (options.collapseIcon or "") ..
        "</button>"
end

return M
