-- claude-status-webview.lua - production hs.webview renderer scaffold.
-- Reads the same /tmp/claude-tab-status contract as claude-status.lua.

local M = {}

local function bootstrapHelperPackagePath()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then source = source:sub(2) end

    local sourcePath = source
    if hs and hs.fs and hs.fs.symlinkAttributes then
        local attrs = hs.fs.symlinkAttributes(sourcePath)
        if attrs and attrs.target then sourcePath = attrs.target end
    end

    local helperRoot = sourcePath:match("^(.*)/[^/]+$")
    if helperRoot then
        package.path = helperRoot .. "/?.lua;" .. helperRoot .. "/?/init.lua;" .. package.path
    end
    return helperRoot or "."
end

local SOURCE_DIR = bootstrapHelperPackagePath()

local webviewHtml = require("webview.html")
local webviewStyles = require("webview.styles")
local webviewState = require("webview.state")
local webviewBridge = require("webview.bridge")
local webviewPlacement = require("webview.placement")

local STATUS_DIR = "/tmp/claude-tab-status"
local STALE_THRESHOLD = 120
local DENYLIST_PATH = os.getenv("HOME") .. "/.hammerspoon/claude-status-denylist.json"
local DENYLIST_TTL = 30 * 24 * 60 * 60
local SETTINGS_KEY = "claudeStatus.settings"
local COMPACT_MODE_KEY = "claudeStatus.compactMode"
local DEBUG_KEY = "claudeStatus.debug"
local DEBUG_LOG_PATH = "/tmp/claude-status-webview-debug.log"
local HOVER_LOG_PATH = "/tmp/claude-status-webview-hover.log"
local FOCUS_LOG_PATH = "/tmp/claude-status-webview-focus.log"
local TERMINAL_APP = "Ghostty"
local CALLBACK_NAME = "claudeStatus"
local BRIDGE_SCHEME = "claude-status"
local DETAIL_VIEW_ENABLED = false
local FLASH_DURATION = 1.5
local COMPLETION_HIGHLIGHT_DURATION = 10.0
local EVENT_TTL = 15.0
local MAX_EVENT_ROWS = 3

-- Sounds stay owned by Hammerspoon so the webview renderer keeps the same
-- Mac-only notification path as the canvas fallback.
local SOUND_ENABLED = true
local SOUND_DONE = { file = SOURCE_DIR .. "/sounds/Glass.wav" }
local SOUND_WAITING = { name = "Ping" }
local SOUND_COOLDOWN = 0.75
local WAITING_SOUND_REMINDER_INTERVAL = 30.0

local WIDTH = 300
local PILL_WIDTH = 120
local HEADER_HEIGHT = 30
local HEIGHT = 380
local WINDOW_PADDING = 20
local POPOVER_GAP = 8
local SETTINGS_WIDTH = 220
local SETTINGS_HEADER_HEIGHT = 30
local SETTINGS_ROW_HEIGHT = 28
local SETTINGS_ROW_GAP = 6
local SETTINGS_VERTICAL_PADDING = 16
local SETTINGS_BORDER_SAFETY = 4
local EVENT_POPOVER_SIZE = { width = 244, height = 108 }
local EVENT_POPOVER_GAP = 5

local webview = nil
local settingsWebview = nil
local eventWebview = nil
local pathwatcher = nil
local hotkey = nil
local hotkeyReset = nil
local updateTimer = nil
local dragTap = nil
local interactionTap = nil
local visible = true
local expanded = false
local pinned = false
local settingsOpen = false
local viewMode = "peek"
local peekHover = false
local peekPinned = false
local olderFinishedExpanded = false
local placementState = { kind = "top-right" }
local dragState = nil
local pointerState = nil
local hoverCollapseSuppressedUntil = 0
local CLICK_DRAG_THRESHOLD = 8
local sessions = {}
local counts = { active = 0, waiting = 0, done = 0 }
local refreshWebview = nil
local dismissSession = nil
local dismissEvent = nil
local focusSession = nil
local startDrag = nil
local moveDrag = nil
local endDrag = nil
local flashState = {}
local prevActivities = {}
local eventQueue = {}
local nextEventId = 1
local lastStatusSoundAt = {}
local currentFrameSize = { width = PILL_WIDTH, height = HEADER_HEIGHT }

local DEFAULT_SETTINGS = {
    soundsEnabled = true,
    waitingReminderSound = true,
    waitingPulse = true,
    completionFlash = true,
    processingNeon = true,
    notificationsEnabled = true,
}

local SETTINGS_ITEMS = {
    { key = "soundsEnabled", label = "Sounds" },
    { key = "waitingReminderSound", label = "Waiting reminders" },
    { key = "waitingPulse", label = "Waiting pulse" },
    { key = "completionFlash", label = "Finish flash" },
    { key = "processingNeon", label = "Processing neon" },
    { key = "notificationsEnabled", label = "Show notifications" },
}

local settings = DEFAULT_SETTINGS

local function settingsSize()
    return {
        width = SETTINGS_WIDTH,
        height = SETTINGS_HEADER_HEIGHT
            + SETTINGS_VERTICAL_PADDING
            + (#SETTINGS_ITEMS * SETTINGS_ROW_HEIGHT)
            + (math.max(#SETTINGS_ITEMS - 1, 0) * SETTINGS_ROW_GAP)
            + SETTINGS_BORDER_SAFETY,
    }
end

local function debugEnabled()
    if not (hs and hs.settings) then return false end
    local value = hs.settings.get(DEBUG_KEY)
    return value == true or value == "true" or value == 1 or value == "1"
end

local function debugLog(message)
    if debugEnabled() then
        hs.printf("[claude-status-webview] %s", tostring(message))
        local f = io.open(DEBUG_LOG_PATH, "a")
        if f then
            f:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [claude-status-webview] " .. tostring(message) .. "\n")
            f:close()
        end
    end
end

local function focusLog(message)
    local f = io.open(FOCUS_LOG_PATH, "a")
    if f then
        f:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [focus] " .. tostring(message) .. "\n")
        f:close()
    end
end

local function hoverLog(message)
    local f = io.open(HOVER_LOG_PATH, "a")
    if f then
        f:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. " [hover] " .. tostring(message) .. "\n")
        f:close()
    end
end

local function defaultSettings()
    local copy = {}
    for k, v in pairs(DEFAULT_SETTINGS) do copy[k] = v end
    return copy
end

local function loadSettings()
    settings = defaultSettings()
    local saved = hs.settings.get(SETTINGS_KEY)
    if type(saved) == "table" then
        for k, v in pairs(saved) do
            if settings[k] ~= nil and type(v) == "boolean" then
                settings[k] = v
            end
        end
    end
end

local function saveSettings()
    hs.settings.set(SETTINGS_KEY, settings)
end

local function loadCompactMode()
    local saved = hs.settings.get(COMPACT_MODE_KEY)
    if saved == "compact" or saved == "peek" then
        viewMode = saved
    else
        viewMode = "peek"
    end
end

local function saveCompactMode()
    hs.settings.set(COMPACT_MODE_KEY, viewMode)
end

local function screenFrame()
    local f = hs.screen.mainScreen():frame()
    return { x = f.x, y = f.y, w = f.w, h = f.h }
end

local function frameForSize(size)
    size = size or currentFrameSize
    return webviewPlacement.frameForWidget(screenFrame(), size, placementState, WINDOW_PADDING)
end

local function defaultFrame()
    return frameForSize(currentFrameSize)
end

local function canOpenDetailView()
    return DETAIL_VIEW_ENABLED == true
end

local function isKnownSettingKey(key)
    for _, item in ipairs(SETTINGS_ITEMS) do
        if item.key == key then return true end
    end
    return false
end

local function handleBridgeMessage(message)
    local body = webviewBridge.normalizeMessage(message, {
        isKnownSettingKey = isKnownSettingKey,
    })
    if type(body) ~= "table" then
        debugLog("bridge ignored")
        return
    end
    debugLog("bridge action=" .. tostring(body.type))
    if body.type == "setting.toggle" then
        if not isKnownSettingKey(body.key) then return end
        settings[body.key] = not settings[body.key]
        if body.key == "notificationsEnabled" and settings.notificationsEnabled == false then
            eventQueue = {}
            if eventWebview then eventWebview:hide() end
        end
        saveSettings()
        if refreshWebview then refreshWebview() end
    elseif body.type == "settings.toggle" then
        peekHover = false
        settingsOpen = not settingsOpen
        if refreshWebview then refreshWebview() end
    elseif body.type == "pin.toggle" then
        if not canOpenDetailView() then
            debugLog("ignored dormant detail pin toggle")
            return
        end
        peekHover = false
        pinned = not pinned
        expanded = pinned
        if not expanded then settingsOpen = false end
        if refreshWebview then refreshWebview() end
    elseif body.type == "older.toggle" then
        if expanded or viewMode == "peek" then
            olderFinishedExpanded = not olderFinishedExpanded
            if viewMode == "peek" then
                peekHover = true
            else
                peekHover = false
            end
            if refreshWebview then refreshWebview() end
        end
    elseif body.type == "expand.toggle" then
        if not canOpenDetailView() then
            debugLog("ignored dormant detail expand toggle")
            return
        end
        if not pinned then
            peekHover = false
            expanded = not expanded
            if not expanded then settingsOpen = false end
            settingsOpen = settingsOpen and expanded
            if refreshWebview then refreshWebview() end
        end
    elseif body.type == "expand.set" then
        if body.expanded == true and not canOpenDetailView() then
            debugLog("ignored dormant detail expand set")
            return
        end
        if not pinned then
            peekHover = false
            if (viewMode == "compact" or viewMode == "peek") and body.expanded == true then
                debugLog("ignored compact/peek hover expand")
                return
            end
            if body.expanded ~= true and hs.timer.secondsSinceEpoch() < hoverCollapseSuppressedUntil then
                debugLog("ignored immediate hover collapse after native expand")
                return
            end
            if settingsOpen and body.expanded ~= true then return end
            expanded = body.expanded == true
            if not expanded then settingsOpen = false end
            settingsOpen = settingsOpen and expanded
            if refreshWebview then refreshWebview() end
        end
    elseif body.type == "peek.hover.set" then
        if expanded or pinned or peekPinned then
            peekHover = false
        else
            local nextPeekHover = body.hovering == true
            if peekHover ~= nextPeekHover then
                peekHover = nextPeekHover
                if refreshWebview then refreshWebview() end
            end
            return
        end
        if refreshWebview then refreshWebview() end
    elseif body.type == "peek.pin.toggle" then
        debugLog("peek pin toggle before pinned=" .. tostring(peekPinned) .. " hover=" .. tostring(peekHover) .. " expanded=" .. tostring(expanded) .. " viewMode=" .. tostring(viewMode))
        if not expanded and viewMode == "peek" then
            peekPinned = not peekPinned
            peekHover = peekPinned
            debugLog("peek pin toggle after pinned=" .. tostring(peekPinned) .. " hover=" .. tostring(peekHover))
            if refreshWebview then refreshWebview() end
        else
            debugLog("peek pin toggle ignored")
        end
    elseif body.type == "compact.mode.set" then
        if body.mode == "peek" or body.mode == "compact" then
            viewMode = body.mode
            expanded = false
            peekHover = false
            peekPinned = false
            settingsOpen = false
            saveCompactMode()
            if refreshWebview then refreshWebview() end
        end
    elseif body.type == "debug.layout" then
        debugLog("layout " .. hs.inspect(body.layout))
    elseif body.type == "row.dismiss" then
        dismissSession(body._zj_session, body.pane_id)
    elseif body.type == "row.focus" then
        focusSession(body._zj_session, body.pane_id, body.tab_num)
    elseif body.type == "event.focus" then
        focusSession(body._zj_session, body.pane_id, body.tab_num)
        dismissEvent(body.id)
    elseif body.type == "event.dismiss" then
        dismissEvent(body.id)
    elseif body.type == "drag.start" then
        startDrag(body.x, body.y)
    elseif body.type == "drag.move" then
        moveDrag(body.dx, body.dy)
    elseif body.type == "drag.end" then
        endDrag()
    end
end

local function urlDecode(value)
    if type(value) ~= "string" then return nil end
    return (value:gsub("+", " "):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function findRequestUrl(value, depth)
    if depth > 4 then return nil end
    if type(value) == "string" then
        if value:match("^%a[%w+.-]*://") then return value end
        return nil
    end
    if type(value) ~= "table" then return nil end

    for _, key in ipairs({ "url", "URL", "absoluteString" }) do
        local candidate = findRequestUrl(value[key], depth + 1)
        if candidate then return candidate end
    end

    for _, key in ipairs({ "request", "sourceFrame", "targetFrame", "response" }) do
        local candidate = findRequestUrl(value[key], depth + 1)
        if candidate then return candidate end
    end

    return nil
end

local function requestUrlFromPolicyRequest(request)
    return findRequestUrl(request, 0)
end

local function bridgePayloadFromUrl(url)
    if type(url) ~= "string" then return nil end
    local escapedScheme = BRIDGE_SCHEME:gsub("%-", "%%-")
    return url:match("^" .. escapedScheme .. "://action%?payload=(.+)$")
end

local function handlePolicyAction(action, _, request)
    if action ~= "navigationAction" and action ~= "newWindow" then return true end
    local url = requestUrlFromPolicyRequest(request)
    debugLog("policy action=" .. tostring(action) .. " url=" .. tostring(url))
    local payload = bridgePayloadFromUrl(url)
    if not payload then
        debugLog("policy no bridge payload")
        return true
    end

    local ok, decoded = pcall(urlDecode, payload)
    if not ok or type(decoded) ~= "string" then
        debugLog("policy decode failed")
        return false
    end

    local jsonOk, message = pcall(hs.json.decode, decoded)
    if jsonOk then
        handleBridgeMessage(message)
    else
        debugLog("policy json failed")
    end
    return false
end

local function loadDenylist()
    local now = os.time()
    local deny = {}
    local data = hs.json.read(DENYLIST_PATH)
    if type(data) == "table" then
        for key, ts in pairs(data) do
            if type(ts) == "number" and (now - ts) < DENYLIST_TTL then
                deny[key] = ts
            end
        end
    end
    return deny
end

local function saveDenylist(deny)
    local f = io.open(DENYLIST_PATH, "w")
    if f then f:write(hs.json.encode(deny)); f:close() end
end

local function denylistKey(zj_session, pane_id)
    return tostring(zj_session) .. ":" .. tostring(pane_id)
end

local function addToDenylist(zj_session, pane_id)
    local deny = loadDenylist()
    deny[denylistKey(zj_session, pane_id)] = os.time()
    saveDenylist(deny)
end

local function recountSessions(rows)
    local nextCounts = { active = 0, waiting = 0, done = 0 }
    for _, row in ipairs(rows) do
        local a = row.activity
        if a == "Thinking" or a == "Tool" or a == "Init" then
            nextCounts.active = nextCounts.active + 1
        elseif a == "Waiting" then
            nextCounts.waiting = nextCounts.waiting + 1
        elseif a == "Done" or a == "Idle" then
            nextCounts.done = nextCounts.done + 1
        end
    end
    return nextCounts
end

function dismissSession(zj_session, pane_id)
    pane_id = tonumber(pane_id)
    if not zj_session or not pane_id then return end

    addToDenylist(zj_session, pane_id)

    local payload = string.format('{"hook_event":"Dismiss","pane_id":%d}', pane_id)
    local cmd = string.format('zellij -s %q pipe --name "claude-tab-status" -- %q', zj_session, payload)
    hs.execute(cmd, true)

    local path = STATUS_DIR .. "/" .. zj_session .. ".json"
    local data = hs.json.read(path)
    if data and data.sessions then
        local kept = {}
        for _, existing in ipairs(data.sessions) do
            if existing.pane_id ~= pane_id then
                table.insert(kept, existing)
            end
        end
        data.sessions = kept
        data.counts = recountSessions(kept)
        if #kept == 0 then
            os.remove(path)
        else
            local f = io.open(path, "w")
            if f then f:write(hs.json.encode(data)); f:close() end
        end
    end

    if refreshWebview then refreshWebview() end
end

function focusSession(zj_session, pane_id, tab_num)
    pane_id = tonumber(pane_id)
    tab_num = tonumber(tab_num)
    focusLog("request session=" .. tostring(zj_session) .. " pane_id=" .. tostring(pane_id) .. " tab_num=" .. tostring(tab_num))
    if not zj_session or not pane_id then
        focusLog("ignored missing identity")
        return
    end

    if hs.application and hs.application.launchOrFocus then
        focusLog("launchOrFocus " .. TERMINAL_APP)
        hs.application.launchOrFocus(TERMINAL_APP)
    end

    if tab_num and tab_num > 0 then
        local tabCmd = string.format('zellij -s %q action go-to-tab %d', zj_session, tab_num)
        focusLog("exec " .. tabCmd)
        hs.execute(tabCmd, true)
    end

    local payload = string.format('{"hook_event":"Focus","pane_id":%d}', pane_id)
    local cmd = string.format('zellij -s %q pipe --name "claude-tab-status" -- %q', zj_session, payload)
    focusLog("exec " .. cmd)
    hs.execute(cmd, true)
end

function dismissEvent(id)
    if id == nil then return end
    id = tostring(id)
    local kept = {}
    for _, event in ipairs(eventQueue) do
        if tostring(event.id) ~= id then table.insert(kept, event) end
    end
    eventQueue = kept
    if refreshWebview then refreshWebview() end
end

function startDrag(mx, my)
    if not webview then return end
    if dragTap then dragTap:stop(); dragTap = nil end
    local f = webview:frame()
    local pos = hs.mouse.absolutePosition()
    dragState = {
        mx = tonumber(mx) or pos.x,
        my = tonumber(my) or pos.y,
        x = f.x,
        y = f.y,
        w = f.w,
        h = f.h,
    }
    debugLog("drag start")
    dragTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp }, function(event)
        if not dragState then return false end
        if event:getType() == hs.eventtap.event.types.leftMouseUp then
            endDrag()
            return false
        end
        local pos = hs.mouse.absolutePosition()
        moveDrag(pos.x - dragState.mx, pos.y - dragState.my)
        return false
    end)
    dragTap:start()
end

function moveDrag(dx, dy)
    if not webview or not dragState then return end
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    debugLog("drag move")
    webview:frame({ x = dragState.x + dx, y = dragState.y + dy, w = dragState.w, h = dragState.h })
    if settingsWebview then settingsWebview:hide() end
    if eventWebview then eventWebview:hide() end
end

function endDrag()
    if not webview or not dragState then dragState = nil; return end
    local f = webview:frame()
    placementState = webviewPlacement.inferAnchor(f, screenFrame(), WINDOW_PADDING)
    if dragTap then dragTap:stop(); dragTap = nil end
    dragState = nil
    debugLog("drag end")
    if refreshWebview then refreshWebview() end
end

local function pointInFrame(point, frame)
    if not point or not frame then return false end
    return point.x >= frame.x and point.x <= frame.x + frame.w
        and point.y >= frame.y and point.y <= frame.y + frame.h
end

local function updateNativeHover(pos)
    if not webview or not visible or not webview:isVisible() then return end
    local nextPeekHover = not expanded and not peekPinned and viewMode == "peek" and pointInFrame(pos, webview:frame())
    if nextPeekHover ~= peekHover then
        peekHover = nextPeekHover
        debugLog("native peek hover=" .. tostring(peekHover))
        hoverLog("native peek hover=" .. tostring(peekHover))
        if refreshWebview then refreshWebview() end
    end
end

local function stopInteractionTap()
    if interactionTap then interactionTap:stop() end
    interactionTap = nil
    pointerState = nil
end

local function startInteractionTap()
    stopInteractionTap()
    interactionTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.leftMouseDragged, hs.eventtap.event.types.leftMouseUp }, function(event)
        if not webview or not visible or not webview:isVisible() then return false end
        local eventType = event:getType()
        local pos = hs.mouse.absolutePosition()

        if eventType == hs.eventtap.event.types.mouseMoved then
            updateNativeHover(pos)
            return false
        end

        if eventType == hs.eventtap.event.types.leftMouseDown then
            if not expanded and (viewMode == "compact" or viewMode == "peek") then
                pointerState = nil
                debugLog("native compact/peek mouse down ignored")
                return false
            end
            if not expanded and pointInFrame(pos, webview:frame()) then
                pointerState = { x = pos.x, y = pos.y, moved = false }
                debugLog("native mouse down inside main frame")
                startDrag(pos.x, pos.y)
            end
            return false
        end

        if not pointerState then return false end

        if eventType == hs.eventtap.event.types.leftMouseDragged then
            if math.abs(pos.x - pointerState.x) > CLICK_DRAG_THRESHOLD or math.abs(pos.y - pointerState.y) > CLICK_DRAG_THRESHOLD then
                pointerState.moved = true
            end
            return false
        end

        if eventType == hs.eventtap.event.types.leftMouseUp then
            debugLog("native mouse up moved=" .. tostring(pointerState.moved))
            if not pointerState.moved then
                if viewMode == "compact" or viewMode == "peek" then
                    debugLog("ignored compact/peek native click expand")
                elseif canOpenDetailView() then
                    expanded = true
                    settingsOpen = false
                    hoverCollapseSuppressedUntil = hs.timer.secondsSinceEpoch() + 0.6
                    debugLog("native collapsed click expand")
                    if refreshWebview then refreshWebview() end
                else
                    debugLog("ignored dormant detail native click expand")
                end
            end
            pointerState = nil
            return false
        end

        return false
    end)
    interactionTap:start()
end

local function countActivity(activity)
    local a = activity
    if a == "Thinking" or a == "Tool" or a == "Init" then
        counts.active = counts.active + 1
    elseif a == "Waiting" then
        counts.waiting = counts.waiting + 1
    elseif a == "Done" or a == "Idle" then
        counts.done = counts.done + 1
    end
end

local function assignDisplayLabels()
    local tabCounts = {}
    for _, s in ipairs(sessions) do
        local t = s.tab_num or 0
        tabCounts[t] = (tabCounts[t] or 0) + 1
    end

    local tabSeen = {}
    for _, s in ipairs(sessions) do
        local t = s.tab_num or 0
        if tabCounts[t] > 1 then
            tabSeen[t] = (tabSeen[t] or 0) + 1
            s._display_num = t .. "." .. tabSeen[t]
        else
            s._display_num = tostring(t)
        end
    end
end

local function flashId(session)
    return tostring(session.pane_id or (session._zj_session .. "_" .. session._display_num))
end

local function cleanupExpiredFlashes()
    local now = hs.timer.secondsSinceEpoch()
    for id, flash in pairs(flashState) do
        if now > flash.expires then flashState[id] = nil end
    end
end

local function eventIdentity(session, kind)
    return tostring(kind) .. ":" .. flashId(session)
end

local function sessionEventTitle(kind, session)
    local name = session.tab_name or "Zellij"
    if kind == "waiting" then
        return tostring(name) .. " needs input"
    end
    return tostring(name) .. " finished"
end

local function enqueueStatusEvent(kind, session, now)
    if settings.notificationsEnabled == false then return end
    if type(session) ~= "table" then return end
    now = now or hs.timer.secondsSinceEpoch()
    local key = eventIdentity(session, kind)

    for _, event in ipairs(eventQueue) do
        if event.key == key then
            event.created_at = now
            event.expires = kind == "finished" and (now + EVENT_TTL) or nil
            event.sticky = kind == "waiting"
            event.title = sessionEventTitle(kind, session)
            event.display_label = session._display_num or session.display_label or session.tab_num
            event.detail = kind == "waiting" and tostring(event.display_label) .. " · Waiting for approval" or tostring(event.display_label) .. " · Click to focus"
            return
        end
    end

    table.insert(eventQueue, 1, {
        id = tostring(nextEventId),
        key = key,
        kind = kind,
        sticky = kind == "waiting",
        title = sessionEventTitle(kind, session),
        pane_id = session.pane_id,
        _zj_session = session._zj_session,
        tab_num = session.tab_num,
        display_label = session._display_num or session.display_label or session.tab_num,
        created_at = now,
        expires = kind == "finished" and (now + EVENT_TTL) or nil,
    })
    eventQueue[1].detail = kind == "waiting" and tostring(eventQueue[1].display_label) .. " · Waiting for approval" or tostring(eventQueue[1].display_label) .. " · Click to focus"
    nextEventId = nextEventId + 1
end

local function cleanupExpiredEvents()
    local now = hs.timer.secondsSinceEpoch()
    local waitingByKey = {}
    for _, s in ipairs(sessions) do
        if (s.activity or "Init") == "Waiting" then
            waitingByKey[eventIdentity(s, "waiting")] = true
        end
    end

    local kept = {}
    for _, event in ipairs(eventQueue) do
        if event.kind == "waiting" then
            if waitingByKey[event.key] then table.insert(kept, event) end
        elseif not event.expires or now <= event.expires then
            table.insert(kept, event)
        end
    end
    eventQueue = kept
end

local function playStatusSound(kind)
    if not SOUND_ENABLED or not settings.soundsEnabled then return end
    local config = kind == "done" and SOUND_DONE or SOUND_WAITING
    if not config then return end

    local now = hs.timer.secondsSinceEpoch()
    if lastStatusSoundAt[kind] and (now - lastStatusSoundAt[kind]) < SOUND_COOLDOWN then
        return
    end
    lastStatusSoundAt[kind] = now

    local ok, err = pcall(function()
        local sound = nil
        if config.file and config.file ~= "" then
            sound = hs.sound.getByFile(config.file)
        elseif config.name and config.name ~= "" then
            sound = hs.sound.getByName(config.name)
        end
        if sound then sound:play() end
    end)
    if not ok then
        print("[claude-status-webview] sound error: " .. tostring(err))
    end
end

local function playWaitingReminderSound()
    if not settings.waitingReminderSound then return end
    local hasWaiting = false
    for _, s in ipairs(sessions) do
        local a = s.activity or "Init"
        if a == "Waiting" then hasWaiting = true; break end
    end
    if not hasWaiting then return end

    local now = hs.timer.secondsSinceEpoch()
    local lastWaitingSoundAt = lastStatusSoundAt.waiting or 0
    if now - lastWaitingSoundAt >= WAITING_SOUND_REMINDER_INTERVAL then
        playStatusSound("waiting")
    end
end

local function detectActivityTransitions()
    local now2 = hs.timer.secondsSinceEpoch()
    local newActivities = {}
    for _, s in ipairs(sessions) do
        local id = flashId(s)
        local activity = s.activity or "Init"
        local prev = prevActivities[id]
        newActivities[id] = activity
        if prev and prev ~= activity then
            if (activity == "Done" or activity == "Idle") and (prev == "Thinking" or prev == "Tool" or prev == "Waiting") then
                if settings.completionFlash then
                    flashState[id] = {
                        active = true,
                        expires = now2 + COMPLETION_HIGHLIGHT_DURATION,
                        duration = COMPLETION_HIGHLIGHT_DURATION,
                        camera_expires = now2 + FLASH_DURATION,
                        camera_duration = FLASH_DURATION,
                    }
                end
                enqueueStatusEvent("finished", s, now2)
                playStatusSound("done")
            elseif activity == "Waiting" then
                playStatusSound("waiting")
                enqueueStatusEvent("waiting", s, now2)
            end
        end
    end
    prevActivities = newActivities
end

local function loadSessions()
    sessions = {}
    counts = { active = 0, waiting = 0, done = 0 }

    local now = os.time()
    debugLog("loadSessions start dir=" .. STATUS_DIR)
    local ok, iter, dirobj = pcall(require("hs.fs").dir, STATUS_DIR)
    if not ok then
        debugLog("loadSessions dir failed")
        return
    end

    local deny = loadDenylist()
    for file in iter, dirobj do
        if file:match("%.json$") then
            local path = STATUS_DIR .. "/" .. file
            local data = hs.json.read(path)
            if data and data.updated_at then
                local age = now - data.updated_at
                if age <= STALE_THRESHOLD and data.sessions then
                    debugLog("loadSessions file=" .. file .. " age=" .. tostring(age) .. " rows=" .. tostring(#data.sessions))
                    local zj_session = file:gsub("%.json$", "")
                    for _, s in ipairs(data.sessions) do
                        local key = denylistKey(zj_session, s.pane_id)
                        if not deny[key] then
                            s._zj_session = zj_session
                            local row = {
                                pane_id = s.pane_id,
                                tab_num = s.tab_num,
                                tab_name = s.tab_name,
                                activity = s.activity,
                                icon = s.icon,
                                detail = s.detail,
                                _zj_session = s._zj_session,
                                _flash_id = tostring(s.pane_id or (s._zj_session .. "_" .. tostring(s.tab_num or 0))),
                            }
                            table.insert(sessions, row)
                            countActivity(row.activity)
                        end
                    end
                elseif age > STALE_THRESHOLD then
                    debugLog("loadSessions stale file=" .. file .. " age=" .. tostring(age))
                    os.remove(path)
                end
            else
                debugLog("loadSessions skipped unreadable file=" .. file)
            end
        end
    end

    table.sort(sessions, function(a, b) return (a.tab_num or 0) < (b.tab_num or 0) end)
    assignDisplayLabels()
    cleanupExpiredFlashes()
    detectActivityTransitions()
    cleanupExpiredEvents()
    playWaitingReminderSound()
    debugLog("loadSessions result sessions=" .. tostring(#sessions) .. " active=" .. tostring(counts.active) .. " waiting=" .. tostring(counts.waiting) .. " done=" .. tostring(counts.done))
end

local function partitionSessions()
    local active, inactive = {}, {}
    for _, s in ipairs(sessions) do
        local a = s.activity or "Init"
        if a == "Done" or a == "Idle" then
            table.insert(inactive, s)
        else
            table.insert(active, s)
        end
    end

    table.sort(inactive, function(a, b)
        local function parseElapsed(detail)
            local n, unit = tostring(detail or ""):match("(%d+)([smh])")
            n = tonumber(n)
            if n then
                if unit == "s" then return n end
                if unit == "m" then return n * 60 end
                if unit == "h" then return n * 3600 end
            end
            return 999999
        end
        return parseElapsed(a.detail) < parseElapsed(b.detail)
    end)

    return active, inactive
end

local function buildFlashViewState()
    cleanupExpiredFlashes()
    local flashRows = {}
    local widgetActive = false
    for id, flash in pairs(flashState) do
        flashRows[id] = {
            active = true,
            highlightExpires = flash.expires,
            highlightDuration = flash.duration,
            cameraExpires = flash.camera_expires,
            cameraDuration = flash.camera_duration,
        }
        if flash.camera_expires and flash.camera_expires > hs.timer.secondsSinceEpoch() then
            widgetActive = true
        end
    end
    return {
        widget = widgetActive,
        rows = flashRows,
    }
end

local function buildEventViewState()
    if settings.notificationsEnabled == false then
        return { events = {}, overflow = 0 }
    end
    cleanupExpiredEvents()
    local events = {}
    for i, event in ipairs(eventQueue) do
        if i <= MAX_EVENT_ROWS then
            local copy = {}
            for key, value in pairs(event) do copy[key] = value end
            table.insert(events, copy)
        end
    end
    return {
        events = events,
        overflow = math.max(#eventQueue - MAX_EVENT_ROWS, 0),
    }
end

local function buildViewState()
    loadSessions()
    local activeSessions, inactiveSessions = partitionSessions()
    local eventState = buildEventViewState()
    return webviewState.build({
        visible = visible,
        counts = counts,
        sessions = sessions,
        activeSessions = activeSessions,
        inactiveSessions = inactiveSessions,
        settings = settings,
        settingsItems = SETTINGS_ITEMS,
        flash = buildFlashViewState(),
        expanded = expanded,
        viewMode = viewMode,
        peekHover = peekHover,
        peekPinned = peekPinned,
        pinned = pinned,
        settingsOpen = settingsOpen,
        olderFinishedExpanded = olderFinishedExpanded,
        placementState = placementState,
        debug = debugEnabled(),
        events = eventState.events,
        eventOverflow = eventState.overflow,
    })
end

local function buildHtml()
    return webviewHtml.build({
        styles = webviewStyles.css(),
        bridgeScheme = BRIDGE_SCHEME,
    })
end

local function rendererScript()
    return webviewHtml.script(BRIDGE_SCHEME)
end

local function compactLayoutDebugScript()
    return [[
(function() {
  try {
    function node(selector) {
      var element = document.querySelector(selector);
      if (!element) return { selector: selector, exists: false };
      var style = window.getComputedStyle(element);
      var rect = element.getBoundingClientRect();
      return {
        selector: selector,
        exists: true,
        className: element.className || "",
        display: style.display,
        position: style.position,
        gridColumnStart: style.gridColumnStart,
        gridColumnEnd: style.gridColumnEnd,
        justifySelf: style.justifySelf,
        alignSelf: style.alignSelf,
        opacity: style.opacity,
        pointerEvents: style.pointerEvents,
        width: Math.round(rect.width * 10) / 10,
        height: Math.round(rect.height * 10) / 10,
        left: Math.round(rect.left * 10) / 10,
        top: Math.round(rect.top * 10) / 10,
        right: Math.round(rect.right * 10) / 10,
        bottom: Math.round(rect.bottom * 10) / 10,
        offsetWidth: element.offsetWidth,
        offsetHeight: element.offsetHeight
      };
    }
    var widget = document.querySelector(".widget");
    var payload = {
      widgetClass: widget ? widget.className : "",
      viewport: {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        clientWidth: document.documentElement ? document.documentElement.clientWidth : null,
        clientHeight: document.documentElement ? document.documentElement.clientHeight : null
      },
      widget: node(".widget"),
      header: node(".header"),
      loader: node(".loader-slot"),
      counts: node(".header-counts"),
      peekTicker: node(".peek-ticker"),
      miniButton: node(".mini-enlarge-toggle"),
      collapseButton: node(".collapse-toggle")
    };
    return JSON.stringify(payload);
  } catch (error) {
    return "error:" + (error && error.name ? error.name : "unknown") + ":" + (error && error.message ? error.message : String(error));
  }
})();
]]
end

local function buildSettingsHtml()
    return webviewHtml.buildSettings({
        styles = webviewStyles.css(),
        bridgeScheme = BRIDGE_SCHEME,
    })
end

local function buildEventsHtml()
    return webviewHtml.buildEvents({
        styles = webviewStyles.css(),
        bridgeScheme = BRIDGE_SCHEME,
    })
end

local function buildHtmlReference()
    return [[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    :root {
      color-scheme: dark;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: transparent;
    }

    * {
      box-sizing: border-box;
    }

    html,
    body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: transparent;
      color: rgba(255, 255, 255, 0.88);
    }

    .widget {
      width: 100%;
      min-height: 32px;
      border: 1px solid rgba(128, 128, 148, 0.55);
      border-radius: 8px;
      background: rgba(23, 23, 33, 0.94);
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.28);
      overflow: hidden;
      position: relative;
    }

    .widget-flash {
      position: absolute;
      inset: 1px;
      border-radius: 7px;
      pointer-events: none;
      opacity: 0;
      background: rgba(255, 255, 255, 0.55);
      z-index: 5;
    }

    .widget.widget-flashing .widget-flash {
      animation: widgetFlash 1.5s ease-out both;
    }

    .header {
      height: 32px;
      display: grid;
      grid-template-columns: 20px 1fr 28px 28px;
      align-items: center;
      gap: 8px;
      padding: 0 8px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.06);
    }

    .spinner {
      width: 16px;
      height: 16px;
      border-radius: 50%;
      border: 2px solid rgba(255, 255, 255, 0.16);
      border-top-color: rgba(115, 166, 255, 0.9);
    }

    .counts {
      min-width: 0;
      display: flex;
      gap: 8px;
      font-size: 12px;
      white-space: nowrap;
      overflow: hidden;
    }

    .count {
      color: rgba(255, 255, 255, 0.55);
    }

    .header-button {
      width: 24px;
      height: 24px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.06);
      color: rgba(255, 255, 255, 0.82);
      line-height: 20px;
      padding: 0;
    }

    .pin-button {
      width: 24px;
      height: 24px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.06);
      color: rgba(255, 255, 255, 0.82);
      line-height: 20px;
      padding: 0;
    }

    .pinned .pin-button {
      background: rgba(115, 166, 255, 0.32);
    }

    .rows {
      display: grid;
      gap: 3px;
      padding: 6px;
    }

    .row {
      min-height: 28px;
      display: grid;
      grid-template-columns: 36px minmax(0, 1fr) minmax(72px, auto);
      align-items: center;
      gap: 8px;
      padding: 4px 7px;
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.025);
      font-size: 12px;
    }

    .row.waiting {
      background: rgba(255, 140, 89, 0.11);
    }

    .waiting-pulse-enabled .row.waiting {
      background: rgba(255, 140, 89, 0.18);
      animation: waitingPulse 1.6s ease-in-out infinite;
    }

    .row.done,
    .row.idle {
      min-height: 24px;
      color: rgba(255, 255, 255, 0.58);
      font-size: 11px;
    }

    .row.completion-highlight {
      background: rgba(255, 255, 255, 0.92);
      color: rgba(10, 13, 15, 0.96);
      box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.70);
    }

    .row.completion-highlight .badge {
      color: rgba(10, 13, 15, 0.96);
      background: rgba(0, 0, 0, 0.08);
    }

    .row.completion-highlight .status {
      color: rgba(10, 13, 15, 0.96);
    }

    .badge,
    .title,
    .status {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .badge {
      border-radius: 5px;
      padding: 2px 4px;
      color: rgba(255, 255, 255, 0.45);
    }

    .status {
      text-align: right;
      color: rgba(255, 255, 255, 0.68);
    }

    .divider {
      height: 1px;
      margin: 3px 4px;
      background: rgba(255, 255, 255, 0.08);
    }

    .empty {
      min-height: 44px;
      display: grid;
      place-items: center;
      color: rgba(255, 255, 255, 0.42);
      font-size: 12px;
    }

    .settings {
      display: grid;
      gap: 0;
      padding: 4px 8px 8px;
      border-top: 1px solid rgba(255, 255, 255, 0.06);
    }

    .setting {
      height: 28px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-size: 11px;
      color: rgba(255, 255, 255, 0.82);
    }

    .switch input {
      display: none;
    }

    .track {
      width: 26px;
      height: 16px;
      display: block;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.14);
      position: relative;
    }

    .track::after {
      content: "";
      width: 12px;
      height: 12px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.85);
      position: absolute;
      top: 2px;
      left: 2px;
      transition: transform 120ms ease;
    }

    .switch input:checked + .track {
      background: rgba(115, 166, 255, 0.52);
    }

    .switch input:checked + .track::after {
      transform: translateX(10px);
    }

    @keyframes waitingPulse {
      0%,
      100% {
        background: rgba(255, 140, 89, 0.12);
        box-shadow: 0 0 0 1px rgba(255, 140, 89, 0.22);
      }
      50% {
        background: rgba(255, 140, 89, 0.28);
        box-shadow: 0 0 0 1px rgba(255, 140, 89, 0.72);
      }
    }

    @keyframes widgetFlash {
      0% {
        opacity: 0.55;
      }
      100% {
        opacity: 0;
      }
    }
  </style>
  <script>
    (function() {
      var VALID_SETTING_KEYS = { soundsEnabled: true, waitingReminderSound: true, waitingPulse: true, completionFlash: true, processingNeon: true, notificationsEnabled: true };
      var VALID_ACTION_TYPES = { "setting.toggle": true, "pin.toggle": true, "row.dismiss": true, "drag.start": true, "drag.move": true, "drag.end": true, "expand.set": true };
      var BRIDGE_SCHEME = "claude-status";
      var dragOrigin = null;

      function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, function(ch) {
          return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch];
        });
      }

      function postAction(message) {
        if (!message || !VALID_ACTION_TYPES[message.type]) return;
        if (message.type === "setting.toggle" && !VALID_SETTING_KEYS[message.key]) return;
        window.location.href = BRIDGE_SCHEME + "://action?payload=" + encodeURIComponent(JSON.stringify(message));
      }

      function postSettingToggle(message) {
        if (!message || message.type !== "setting.toggle") return;
        if (!VALID_SETTING_KEYS[message.key]) return;
        postAction(message);
      }

      function renderRows(rows, className) {
        var fragment = document.createDocumentFragment();
        var flash = window.__claudeStatusFlash || {};
        var flashRows = flash.rows || {};
        var settings = window.__claudeStatusSettings || {};
        (rows || []).forEach(function(row) {
          var el = document.createElement("article");
          el.className = "row " + className + " " + String(row.activity || "Init").toLowerCase();
          el.dataset.paneId = String(row.pane_id ?? "");
          el.dataset.zjSession = row._zj_session || "";
          var rowId = String(row.pane_id || (row._zj_session + "_" + row._display_num));
          var flashInfo = flashRows[row._flash_id];
          if (!flashInfo) flashInfo = flashRows[rowId];
          if (flashInfo && settings.completionFlash) {
            el.classList.add("completion-highlight");
          }
          el.innerHTML =
            '<span class="badge">' + escapeHtml(row._display_num || row.tab_num || "") + '</span>' +
            '<span class="title">' + escapeHtml(row.tab_name || "") + '</span>' +
            '<span class="status">' + escapeHtml(row.icon || "") + ' ' +
            escapeHtml(row.activity || "Init") +
            (row.detail ? ' ' + escapeHtml(row.detail || "") : '') +
            '</span>';
          fragment.appendChild(el);
        });
        return fragment;
      }

      function renderSettings(settings, settingsItems) {
        var settingsEl = document.getElementById("settings");
        if (!settingsEl) return;
        settingsEl.innerHTML = "";
        (settingsItems || []).forEach(function(item) {
          if (!VALID_SETTING_KEYS[item.key]) return;
          var row = document.createElement("label");
          row.className = "setting";
          row.dataset.setting = item.key;
          row.innerHTML =
            escapeHtml(item.label || item.key) +
            ' <span class="switch"><input type="checkbox"><span class="track"></span></span>';
          var input = row.querySelector("input");
          input.checked = !!settings[item.key];
          settingsEl.appendChild(row);
        });
      }

      window.renderStatus = function(state) {
        state = state || {};
        var counts = state.counts || {};
        var settings = state.settings || {};
        var flash = state.flash || {};
        var widget = document.querySelector(".widget");
        var countsEl = document.getElementById("counts");
        var rowsEl = document.getElementById("rows");
        if (!countsEl || !rowsEl) return;

        window.__claudeStatusSettings = settings;
        window.__claudeStatusFlash = flash;
        document.body.classList.toggle("waiting-pulse-enabled", !!settings.waitingPulse);
        if (widget) {
          widget.classList.toggle("widget-flashing", !!(flash.widget && settings.completionFlash));
          widget.classList.toggle("expanded", !!state.expanded);
          widget.classList.toggle("pinned", !!state.pinned);
        }
        renderSettings(settings, state.settingsItems || []);

        countsEl.querySelector('[data-count="active"]').textContent = "active " + (counts.active || 0);
        countsEl.querySelector('[data-count="waiting"]').textContent = "waiting " + (counts.waiting || 0);
        countsEl.querySelector('[data-count="done"]').textContent = "done " + (counts.done || 0);

        rowsEl.innerHTML = "";
        var activeRows = state.activeSessions || [];
        var inactiveRows = state.inactiveSessions || [];
        if (activeRows.length === 0 && inactiveRows.length === 0) {
          var empty = document.createElement("div");
          empty.className = "empty";
          empty.textContent = "No Claude sessions";
          rowsEl.appendChild(empty);
          return;
        }

        rowsEl.appendChild(renderRows(activeRows, "active"));
        if (activeRows.length > 0 && inactiveRows.length > 0) {
          var divider = document.createElement("div");
          divider.className = "divider";
          rowsEl.appendChild(divider);
        }
        rowsEl.appendChild(renderRows(inactiveRows, "inactive"));
      };

      document.addEventListener("click", function(event) {
        var action = event.target.closest("[data-action]");
        if (action && action.dataset.action === "pin.toggle") {
          postAction({ type: "pin.toggle" });
          return;
        }
        var row = event.target.closest("[data-setting]");
        if (!row) return;
        var key = row.dataset.setting;
        postSettingToggle({ type: "setting.toggle", key: key });
      });

      document.addEventListener("mouseenter", function() {
        postAction({ type: "expand.set", expanded: true });
      });

      document.addEventListener("mouseleave", function() {
        postAction({ type: "expand.set", expanded: false });
      });

      document.addEventListener("pointerdown", function(event) {
        if (event.target.closest("button, input, [data-setting]")) return;
        dragOrigin = { x: event.screenX, y: event.screenY };
        postAction({ type: "drag.start", x: event.screenX, y: event.screenY });
      });

      document.addEventListener("pointermove", function(event) {
        if (!dragOrigin) return;
        postAction({ type: "drag.move", dx: event.screenX - dragOrigin.x, dy: event.screenY - dragOrigin.y });
      });

      document.addEventListener("pointerup", function() {
        if (!dragOrigin) return;
        dragOrigin = null;
        postAction({ type: "drag.end" });
      });
    })();
  </script>
</head>
<body>
  <main class="widget">
    <div class="widget-flash" id="widget-flash"></div>
    <header class="header">
      <div class="spinner" aria-hidden="true"></div>
      <div class="counts" id="counts">
        <span class="count" data-count="active">active 0</span>
        <span class="count" data-count="waiting">waiting 0</span>
        <span class="count" data-count="done">done 0</span>
      </div>
      <button class="header-button" data-action="settings" type="button">v</button>
      <button class="pin-button" data-action="pin.toggle" type="button">p</button>
    </header>

    <section class="rows" id="rows">
      <div class="empty">No Claude sessions</div>
    </section>

    <section class="settings" id="settings">
      <label class="setting" data-setting="soundsEnabled">Sounds <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
      <label class="setting" data-setting="waitingReminderSound">Waiting reminders <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
      <label class="setting" data-setting="waitingPulse">Waiting pulse <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
      <label class="setting" data-setting="completionFlash">Finish flash <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
      <label class="setting" data-setting="processingNeon">Processing neon <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
      <label class="setting" data-setting="notificationsEnabled">Show notifications <span class="switch"><input type="checkbox"><span class="track"></span></span></label>
    </section>
  </main>
</body>
</html>
]]
end

function refreshWebview()
    if not webview then return end

    local viewState = buildViewState()
    currentFrameSize = viewState.frame
    local mainFrame = webview:frame()
    debugLog("refresh state expanded=" .. tostring(viewState.expanded) .. " sessions=" .. tostring(#sessions) .. " activeRows=" .. tostring(#viewState.activeRows) .. " completedRows=" .. tostring(#viewState.completedRows) .. " frame=" .. tostring(mainFrame.x) .. "," .. tostring(mainFrame.y) .. " " .. tostring(mainFrame.w) .. "x" .. tostring(mainFrame.h))
    if not dragState then
        mainFrame = frameForSize(currentFrameSize)
        webview:frame(mainFrame)
    end
    local payload = hs.json.encode(viewState)
    local bootstrapScript = rendererScript()
    local script = bootstrapScript .. [[
(function() {
  try {
    var state = ]] .. payload .. [[;
    if (typeof window.renderStatus !== "function") {
      return "missing-renderStatus";
    }
    window.renderStatus(state);
    var activeValue = document.querySelector('[data-count="active"] .count-value');
    var completedValue = document.querySelector('[data-count="completed"] .count-value');
    return "ok active=" + (activeValue ? activeValue.textContent : "missing") + " completed=" + (completedValue ? completedValue.textContent : "missing");
  } catch (error) {
    return "error:" + (error && error.name ? error.name : "unknown") + ":" + (error && error.message ? error.message : String(error));
  }
})();
]]
    webview:evaluateJavaScript(script, function(result)
        debugLog("render eval result=" .. tostring(result))
    end)
    if debugEnabled() and viewState.viewMode == "compact" then
        webview:evaluateJavaScript(compactLayoutDebugScript(), function(layout)
            debugLog("layout " .. tostring(layout))
        end)
    end

    local shouldShow = false
    if visible and #sessions > 0 then
        shouldShow = true
    elseif visible and #eventQueue > 0 then
        shouldShow = true
    elseif visible and expanded then
        shouldShow = true
    end

    if shouldShow then
        webview:show()
    else
        webview:hide()
    end

    local showSettings = shouldShow and settingsOpen
    if showSettings then
        if not settingsWebview then
            local settingsFrame = webviewPlacement.placePopover(screenFrame(), mainFrame, settingsSize(), {
                padding = WINDOW_PADDING,
                gap = POPOVER_GAP,
            })
            settingsWebview = hs.webview.new(settingsFrame)
            settingsWebview:windowStyle({ "borderless" })
            settingsWebview:level(hs.canvas.windowLevels.floating)
            settingsWebview:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
            settingsWebview:transparent(true)
            settingsWebview:allowTextEntry(false)
            settingsWebview:policyCallback(handlePolicyAction)
            settingsWebview:html(buildSettingsHtml())
        end

        local settingsFrame = webviewPlacement.placePopover(screenFrame(), mainFrame, settingsSize(), {
            padding = WINDOW_PADDING,
            gap = POPOVER_GAP,
        })
        settingsWebview:frame(settingsFrame)
        settingsWebview:show()
        script = "window.renderSettings(" .. payload .. ");"
        settingsWebview:evaluateJavaScript(script, function(result)
            debugLog("settings eval result=" .. tostring(result))
        end)
    elseif settingsWebview then
        settingsWebview:hide()
    end

    local showEvents = shouldShow and settings.notificationsEnabled ~= false and not expanded and #eventQueue > 0
    if showEvents then
        if not eventWebview then
            local eventFrame = webviewPlacement.placePopover(screenFrame(), mainFrame, EVENT_POPOVER_SIZE, {
                padding = WINDOW_PADDING,
                gap = EVENT_POPOVER_GAP,
                order = { "below", "above", "left", "right" },
                clampCrossAxis = true,
            })
            eventWebview = hs.webview.new(eventFrame)
            eventWebview:windowStyle({ "borderless" })
            eventWebview:level(hs.canvas.windowLevels.floating)
            eventWebview:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
            eventWebview:transparent(true)
            eventWebview:allowTextEntry(false)
            eventWebview:policyCallback(handlePolicyAction)
            eventWebview:html(buildEventsHtml())
        end

        local eventFrame = webviewPlacement.placePopover(screenFrame(), mainFrame, EVENT_POPOVER_SIZE, {
            padding = WINDOW_PADDING,
            gap = EVENT_POPOVER_GAP,
            order = { "below", "above", "left", "right" },
            clampCrossAxis = true,
        })
        eventWebview:frame(eventFrame)
        eventWebview:show()
        local eventPayload = hs.json.encode(buildEventViewState())
        local eventScript = "window.renderEvents(" .. eventPayload .. ");"
        eventWebview:evaluateJavaScript(eventScript, function(result)
            debugLog("events eval result=" .. tostring(result))
        end)
    elseif eventWebview then
        eventWebview:hide()
    end
end

local function onFileChange()
    refreshWebview()
end

local function resetSessions()
    local ok, iter, dirobj = pcall(require("hs.fs").dir, STATUS_DIR)
    if ok then
        for file in iter, dirobj do
            if file:match("%.json$") then
                os.remove(STATUS_DIR .. "/" .. file)
            end
        end
    end
    if refreshWebview then refreshWebview() end
    if hs.alert then hs.alert.show("Claude status reset", 1) end
end

local function stopDrag()
    if dragTap then dragTap:stop(); dragTap = nil end
    dragState = nil
end

function M.stop()
    if updateTimer then updateTimer:stop() end
    if dragTap then dragTap:stop() end
    if interactionTap then interactionTap:stop() end
    if hotkey then hotkey:delete() end
    if hotkeyReset then hotkeyReset:delete() end
    if pathwatcher then pathwatcher:stop() end
    if webview then webview:delete() end
    if settingsWebview then settingsWebview:delete() end
    if eventWebview then eventWebview:delete() end

    updateTimer = nil
    stopDrag()
    stopInteractionTap()
    hotkey = nil
    hotkeyReset = nil
    pathwatcher = nil
    webview = nil
    settingsWebview = nil
    eventWebview = nil
    settingsOpen = false
    peekHover = false
end

function M.start()
    M.stop()
    os.execute("mkdir -p " .. STATUS_DIR)
    loadSettings()
    loadCompactMode()
    eventQueue = {}
    nextEventId = 1
    peekHover = false

    webview = hs.webview.new(defaultFrame())
    webview:windowStyle({ "borderless" })
    webview:level(hs.canvas.windowLevels.floating)
    webview:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    webview:transparent(true)
    webview:allowTextEntry(false)
    webview:policyCallback(handlePolicyAction)
    webview:html(buildHtml())
    startInteractionTap()

    pathwatcher = hs.pathwatcher.new(STATUS_DIR, onFileChange)
    pathwatcher:start()
    updateTimer = hs.timer.doEvery(1, refreshWebview)
    hotkey = hs.hotkey.bind({ "ctrl", "alt" }, "c", M.toggle)
    hotkeyReset = hs.hotkey.bind({ "ctrl", "alt" }, "r", resetSessions)

    refreshWebview()
end

function M.toggle()
    if not webview then
        visible = true
        M.start()
        return
    end

    if webview:isVisible() then
        webview:hide()
        visible = false
    else
        webview:show()
        visible = true
    end
end

return M
