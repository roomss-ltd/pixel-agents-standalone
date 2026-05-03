-- webview/bridge.lua - narrow JS action normalizer for the webview callback path.

local M = {}

local KNOWN_ACTIONS = {
    ["setting.toggle"] = true,
    ["settings.toggle"] = true,
    ["pin.toggle"] = true,
    ["row.focus"] = true,
    ["row.dismiss"] = true,
    ["row.interrupt"] = true,
    ["event.focus"] = true,
    ["event.dismiss"] = true,
    ["older.toggle"] = true,
    ["drag.start"] = true,
    ["drag.move"] = true,
    ["drag.end"] = true,
    ["expand.toggle"] = true,
    ["expand.set"] = true,
    ["peek.hover.set"] = true,
    ["peek.pin.toggle"] = true,
    ["compact.mode.set"] = true,
    ["edit.toggle"] = true,
    ["debug.layout"] = true,
}

function M.normalizeMessage(message, handlers)
    local body = message and (message.body or message)
    if type(body) ~= "table" then return nil end
    if not KNOWN_ACTIONS[body.type] then return nil end
    if body.type == "setting.toggle" then
        local isKnownSettingKey = handlers and handlers.isKnownSettingKey
        if type(isKnownSettingKey) == "function" and not isKnownSettingKey(body.key) then
            return nil
        end
    end
    return body
end

return M
