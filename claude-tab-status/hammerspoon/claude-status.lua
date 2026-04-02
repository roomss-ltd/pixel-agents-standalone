-- claude-status.lua — macOS overlay for Claude Code session status
-- Reads JSON from /tmp/claude-tab-status/*.json, renders a floating canvas.

local M = {}

-- Config
local STATUS_DIR = "/tmp/claude-tab-status"
local STALE_THRESHOLD = 120

-- Layout
local OFFSET_X = 15
local OFFSET_Y = 0
local PILL_WIDTH = 120
local EXPANDED_WIDTH = 300
local ROW_HEIGHT = 30
local HEADER_HEIGHT = 30
local CORNER_RADIUS = 12
local PX = 14

-- Typography
local FONT_HEADER = { name = ".AppleSystemUIFont", size = 12 }
local FONT_BOLD = { name = ".AppleSystemUIFontBold", size = 10 }
local FONT_BODY = { name = ".AppleSystemUIFont", size = 12 }
local FONT_SMALL = { name = ".AppleSystemUIFont", size = 11 }

-- Colors — dark glass
local BG = { red = 0.09, green = 0.09, blue = 0.13, alpha = 0.94 }
local BORDER_OUTER = { red = 0.50, green = 0.50, blue = 0.58, alpha = 0.55 }
local BORDER_INNER = { red = 1, green = 1, blue = 1, alpha = 0.04 }
local WHITE = { red = 1, green = 1, blue = 1, alpha = 0.88 }
local DIM = { red = 1, green = 1, blue = 1, alpha = 0.35 }
local ROW_EVEN = { red = 1, green = 1, blue = 1, alpha = 0.025 }
local ROW_HIGHLIGHT = { red = 1, green = 1, blue = 1, alpha = 0.05 }

local ACTIVITY_COLOR = {
    Thinking = { red = 0.45, green = 0.65, blue = 1.0, alpha = 1 },
    Tool     = { red = 1.0,  green = 0.75, blue = 0.25, alpha = 1 },
    Waiting  = { red = 1.0,  green = 0.55, blue = 0.35, alpha = 1 },
    Done     = { red = 0.45, green = 0.82, blue = 0.50, alpha = 1 },
    Init     = { red = 0.55, green = 0.55, blue = 0.60, alpha = 1 },
    Idle     = { red = 0.45, green = 0.82, blue = 0.50, alpha = 0.5 },
}

-- Badge gets tinted by activity color (low alpha)
local function badgeBg(activity)
    local c = ACTIVITY_COLOR[activity]
    if c then
        return { red = c.red, green = c.green, blue = c.blue, alpha = 0.15 }
    end
    return { red = 1, green = 1, blue = 1, alpha = 0.08 }
end

local function badgeFg(activity)
    local c = ACTIVITY_COLOR[activity]
    if c then
        return { red = c.red, green = c.green, blue = c.blue, alpha = 0.85 }
    end
    return { red = 1, green = 1, blue = 1, alpha = 0.55 }
end

local PILL_ICONS = {
    { key = "active",  icon = "\u{25CF}", color = ACTIVITY_COLOR.Thinking },
    { key = "waiting", icon = "\u{23F8}", color = ACTIVITY_COLOR.Waiting },
    { key = "done",    icon = "\u{2713}", color = ACTIVITY_COLOR.Done },
}

-- State
local canvas = nil
local pathwatcher = nil
local hotkey = nil
local hotkeyReset = nil
local visible = true
local expanded = false
local pinned = false
local sessions = {}
local counts = { active = 0, waiting = 0, done = 0 }

-- Dismiss/drag state
local ignoreUpdatesUntil = 0
local dragTap = nil
local longPressTimer = nil
local dragStart = nil -- { mx, my, cx, cy } mouse + canvas origin at mouseDown
local customPos = nil -- { x, y } user-chosen position, nil = default bottom-right

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function loadSessions()
    sessions = {}
    counts = { active = 0, waiting = 0, done = 0 }
    local now = os.time()
    local ok, iter, dirobj = pcall(require("hs.fs").dir, STATUS_DIR)
    if not ok then return end
    for file in iter, dirobj do
        if file:match("%.json$") then
            local path = STATUS_DIR .. "/" .. file
            local data = hs.json.read(path)
            if data and data.updated_at then
                local age = now - data.updated_at
                if age <= STALE_THRESHOLD and data.sessions then
                    local zj_session = file:gsub("%.json$", "")
                    for _, s in ipairs(data.sessions) do
                        s._zj_session = zj_session
                        table.insert(sessions, s)
                    end
                    counts.active  = counts.active  + (data.counts and data.counts.active or 0)
                    counts.waiting = counts.waiting + (data.counts and data.counts.waiting or 0)
                    counts.done    = counts.done    + (data.counts and data.counts.done or 0)
                elseif age > STALE_THRESHOLD then
                    -- Dead Zellij session — clean up the file
                    os.remove(path)
                end
            end
        end
    end
    table.sort(sessions, function(a, b) return (a.tab_num or 0) < (b.tab_num or 0) end)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function screenBottomRight()
    local f = hs.screen.mainScreen():frame()
    return f.x + f.w, f.y + f.h
end

local function redraw()
    if not canvas then return end

    local w = expanded and EXPANDED_WIDTH or PILL_WIDTH
    local h = HEADER_HEIGHT
    if expanded and #sessions > 0 then
        h = HEADER_HEIGHT + (#sessions * ROW_HEIGHT) + 6
    end

    local cx, cy
    if customPos then
        -- User-dragged position: anchor bottom-right corner of canvas
        cx = customPos.x - w
        cy = customPos.y - h
    else
        local rx, ry = screenBottomRight()
        cx = rx - w - OFFSET_X
        cy = ry - h - OFFSET_Y
    end
    canvas:frame({ x = cx, y = cy, w = w, h = h })

    while canvas:elementCount() > 0 do canvas:removeElement(1) end

    -- Background with visible border (inset by 1px so stroke isn't clipped)
    canvas:appendElements({
        type = "rectangle",
        frame = { x = 1, y = 1, w = w - 2, h = h - 2 },
        fillColor = BG,
        strokeColor = BORDER_OUTER, strokeWidth = 1.5,
        roundedRectRadii = { xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS },
        trackMouseEnterExit = true,
        trackMouseDown = true,
        trackMouseUp = true,
    })

    if not expanded then
        -- === COLLAPSED PILL — summary with colored icons ===
        local st = hs.styledtext.new("")
        local any = false
        for _, e in ipairs(PILL_ICONS) do
            local n = counts[e.key] or 0
            if n > 0 then
                if any then st = st .. hs.styledtext.new("  ", { font = FONT_HEADER, color = DIM }) end
                st = st .. hs.styledtext.new(e.icon .. " ", { font = FONT_HEADER, color = e.color })
                st = st .. hs.styledtext.new(tostring(n), { font = FONT_HEADER, color = WHITE })
                any = true
            end
        end
        if not any then st = hs.styledtext.new("idle", { font = FONT_HEADER, color = DIM }) end
        canvas:appendElements({ type = "text", frame = { x = PX, y = 7, w = w - PX*2, h = 20 }, text = st })
    else
        -- === EXPANDED — summary header + session rows ===

        -- Header: show pill-style summary instead of "N sessions"
        local st = hs.styledtext.new("")
        local any = false
        for _, e in ipairs(PILL_ICONS) do
            local n = counts[e.key] or 0
            if n > 0 then
                if any then st = st .. hs.styledtext.new("  ", { font = FONT_HEADER, color = DIM }) end
                st = st .. hs.styledtext.new(e.icon .. " ", { font = FONT_HEADER, color = e.color })
                st = st .. hs.styledtext.new(tostring(n), { font = FONT_HEADER, color = WHITE })
                any = true
            end
        end
        if not any then st = hs.styledtext.new("idle", { font = FONT_HEADER, color = DIM }) end
        canvas:appendElements({ type = "text", frame = { x = PX, y = 7, w = w - PX*2, h = 20 }, text = st })

        -- Session rows
        for i, s in ipairs(sessions) do
            local y = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT
            local activity = s.activity or "Init"
            local isActive = (activity == "Thinking" or activity == "Tool" or activity == "Waiting")

            -- Alternating row backgrounds + highlight for active rows
            local rowBg
            if isActive then
                rowBg = ROW_HIGHLIGHT
            elseif i % 2 == 0 then
                rowBg = ROW_EVEN
            end
            if rowBg then
                canvas:appendElements({
                    type = "rectangle",
                    frame = { x = 4, y = y + 1, w = w - 8, h = ROW_HEIGHT - 1 },
                    fillColor = rowBg, strokeWidth = 0,
                    roundedRectRadii = { xRadius = 6, yRadius = 6 },
                })
            end

            -- All elements vertically centered in ROW_HEIGHT
            local mid = y + (ROW_HEIGHT / 2)

            -- Tab number badge — colored by activity
            local badge_w = 22
            local badge_h = 18
            canvas:appendElements({
                type = "rectangle",
                frame = { x = PX, y = mid - badge_h/2, w = badge_w, h = badge_h },
                fillColor = badgeBg(activity), strokeWidth = 0,
                roundedRectRadii = { xRadius = 5, yRadius = 5 },
            })
            canvas:appendElements({
                type = "text",
                frame = { x = PX, y = mid - badge_h/2 + 2, w = badge_w, h = badge_h },
                text = hs.styledtext.new(tostring(s.tab_num or 0), {
                    font = FONT_BOLD, color = badgeFg(activity),
                    paragraphStyle = { alignment = "center" },
                }),
            })

            -- Tab name
            local text_h = 18
            local name = s.tab_name or "?"
            if #name > 22 then name = name:sub(1, 20) .. "\u{2026}" end
            canvas:appendElements({
                type = "text",
                frame = { x = PX + badge_w + 8, y = mid - text_h/2, w = w - 160, h = text_h },
                text = hs.styledtext.new(name, { font = FONT_BODY, color = WHITE }),
            })

            -- Status (right-aligned)
            local icon = s.icon or ""
            local detail = s.detail or ""
            local sc = ACTIVITY_COLOR[activity] or DIM
            local has_detail = detail ~= nil and detail ~= "" and detail ~= "null"
            local status
            if has_detail then
                local d = detail
                if #d > 10 then d = d:sub(1, 8) .. "\u{2026}" end
                status = icon .. " " .. d
            else
                status = icon .. " " .. activity
            end
            canvas:appendElements({
                type = "text",
                frame = { x = w - 116, y = mid - text_h/2, w = 102, h = text_h },
                text = hs.styledtext.new(status, {
                    font = FONT_SMALL, color = sc,
                    paragraphStyle = { alignment = "right" },
                }),
            })
        end
    end

    -- Hide entirely when no sessions, show when there are
    if visible and #sessions > 0 then canvas:show() else canvas:hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function onFileChange()
    if os.time() < ignoreUpdatesUntil then return end
    loadSessions(); redraw()
end

local function toggleVisibility()
    visible = not visible
    if visible then loadSessions(); redraw(); canvas:show() else canvas:hide() end
end

local function dismissSessionAtY(mouseY)
    if not expanded or #sessions == 0 then return false end
    local f = canvas:frame()
    local localY = mouseY - f.y
    -- Only target row area, not header
    if localY < HEADER_HEIGHT then return false end
    local idx = math.floor((localY - HEADER_HEIGHT) / ROW_HEIGHT) + 1
    if idx < 1 or idx > #sessions then return false end
    local s = sessions[idx]
    if not s._zj_session then return false end

    -- 1. Try signaling the live plugin (works if Zellij session is alive)
    if s.pane_id then
        local payload = string.format('{"hook_event":"SessionEnd","pane_id":%d}', s.pane_id)
        local cmd = string.format('zellij -s %q pipe --name "claude-tab-status" -- %q',
            s._zj_session, payload)
        hs.execute(cmd, true)
    end

    -- 2. Also rewrite the JSON file excluding this session (works if session is dead or old plugin)
    local path = STATUS_DIR .. "/" .. s._zj_session .. ".json"
    local data = hs.json.read(path)
    if data and data.sessions then
        local kept = {}
        for _, existing in ipairs(data.sessions) do
            -- Match by pane_id if available, otherwise by tab_name + activity
            local isTarget = false
            if s.pane_id and existing.pane_id then
                isTarget = (existing.pane_id == s.pane_id)
            else
                isTarget = (existing.tab_name == s.tab_name and existing.activity == s.activity)
            end
            if not isTarget then
                table.insert(kept, existing)
            end
        end
        data.sessions = kept
        -- Recount
        data.counts = { active = 0, waiting = 0, done = 0 }
        for _, existing in ipairs(kept) do
            local a = existing.activity
            if a == "Thinking" or a == "Tool" or a == "Init" then
                data.counts.active = data.counts.active + 1
            elseif a == "Waiting" then
                data.counts.waiting = data.counts.waiting + 1
            elseif a == "Done" or a == "Idle" then
                data.counts.done = data.counts.done + 1
            end
        end
        if #kept == 0 then
            os.remove(path)
        else
            local f = io.open(path, "w")
            if f then f:write(hs.json.encode(data)); f:close() end
        end
    end

    -- Ignore pathwatcher updates for 7s to let the plugin process the pipe
    ignoreUpdatesUntil = os.time() + 7
    loadSessions(); redraw()
    return true
end

local function resetSessions()
    -- Delete all JSON files — plugin rewrites live sessions on next 5s tick
    local ok, iter, dirobj = pcall(require("hs.fs").dir, STATUS_DIR)
    if ok then
        for file in iter, dirobj do
            if file:match("%.json$") then
                os.remove(STATUS_DIR .. "/" .. file)
            end
        end
    end
    loadSessions(); redraw()
    hs.alert.show("Claude status reset", 1)
end

local function stopDrag()
    if dragTap then dragTap:stop(); dragTap = nil end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function M.start()
    os.execute("mkdir -p " .. STATUS_DIR)
    local rx, ry = screenBottomRight()
    canvas = hs.canvas.new({ x = rx - PILL_WIDTH - OFFSET_X, y = ry - HEADER_HEIGHT - OFFSET_Y, w = PILL_WIDTH, h = HEADER_HEIGHT })
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas:clickActivating(false)
    canvas:mouseCallback(function(_, msg)
        if msg == "mouseDown" then
            local mouse = hs.mouse.absolutePosition()
            local f = canvas:frame()
            dragStart = { mx = mouse.x, my = mouse.y, cx = f.x, cy = f.y }
            -- Start long-press timer (3s) for dismiss
            if longPressTimer then longPressTimer:stop() end
            local pressY = mouse.y
            longPressTimer = hs.timer.doAfter(3, function()
                if expanded then
                    dismissSessionAtY(pressY)
                end
                longPressTimer = nil
            end)
            -- Start tracking mouse movement for drag
            dragTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged }, function(e)
                if not dragStart then return false end
                local cur = hs.mouse.absolutePosition()
                local dx = cur.x - dragStart.mx
                local dy = cur.y - dragStart.my
                if math.abs(dx) > 3 or math.abs(dy) > 3 then
                    -- Cancel long-press on drag
                    if longPressTimer then longPressTimer:stop(); longPressTimer = nil end
                    local f = canvas:frame()
                    canvas:frame({ x = dragStart.cx + dx, y = dragStart.cy + dy, w = f.w, h = f.h })
                end
                return false
            end)
            dragTap:start()
        elseif msg == "mouseUp" then
            local wasDrag = false
            if dragStart then
                local mouse = hs.mouse.absolutePosition()
                local dx = math.abs(mouse.x - dragStart.mx)
                local dy = math.abs(mouse.y - dragStart.my)
                if dx > 5 or dy > 5 then
                    -- Was a drag — save new position (bottom-right corner of canvas)
                    local f = canvas:frame()
                    customPos = { x = f.x + f.w, y = f.y + f.h }
                    wasDrag = true
                end
            end
            dragStart = nil
            stopDrag()
            -- Cancel long-press if released before 3s
            if longPressTimer then longPressTimer:stop(); longPressTimer = nil end
            if not wasDrag then
                -- Single click: toggle pin
                pinned = not pinned
                expanded = pinned
                loadSessions(); redraw()
            end
        elseif msg == "mouseEnter" then
            if not pinned then expanded = true; loadSessions(); redraw() end
        elseif msg == "mouseExit" then
            if not pinned then expanded = false; loadSessions(); redraw() end
        end
    end)

    loadSessions(); redraw()

    pathwatcher = hs.pathwatcher.new(STATUS_DIR, onFileChange)
    pathwatcher:start()
    hotkey = hs.hotkey.bind({ "ctrl", "alt" }, "c", toggleVisibility)
    hotkeyReset = hs.hotkey.bind({ "ctrl", "alt" }, "r", resetSessions)
end

function M.stop()
    if hotkey then hotkey:delete() end
    if hotkeyReset then hotkeyReset:delete() end
    if pathwatcher then pathwatcher:stop() end
    if canvas then canvas:delete() end
    stopDrag()
    canvas = nil; pathwatcher = nil; hotkey = nil; hotkeyReset = nil
end

M.start()
return M
