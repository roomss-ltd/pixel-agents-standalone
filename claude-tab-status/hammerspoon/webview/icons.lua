-- webview/icons.lua - local inline SVG icons for compact header controls.

local M = {}

local ICONS = {
    ["chevron-up"] = [[<path d="m6 15 6-6 6 6"/>]],
    ["chevron-down"] = [[<path d="m6 9 6 6 6-6"/>]],
    ["minimize-2"] = [[<path d="M4 14h6v6"/><path d="m10 14-7 7"/><path d="M20 10h-6V4"/><path d="m14 10 7-7"/>]],
    ["maximize-2"] = [[<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="M9 21H3v-6"/><path d="m3 21 7-7"/>]],
    ["settings"] = [[<path d="M12 15.5A3.5 3.5 0 1 0 12 8a3.5 3.5 0 0 0 0 7.5Z"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.2a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.2a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3h.1a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.2a1.6 1.6 0 0 0 1 1.5h.1a1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8v.1a1.6 1.6 0 0 0 1.5 1h.2a2 2 0 1 1 0 4h-.2a1.6 1.6 0 0 0-1.5.9Z"/>]],
    ["pin"] = [[<path d="M12 17v5"/><path d="M5 17h14"/><path d="M15 3.1c0 1.1-.9 1.9-2 1.9h-2c-1.1 0-2-.8-2-1.9"/><path d="M7 8h10"/><path d="M9 8v6l-2 3h10l-2-3V8"/>]],
    ["ellipsis"] = [[<circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>]],
    ["coffee"] = [[<path d="M10 2v2"/><path d="M14 2v2"/><path d="M6 2v2"/><path d="M18 8h1a4 4 0 1 1 0 8h-1"/><path d="M4 8h14v7a6 6 0 0 1-6 6H10a6 6 0 0 1-6-6Z"/><path d="M6 8h10"/>]],
}

local function escapeAttribute(value)
    return tostring(value or ""):gsub("&", "&amp;"):gsub("\"", "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

function M.svg(name, className)
    local body = ICONS[name]
    if not body then return "" end
    local classAttr = escapeAttribute(className or "control-icon")
    return '<span class="' .. classAttr .. '" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" focusable="false">' .. body .. "</svg></span>"
end

return M
