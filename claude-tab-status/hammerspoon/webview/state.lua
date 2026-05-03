-- webview/state.lua - serializable render-state helper for the webview UI.

local M = {}

local WIDTH = 300
local PILL_WIDTH = 188
local PEEK_WIDTH = 326
local PANEL_TOP_PADDING = 0
local PANEL_BOTTOM_PADDING = 10
local HEADER_HEIGHT = 30
local PEEK_HISTORY_MAX_ITEMS = 30
local PEEK_HISTORY_MAX_VISIBLE_ROWS = 8
local PEEK_ACTIVE_STACK_MAX_ITEMS = 3
local PEEK_ACTIVE_STACK_ROW_HEIGHT = 25
local PEEK_ACTIVE_STACK_ROW_GAP = 4
local PEEK_ACTIVE_STACK_OVERFLOW_HEIGHT = 16
local PEEK_QUEUE_DIVIDER_HEIGHT = 14
local PEEK_HISTORY_OLDER_DIVIDER_HEIGHT = 14
local PEEK_HISTORY_ROW_HEIGHT = 27
local PEEK_HISTORY_ROW_GAP = 4
local PEEK_HISTORY_EMPTY_HEIGHT = 14
local PEEK_HISTORY_REVEAL_PADDING = 9
local PEEK_HISTORY_SECTION_GAP = 5
local PEEK_ACTION_HEIGHT = 24
local PEEK_ACTION_WITH_OLDER_TOGGLE_HEIGHT = 54
local PEEK_HOVER_FRAME_SAFETY = 18
local PEEK_MAX_HOVER_FRAME_HEIGHT = 420
local BORDER_SHADOW_SAFETY = 6
local PEEK_HOVER_BORDER_SAFETY = BORDER_SHADOW_SAFETY + 10
local ACTIVE_ROW_HEIGHT = 28
local COMPLETED_ROW_HEIGHT = 22
local ROW_GAP = 3
local DIVIDER_HEIGHT = 16
local BOTTOM_ACTION_HEIGHT = 26
local BOTTOM_ACTION_BORDER_SAFETY = 8
local PEEK_VISIBLE_HEIGHT = 64
local PEEK_FRAME_HEIGHT = PEEK_VISIBLE_HEIGHT + BORDER_SHADOW_SAFETY
local EXPANDED_BORDER_SAFETY = 12
local COLLAPSED_FRAME_HEIGHT = HEADER_HEIGHT + BORDER_SHADOW_SAFETY
local MAX_FRAME_HEIGHT = 700
local RECENT_FINISHED_WINDOW_SECONDS = 3600
local DEFAULT_COMPACT_MODE = "peek"

local function peekHistoryListHeight(historyCount)
    if historyCount <= 0 then return PEEK_HISTORY_EMPTY_HEIGHT end
    local visibleRows = math.min(historyCount, PEEK_HISTORY_MAX_VISIBLE_ROWS)
    return (visibleRows * PEEK_HISTORY_ROW_HEIGHT) + (math.max(visibleRows - 1, 0) * PEEK_HISTORY_ROW_GAP)
end

local function peekActiveStackHeight(peek)
    peek = peek or {}
    local activeQueue = peek.activeQueue or {}
    local stackCount = #(activeQueue.stack or {})
    local overflow = activeQueue.overflow or 0
    if stackCount <= 0 and overflow <= 0 then return 0 end

    local height = stackCount * PEEK_ACTIVE_STACK_ROW_HEIGHT
    height = height + (math.max(stackCount - 1, 0) * PEEK_ACTIVE_STACK_ROW_GAP)
    if overflow > 0 then
        height = height + PEEK_ACTIVE_STACK_ROW_GAP + PEEK_ACTIVE_STACK_OVERFLOW_HEIGHT
    end
    return height + PEEK_HISTORY_SECTION_GAP
end

local function peekHoverFrameHeight(sections)
    local header = sections.header or {}
    local peek = header.peek or {}
    local historyCount = #(peek.history or {})
    local olderFinished = peek.olderFinished or {}
    if olderFinished.expanded == true then
        historyCount = historyCount + #(peek.olderHistory or {})
    end
    local stackCount = #((peek.activeQueue or {}).stack or {})
    local height = PEEK_FRAME_HEIGHT
    height = height + peekActiveStackHeight(peek)
    if #((sections.activeRows or {})) > 0 and historyCount > 0 then
        height = height + PEEK_QUEUE_DIVIDER_HEIGHT
    end
    if olderFinished.count and olderFinished.count > 0 then
        height = height + PEEK_HISTORY_OLDER_DIVIDER_HEIGHT
    end
    height = height + peekHistoryListHeight(historyCount)
    local actionHeight = PEEK_ACTION_HEIGHT
    if olderFinished.count and olderFinished.count > 0 then
        actionHeight = PEEK_ACTION_WITH_OLDER_TOGGLE_HEIGHT
    end
    height = height + PEEK_HISTORY_SECTION_GAP + actionHeight
    height = height + PEEK_HISTORY_REVEAL_PADDING + PEEK_HOVER_FRAME_SAFETY
    height = height + PEEK_HOVER_BORDER_SAFETY
    return math.min(height, PEEK_MAX_HOVER_FRAME_HEIGHT)
end

function M.frameForSections(sections)
    sections = sections or {}
    if not sections.expanded then
        if sections.viewMode == "peek" then
            return {
                width = PEEK_WIDTH,
                height = sections.peekHover and peekHoverFrameHeight(sections) or PEEK_FRAME_HEIGHT,
            }
        end
        return {
            width = PILL_WIDTH,
            height = COLLAPSED_FRAME_HEIGHT,
        }
    end

    local height = 0
    local olderRowsVisible = sections.olderFinished and sections.olderFinished.expanded == true
    height = height + PANEL_TOP_PADDING + PANEL_BOTTOM_PADDING
    height = height + HEADER_HEIGHT
    height = height + (#sections.activeRows * (ACTIVE_ROW_HEIGHT + ROW_GAP))
    height = height + (#sections.completedRows * (COMPLETED_ROW_HEIGHT + ROW_GAP))
    if sections.showOlderFinishedDivider then
        height = height + DIVIDER_HEIGHT
    end
    if olderRowsVisible then
        height = height + (#sections.olderCompletedRows * (COMPLETED_ROW_HEIGHT + ROW_GAP))
        height = height + EXPANDED_BORDER_SAFETY
    end
    if sections.showBottomActions then
        height = height + BOTTOM_ACTION_HEIGHT + ROW_GAP + BOTTOM_ACTION_BORDER_SAFETY
    end
    if sections.showDivider then
        height = height + DIVIDER_HEIGHT
    end
    height = height + BORDER_SHADOW_SAFETY
    height = math.min(height, MAX_FRAME_HEIGHT)
    return {
        width = sections.expanded and WIDTH or PILL_WIDTH,
        height = height,
    }
end

local function displayLabel(row)
    if row._display_num ~= nil then return tostring(row._display_num) end
    if row.display_label ~= nil then return tostring(row.display_label) end
    if row.tab_num ~= nil then return tostring(row.tab_num) end
    return ""
end

local function peekTitle(name)
    if name ~= "" then return name end
    return "Tab"
end

local function peekItemFromSession(row, kind)
    local label = displayLabel(row)
    local name = tostring(row.tab_name or "")
    local detail = tostring(row.detail or row.activity or "")
    if kind == "waiting" then
        detail = detail ~= "" and ("Needs input - " .. detail) or "Needs input"
    elseif detail == "" then
        detail = "Running"
    end
    return {
        kind = kind,
        title = peekTitle(name),
        detail = detail,
        display_label = label,
        pane_id = row.pane_id,
        _zj_session = row._zj_session,
        tab_num = row.tab_num,
    }
end

local function peekItemFromEvent(event)
    return {
        kind = event.kind or "finished",
        title = event.title or "",
        detail = event.detail or "",
        display_label = event.display_label,
        pane_id = event.pane_id,
        _zj_session = event._zj_session,
        tab_num = event.tab_num,
        event_id = event.id,
    }
end

local function rowKey(row)
    row = row or {}
    return table.concat({
        tostring(row._zj_session or ""),
        tostring(row.pane_id or ""),
        tostring(row.tab_num or ""),
    }, ":")
end

local function eventKeySet(events)
    local keys = {}
    for _, event in ipairs(events or {}) do
        keys[rowKey(event)] = true
    end
    return keys
end

local function peekItemFromCompletedRow(row, tier)
    row = row or {}
    local label = displayLabel(row)
    local name = tostring(row.tab_name or "")
    return {
        kind = "finished",
        tier = tier,
        title = peekTitle(name),
        detail = tostring(row.detail or ""),
        display_label = label,
        pane_id = row.pane_id,
        _zj_session = row._zj_session,
        tab_num = row.tab_num,
    }
end

local function buildIdlePeekItem(recentCompletedRows)
    local latest = recentCompletedRows and recentCompletedRows[1] and peekItemFromCompletedRow(recentCompletedRows[1])
    if latest then
        return {
            kind = "idle",
            title = "Coffee break",
            detail = "All tabs quiet · last finish " .. latest.detail,
            display_label = "",
            pane_id = latest.pane_id,
            _zj_session = latest._zj_session,
            tab_num = latest.tab_num,
        }
    end
    return {
        kind = "idle",
        title = "Coffee break",
        detail = "All tabs quiet",
        display_label = "",
    }
end

local function appendAll(target, values)
    for _, value in ipairs(values or {}) do
        table.insert(target, value)
    end
end

local function buildPeekItems(activeRows)
    local waitingItems, runningItems = {}, {}
    for _, row in ipairs(activeRows or {}) do
        if tostring(row.activity or ""):lower() == "waiting" then
            table.insert(waitingItems, peekItemFromSession(row, "waiting"))
        else
            table.insert(runningItems, peekItemFromSession(row, "running"))
        end
    end

    local items = {}
    appendAll(items, waitingItems)
    appendAll(items, runningItems)
    return items, #waitingItems > 0
end

local function buildPeekActiveQueue(peekItems)
    local stack = {}
    for i = 2, #peekItems do
        if #stack >= PEEK_ACTIVE_STACK_MAX_ITEMS then break end
        table.insert(stack, peekItems[i])
    end

    return {
        primary = peekItems[1],
        stack = stack,
        overflow = math.max(#peekItems - 1 - PEEK_ACTIVE_STACK_MAX_ITEMS, 0),
        maxVisible = PEEK_ACTIVE_STACK_MAX_ITEMS,
    }
end

local function buildPeekHistory(completedRows, events, tier)
    local history = {}
    local suppressed = eventKeySet(events)
    for _, row in ipairs(completedRows or {}) do
        if #history >= PEEK_HISTORY_MAX_ITEMS then break end
        local key = rowKey(row)
        if not suppressed[key] then
            table.insert(history, peekItemFromCompletedRow(row, tier))
        end
    end
    return history
end

local function compactViewMode(input, activeTotal)
    if input.viewMode == "compact" then return "compact" end
    if activeTotal <= 0 then return "compact" end
    if input.viewMode == "peek" then return "peek" end
    return DEFAULT_COMPACT_MODE
end

local function renderRows(rows)
    local rendered = {}
    for i, row in ipairs(rows or {}) do
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        copy.display_label = displayLabel(row)
        rendered[i] = copy
    end
    return rendered
end

local function parseElapsedSeconds(detail)
    local n, unit = tostring(detail or ""):match("(%d+)%s*([smhd])")
    n = tonumber(n)
    if not n then return 999999999 end
    if unit == "s" then return n end
    if unit == "m" then return n * 60 end
    if unit == "h" then return n * 3600 end
    if unit == "d" then return n * 86400 end
    return 999999999
end

local function splitFinishedRows(rows)
    local recentRows, olderRows = {}, {}
    for _, row in ipairs(rows or {}) do
        local elapsed = parseElapsedSeconds(row.detail)
        if elapsed <= RECENT_FINISHED_WINDOW_SECONDS then
            table.insert(recentRows, row)
        else
            table.insert(olderRows, row)
        end
    end
    return recentRows, olderRows
end

function M.build(input)
    input = input or {}
    local counts = input.counts or { active = 0, waiting = 0, done = 0 }
    local activeTotal = counts.active + counts.waiting
    local activeRows = renderRows(input.activeSessions)
    local allCompletedRows = renderRows(input.inactiveSessions)
    local recentCompletedRows, olderCompletedRows = splitFinishedRows(allCompletedRows)
    local completedRows = recentCompletedRows
    local showOlderFinishedControl = #olderCompletedRows > 0
    local showOlderFinishedDivider = showOlderFinishedControl and (#activeRows > 0 or #completedRows > 0)
    local finishedVisible = #completedRows > 0 or showOlderFinishedControl
    local showDivider = #activeRows > 0 and finishedVisible
    local settingsOpen = input.settingsOpen == true
    local peekItems, peekPinned = buildPeekItems(activeRows)
    if #peekItems == 0 then
        table.insert(peekItems, buildIdlePeekItem(recentCompletedRows))
    end
    local viewMode = input.expanded == true and "expanded" or compactViewMode(input, activeTotal)
    local olderExpanded = input.olderFinishedExpanded == true and (input.expanded == true or viewMode == "peek")
    local peekHover = (input.peekHover == true or input.peekPinned == true) and viewMode == "peek"
    local sections = {
        visible = input.visible,
        counts = counts,
        sessions = input.sessions,
        activeSessions = activeRows,
        inactiveSessions = allCompletedRows,
        header = {
            activeCount = counts.active,
            waitingCount = counts.waiting,
            completedCount = #recentCompletedRows,
            totalCompletedCount = counts.done,
            peek = {
                active = viewMode == "peek",
                items = peekItems,
                activeQueue = buildPeekActiveQueue(peekItems),
                history = buildPeekHistory(recentCompletedRows, input.events, "recent-finished"),
                olderHistory = buildPeekHistory(olderCompletedRows, input.events, "older-finished"),
                olderFinished = {
                    count = #olderCompletedRows,
                    expanded = olderExpanded,
                    label = "Older finished",
                },
                pinned = peekPinned,
                hovering = peekHover,
                hoverPinned = input.peekPinned == true,
            },
            loader = {
                active = activeTotal > 0,
                size = 18,
                speed = 1.75,
                color = "var(--active-blue)",
            },
            expanded = input.expanded,
            pinned = input.pinned,
        },
        activeRows = activeRows,
        completedRows = completedRows,
        recentCompletedRows = recentCompletedRows,
        olderCompletedRows = olderCompletedRows,
        olderFinished = {
            count = #olderCompletedRows,
            expanded = olderExpanded,
            label = "Older finished",
        },
        showDivider = showDivider,
        showOlderFinishedControl = showOlderFinishedControl,
        showOlderFinishedDivider = showOlderFinishedDivider,
        showBottomActions = input.expanded == true,
        settings = {
            items = input.settingsItems,
            values = input.settings,
            open = input.settingsOpen == true,
            soundsEnabled = input.settings and input.settings.soundsEnabled,
            waitingReminderSound = input.settings and input.settings.waitingReminderSound,
            waitingPulse = input.settings and input.settings.waitingPulse,
            completionFlash = input.settings and input.settings.completionFlash,
            processingNeon = input.settings and input.settings.processingNeon,
            notificationsEnabled = input.settings and input.settings.notificationsEnabled,
        },
        settingsItems = input.settingsItems,
        effects = {
            flash = input.flash,
            waitingPulse = input.settings and input.settings.waitingPulse,
            completionFlash = input.settings and input.settings.completionFlash,
            processingNeon = input.settings and input.settings.processingNeon,
        },
        flash = input.flash,
        notifications = {
            events = input.events or {},
            overflow = input.eventOverflow or 0,
        },
        viewMode = viewMode,
        peekHover = peekHover,
        expanded = input.expanded,
        pinned = input.pinned,
        settingsOpen = settingsOpen,
        customPos = input.customPos,
    }
    sections.frame = M.frameForSections(sections)
    return sections
end

return M
