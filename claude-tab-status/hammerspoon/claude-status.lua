-- claude-status.lua — macOS overlay for Claude Code session status
-- Reads JSON from /tmp/claude-tab-status/*.json, renders a floating canvas.

local M = {}

-- Config
local STATUS_DIR = "/tmp/claude-tab-status"
local STALE_THRESHOLD = 120
local DENYLIST_PATH = os.getenv("HOME") .. "/.hammerspoon/claude-status-denylist.json"
local DENYLIST_TTL = 30 * 24 * 60 * 60  -- 30 days

local function currentFileDir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then source = source:sub(2) end

    if hs and hs.fs and hs.fs.symlinkAttributes then
        local attrs = hs.fs.symlinkAttributes(source)
        if attrs and attrs.target then source = attrs.target end
    end

    return source:match("^(.*)/[^/]+$") or "."
end

local SOURCE_DIR = currentFileDir()

-- Sounds are intentionally owned by Hammerspoon so Claude Code and Codex share
-- one Mac-only notification path. Use either `name` for a system sound or
-- `file` for an absolute path to an audio file.
local SOUND_ENABLED = true
local SOUND_DONE = { file = SOURCE_DIR .. "/sounds/Glass.wav" }
local SOUND_WAITING = { name = "Ping" }
local SOUND_COOLDOWN = 0.75
local WAITING_SOUND_REMINDER_INTERVAL = 30.0

-- User settings persisted by Hammerspoon.
local SETTINGS_KEY = "claudeStatus.settings"
local DEFAULT_SETTINGS = {
    soundsEnabled = true,
    waitingReminderSound = true,
    waitingPulse = true,
    completionFlash = true,
}

-- Layout
local OFFSET_X = 15
local OFFSET_Y = 0
local PILL_WIDTH = 120
local EXPANDED_WIDTH = 300
local ROW_HEIGHT = 30
local ROW_HEIGHT_COMPACT = 26
local HEADER_HEIGHT = 30
local SEPARATOR_HEIGHT = 16
local SETTINGS_ROW_HEIGHT = 28
local SETTINGS_SECTION_GAP = 8
local ROW_GAP = 4
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

local WAITING_PULSE_PERIOD = 1.6

-- Row background tinted by activity color
local function rowBg(activity, alpha)
    local c = ACTIVITY_COLOR[activity]
    if c then
        return { red = c.red, green = c.green, blue = c.blue, alpha = alpha or 0.10 }
    end
    return { red = 1, green = 1, blue = 1, alpha = 0.04 }
end

local function rowBorder(activity, alpha)
    local c = ACTIVITY_COLOR[activity]
    if c then
        return { red = c.red, green = c.green, blue = c.blue, alpha = alpha or 0.25 }
    end
    return { red = 1, green = 1, blue = 1, alpha = 0.08 }
end

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

local SETTINGS_ITEMS = {
    { key = "soundsEnabled", label = "Sounds" },
    { key = "waitingReminderSound", label = "Waiting reminders" },
    { key = "waitingPulse", label = "Waiting pulse" },
    { key = "completionFlash", label = "Finish flash" },
}

-- Spinner animation
local SPINNER_FRAMES = { "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}" }
local spinnerIndex = 1
local spinnerTimer = nil

-- Exit code flash: pane_id -> { color, expires_at }
local flashState = {}
local FLASH_DURATION = 1.5
local COMPLETION_HIGHLIGHT_DURATION = 10.0
local FLASH_GREEN = { red = 0.30, green = 0.90, blue = 0.40, alpha = 0.25 }
local FLASH_CAMERA = { red = 1, green = 1, blue = 1, alpha = 0.55 }
local FLASH_COMPLETE = { red = 1, green = 1, blue = 1, alpha = 0.92 }
local FLASH_INVERT_TEXT = { red = 0.04, green = 0.05, blue = 0.06, alpha = 0.96 }
local FLASH_POP_PIXELS = 8
local FLASH_RED   = { red = 0.95, green = 0.30, blue = 0.30, alpha = 0.25 }

-- Previous activity state for detecting transitions
local prevActivities = {}  -- pane_id -> activity

-- State
local canvas = nil
local pathwatcher = nil
local hotkey = nil
local hotkeyReset = nil
local visible = true
local expanded = false
local settingsExpanded = false
local pinned = false
local sessions = {}
local counts = { active = 0, waiting = 0, done = 0 }
local lastStatusSoundAt = {}
local settings = {}
local hitboxes = {}
local hitboxMouseDown = nil

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

settings = defaultSettings()

local function registerHitbox(id, x, y, w, h)
    table.insert(hitboxes, { id = id, x = x, y = y, w = w, h = h })
end

local function hitboxAtMouse(mouse)
    if not canvas then return nil end
    local f = canvas:frame()
    local x = mouse.x - f.x
    local y = mouse.y - f.y
    for i = #hitboxes, 1, -1 do
        local hitbox = hitboxes[i]
        if x >= hitbox.x and x <= hitbox.x + hitbox.w and y >= hitbox.y and y <= hitbox.y + hitbox.h then
            return hitbox
        end
    end
    return nil
end

local function waitingPulseAlpha(minAlpha, maxAlpha)
    local t = hs.timer.secondsSinceEpoch()
    local wave = (math.sin((t / WAITING_PULSE_PERIOD) * math.pi * 2) + 1) / 2
    return minAlpha + ((maxAlpha - minAlpha) * wave)
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
        print("[claude-status] sound error: " .. tostring(err))
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

local function flashProgress(flash)
    local duration = flash.duration or FLASH_DURATION
    local remaining = math.max(0, flash.expires - hs.timer.secondsSinceEpoch())
    return math.max(0, math.min(1, 1 - (remaining / duration)))
end

local function flashPopProgress(flash)
    local duration = flash.camera_duration or FLASH_DURATION
    local expires = flash.camera_expires or flash.expires
    local remaining = math.max(0, expires - hs.timer.secondsSinceEpoch())
    return math.max(0, math.min(1, 1 - (remaining / duration)))
end

local function flashEaseOut(progress)
    return 1 - math.pow(1 - progress, 3)
end

local function cleanupExpiredFlashes()
    local now = hs.timer.secondsSinceEpoch()
    for id, f in pairs(flashState) do
        if now > f.expires then flashState[id] = nil end
    end
end

local function strongestFlashIntensity()
    local strongest = 0
    for _, flash in pairs(flashState) do
        local progress = flashPopProgress(flash)
        local intensity = (1 - flashEaseOut(progress)) * FLASH_CAMERA.alpha
        if intensity > strongest then strongest = intensity end
    end
    return strongest
end

local function drawWidgetFlash()
    local intensity = strongestFlashIntensity()
    if intensity <= 0 then return end
    local f = canvas:frame()
    canvas:appendElements({
        type = "rectangle",
        frame = { x = 1, y = 1, w = f.w - 2, h = f.h - 2 },
        fillColor = { red = FLASH_CAMERA.red, green = FLASH_CAMERA.green, blue = FLASH_CAMERA.blue, alpha = intensity },
        strokeWidth = 0,
        roundedRectRadii = { xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS },
    })
end

local function drawCompletionRowFlash(rowX, rowY, rowW, rowH, flash)
    local progress = flashPopProgress(flash)
    local lift = (1 - flashEaseOut(progress)) * FLASH_POP_PIXELS
    canvas:appendElements({
        type = "rectangle",
        frame = { x = rowX - lift, y = rowY - lift, w = rowW + (lift * 2), h = rowH + (lift * 2) },
        fillColor = FLASH_COMPLETE,
        strokeColor = { red = 1, green = 1, blue = 1, alpha = 0.85 * (1 - progress) },
        strokeWidth = 2.5,
        roundedRectRadii = { xRadius = 7, yRadius = 7 },
    })
end

-- Dismiss/drag state
local ignoreUpdatesUntil = 0
local dragTap = nil
local longPressTimer = nil
local dragging = false
local dragStart = nil -- { mx, my, cx, cy } mouse + canvas origin at mouseDown
local customPos = nil -- { x, y } user-chosen position, nil = default bottom-right

---------------------------------------------------------------------------
-- Denylist (persistent ghost suppression)
---------------------------------------------------------------------------

-- Returns map of "<zj_session>:<pane_id>" -> ts (unix). Drops entries older
-- than DENYLIST_TTL on load. Logs the file path on first load so users can
-- find it for manual cleanup: rm ~/.hammerspoon/claude-status-denylist.json
local denylistLogged = false
local function loadDenylist()
    if not denylistLogged then
        print("[claude-status] denylist file: " .. DENYLIST_PATH)
        denylistLogged = true
    end
    local data = hs.json.read(DENYLIST_PATH)
    if type(data) ~= "table" then return {} end
    local now = os.time()
    local fresh = {}
    for k, ts in pairs(data) do
        if type(ts) == "number" and (now - ts) < DENYLIST_TTL then
            fresh[k] = ts
        end
    end
    return fresh
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

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function loadSessions()
    sessions = {}
    counts = { active = 0, waiting = 0, done = 0 }
    local now = os.time()
    local ok, iter, dirobj = pcall(require("hs.fs").dir, STATUS_DIR)
    if not ok then return end
    local deny = loadDenylist()
    for file in iter, dirobj do
        if file:match("%.json$") then
            local path = STATUS_DIR .. "/" .. file
            local data = hs.json.read(path)
            if data and data.updated_at then
                local age = now - data.updated_at
                if age <= STALE_THRESHOLD and data.sessions then
                    local zj_session = file:gsub("%.json$", "")
                    for _, s in ipairs(data.sessions) do
                        local key = denylistKey(zj_session, s.pane_id)
                        if not deny[key] then
                            s._zj_session = zj_session
                            table.insert(sessions, s)
                            local a = s.activity or "Init"
                            if a == "Thinking" or a == "Tool" then
                                counts.active = counts.active + 1
                            elseif a == "Waiting" then
                                counts.waiting = counts.waiting + 1
                            elseif a == "Done" or a == "Idle" or a == "Init" then
                                counts.done = counts.done + 1
                            end
                        end
                    end
                elseif age > STALE_THRESHOLD then
                    -- Dead Zellij session — clean up the file
                    os.remove(path)
                end
            end
        end
    end
    table.sort(sessions, function(a, b) return (a.tab_num or 0) < (b.tab_num or 0) end)

    -- Assign display labels: "3" for single panes, "3.1"/"3.2" for multiple panes per tab
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

    -- Detect activity transitions for exit code flash
    local now2 = hs.timer.secondsSinceEpoch()
    local newActivities = {}
    for _, s in ipairs(sessions) do
        local id = s.pane_id or (s._zj_session .. "_" .. s._display_num)
        local activity = s.activity or "Init"
        local prev = prevActivities[id]
        newActivities[id] = activity
        -- Flash when transitioning from active state to Done/Idle
        if prev and prev ~= activity then
            if (activity == "Done" or activity == "Idle") and (prev == "Thinking" or prev == "Tool" or prev == "Waiting") then
                if settings.completionFlash then
                    flashState[id] = { color = FLASH_GREEN, expires = now2 + COMPLETION_HIGHLIGHT_DURATION, duration = COMPLETION_HIGHLIGHT_DURATION, camera_expires = now2 + FLASH_DURATION, camera_duration = FLASH_DURATION }
                end
                playStatusSound("done")
            elseif activity == "Waiting" then
                playStatusSound("waiting")
            end
        end
    end
    prevActivities = newActivities

    cleanupExpiredFlashes()
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function screenBottomRight()
    local f = hs.screen.mainScreen():frame()
    return f.x + f.w, f.y + f.h
end

-- Split sessions into active (needs attention) and inactive (done/idle) tiers.
local function partitionSessions()
    local active, inactive = {}, {}
    for _, s in ipairs(sessions) do
        local a = s.activity or "Init"
        if a == "Done" or a == "Idle" or a == "Init" then
            table.insert(inactive, s)
        else
            table.insert(active, s)
        end
    end
    -- Sort inactive by most recent first (detail contains elapsed time like "38s ago")
    -- Parse the numeric portion to sort properly
    table.sort(inactive, function(a, b)
        local function parseElapsed(d)
            if not d or d == "" or d == "null" then return 999999 end
            local n, unit = d:match("^(%d+)(%a)")
            if not n then return 999999 end
            n = tonumber(n)
            if unit == "s" then return n
            elseif unit == "m" then return n * 60
            elseif unit == "h" then return n * 3600
            end
            return 999999
        end
        return parseElapsed(a.detail) < parseElapsed(b.detail)
    end)
    return active, inactive
end

local function drawSettingsToggle(x, y, on)
    local track = on and { red = 0.45, green = 0.82, blue = 0.50, alpha = 0.88 } or { red = 1, green = 1, blue = 1, alpha = 0.16 }
    local knobX = on and (x + 18) or (x + 2)
    canvas:appendElements({
        type = "rectangle",
        frame = { x = x, y = y, w = 34, h = 18 },
        fillColor = track,
        strokeColor = { red = 1, green = 1, blue = 1, alpha = on and 0.18 or 0.10 },
        strokeWidth = 0.5,
        roundedRectRadii = { xRadius = 9, yRadius = 9 },
    })
    canvas:appendElements({
        type = "rectangle",
        frame = { x = knobX, y = y + 2, w = 14, h = 14 },
        fillColor = { red = 1, green = 1, blue = 1, alpha = 0.94 },
        strokeWidth = 0,
        roundedRectRadii = { xRadius = 7, yRadius = 7 },
    })
end

local function drawSettingsDrawer(y, w)
    canvas:appendElements({
        type = "segments",
        coordinates = {
            { x = PX + 4, y = y },
            { x = w - PX - 4, y = y },
        },
        strokeColor = { red = 1, green = 1, blue = 1, alpha = 0.22 },
        strokeWidth = 0.5,
    })
    y = y + 8

    for _, item in ipairs(SETTINGS_ITEMS) do
        local rowY = y
        local toggleX = w - PX - 38
        registerHitbox("settings.item", 8, rowY, w - 16, SETTINGS_ROW_HEIGHT)
        hitboxes[#hitboxes].setting = item.key
        canvas:appendElements({
            type = "rectangle",
            frame = { x = 8, y = rowY + 1, w = w - 16, h = SETTINGS_ROW_HEIGHT - 2 },
            fillColor = { red = 1, green = 1, blue = 1, alpha = 0.025 },
            strokeWidth = 0,
            roundedRectRadii = { xRadius = 6, yRadius = 6 },
            trackMouseDown = true,
            trackMouseUp = true,
        })
        canvas:appendElements({
            type = "text",
            frame = { x = PX, y = rowY + 6, w = w - 78, h = 18 },
            text = hs.styledtext.new(item.label, { font = FONT_SMALL, color = WHITE }),
        })
        drawSettingsToggle(toggleX, rowY + 5, settings[item.key])
        y = y + SETTINGS_ROW_HEIGHT
    end
end

local function redraw()
    if not canvas then return end

    local w = expanded and EXPANDED_WIDTH or PILL_WIDTH
    local activeSessions, inactiveSessions = partitionSessions()
    local h = HEADER_HEIGHT
    if expanded and #sessions > 0 then
        local activeH = #activeSessions * (ROW_HEIGHT + ROW_GAP)
        local sepH = (#activeSessions > 0 and #inactiveSessions > 0) and SEPARATOR_HEIGHT or 0
        local inactiveH = #inactiveSessions * (ROW_HEIGHT_COMPACT + ROW_GAP)
        h = HEADER_HEIGHT + activeH + sepH + inactiveH + 6
    end
    if expanded and settingsExpanded then
        h = h + SETTINGS_SECTION_GAP + 8 + (#SETTINGS_ITEMS * SETTINGS_ROW_HEIGHT)
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
    hitboxes = {}

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

    -- Build header counts (centered)
    local function buildHeaderCounts()
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
        st = st:setStyle({ paragraphStyle = { alignment = "center" } }, 1, #tostring(st))
        return st
    end

    -- Check if any session is truly running (not just Init)
    local hasRunning = false
    for _, s in ipairs(sessions) do
        local a = s.activity or "Init"
        if a == "Thinking" or a == "Tool" then hasRunning = true; break end
    end

    -- Spinner element (far left, separate from counts)
    local function drawSpinner()
        if hasRunning then
            local frame = SPINNER_FRAMES[spinnerIndex] or SPINNER_FRAMES[1]
            canvas:appendElements({
                type = "text",
                frame = { x = PX, y = 7, w = 20, h = 20 },
                text = hs.styledtext.new(frame, { font = FONT_HEADER, color = ACTIVITY_COLOR.Thinking }),
            })
        end
    end

    local function drawSettingsButton()
        registerHitbox("settings.toggle", w - 34, 5, 24, 20)
        canvas:appendElements({
            type = "rectangle",
            frame = { x = w - 34, y = 5, w = 24, h = 20 },
            fillColor = settingsExpanded and { red = 1, green = 1, blue = 1, alpha = 0.15 } or { red = 1, green = 1, blue = 1, alpha = 0.06 },
            strokeColor = { red = 1, green = 1, blue = 1, alpha = settingsExpanded and 0.22 or 0.10 },
            strokeWidth = 0.5,
            roundedRectRadii = { xRadius = 6, yRadius = 6 },
            trackMouseDown = true,
            trackMouseUp = true,
        })
        canvas:appendElements({
            type = "text",
            frame = { x = w - 34, y = 7, w = 24, h = 16 },
            text = hs.styledtext.new(settingsExpanded and "v" or ">", {
                font = FONT_BOLD, color = WHITE,
                paragraphStyle = { alignment = "center" },
            }),
        })
    end

    if not expanded then
        -- === COLLAPSED PILL ===
        drawSpinner()
        canvas:appendElements({ type = "text", frame = { x = 0, y = 7, w = w, h = 20 }, text = buildHeaderCounts() })
        drawSettingsButton()
    else
        -- === EXPANDED — summary header + session rows ===
        drawSpinner()
        canvas:appendElements({ type = "text", frame = { x = 0, y = 7, w = w, h = 20 }, text = buildHeaderCounts() })
        drawSettingsButton()

        -- === Active tier (full-size rows) ===
        local y = HEADER_HEIGHT
        for i, s in ipairs(activeSessions) do
            local activity = s.activity or "Init"

            -- Activity-tinted row background
            local rowX, rowW = 8, w - 16
            local rowFillColor = rowBg(activity, 0.12)
            local rowBorderColor = rowBorder(activity, 0.25)
            if activity == "Waiting" and settings.waitingPulse then
                rowFillColor = rowBg(activity, waitingPulseAlpha(0.12, 0.28))
                rowBorderColor = rowBorder(activity, waitingPulseAlpha(0.25, 0.72))
            end
            canvas:appendElements({
                type = "rectangle",
                frame = { x = rowX, y = y + 1, w = rowW, h = ROW_HEIGHT - 1 },
                fillColor = rowFillColor,
                strokeColor = rowBorderColor, strokeWidth = 0.5,
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
            })
            local sid = s.pane_id or (s._zj_session .. "_" .. s._display_num)
            local flash = flashState[sid]
            if flash then
                drawCompletionRowFlash(rowX, y + 1, rowW, ROW_HEIGHT - 1, flash)
            end

            local mid = y + (ROW_HEIGHT / 2)

            -- Tab number badge (wider for multi-pane labels like "3.1")
            local label = s._display_num or tostring(s.tab_num or 0)
            local badge_w = #label > 2 and 30 or 22
            local badge_h = 18
            local badgeFillColor = flash and { red = 0, green = 0, blue = 0, alpha = 0.08 } or badgeBg(activity)
            local badgeTextColor = flash and FLASH_INVERT_TEXT or badgeFg(activity)
            canvas:appendElements({
                type = "rectangle",
                frame = { x = PX, y = mid - badge_h/2, w = badge_w, h = badge_h },
                fillColor = badgeFillColor, strokeWidth = 0,
                roundedRectRadii = { xRadius = 5, yRadius = 5 },
            })
            canvas:appendElements({
                type = "text",
                frame = { x = PX, y = mid - badge_h/2 + 2, w = badge_w, h = badge_h },
                text = hs.styledtext.new(label, {
                    font = FONT_BOLD, color = badgeTextColor,
                    paragraphStyle = { alignment = "center" },
                }),
            })

            -- Tab name (+1 to compensate for text top-padding)
            local text_h = 18
            local name = s.tab_name or "?"
            if #name > 22 then name = name:sub(1, 20) .. "\u{2026}" end
            local nameColor = flash and FLASH_INVERT_TEXT or WHITE
            canvas:appendElements({
                type = "text",
                frame = { x = PX + badge_w + 8, y = mid - text_h/2 + 2, w = w - 160, h = text_h },
                text = hs.styledtext.new(name, { font = FONT_BODY, color = nameColor }),
            })

            -- Status (right-aligned, +1 to match tab name)
            local icon = s.icon or ""
            local detail = s.detail or ""
            local sc = ACTIVITY_COLOR[activity] or DIM
            local statusColor = flash and FLASH_INVERT_TEXT or sc
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
                frame = { x = w - 116, y = mid - text_h/2 + 2, w = 102, h = text_h },
                text = hs.styledtext.new(status, {
                    font = FONT_SMALL, color = statusColor,
                    paragraphStyle = { alignment = "right" },
                }),
            })

            y = y + ROW_HEIGHT + ROW_GAP
        end

        -- === Separator between tiers ===
        if #activeSessions > 0 and #inactiveSessions > 0 then
            local sepY = y + math.floor(SEPARATOR_HEIGHT / 2)
            canvas:appendElements({
                type = "segments",
                coordinates = {
                    { x = PX + 4, y = sepY },
                    { x = w - PX - 4, y = sepY },
                },
                strokeColor = { red = 1, green = 1, blue = 1, alpha = 0.50 },
                strokeWidth = 0.5,
                strokeDashPattern = { 4, 3 },
            })
            y = y + SEPARATOR_HEIGHT
        end

        -- === Inactive tier (compact, dimmed rows) ===
        local DIM_WHITE = { red = 1, green = 1, blue = 1, alpha = 0.65 }
        for i, s in ipairs(inactiveSessions) do
            local activity = s.activity or "Idle"

            -- Activity-tinted row background (dimmer for inactive)
            canvas:appendElements({
                type = "rectangle",
                frame = { x = 8, y = y + 1, w = w - 16, h = ROW_HEIGHT_COMPACT - 1 },
                fillColor = rowBg(activity, 0.06),
                strokeColor = rowBorder(activity, 0.12), strokeWidth = 0.5,
                roundedRectRadii = { xRadius = 6, yRadius = 6 },
            })
            local sid = s.pane_id or (s._zj_session .. "_" .. s._display_num)
            local flash = flashState[sid]
            if flash then
                drawCompletionRowFlash(8, y + 1, w - 16, ROW_HEIGHT_COMPACT - 1, flash)
            end

            local mid = y + (ROW_HEIGHT_COMPACT / 2)

            -- Tab number badge (smaller for compact rows, wider for multi-pane labels)
            local label = s._display_num or tostring(s.tab_num or 0)
            local badge_w = #label > 2 and 28 or 20
            local badge_h = 16
            local compactBadgeFillColor = flash and { red = 0, green = 0, blue = 0, alpha = 0.08 } or badgeBg(activity)
            local compactBadgeTextColor = flash and FLASH_INVERT_TEXT or badgeFg(activity)
            canvas:appendElements({
                type = "rectangle",
                frame = { x = PX, y = mid - badge_h/2 + 1, w = badge_w, h = badge_h },
                fillColor = compactBadgeFillColor, strokeWidth = 0,
                roundedRectRadii = { xRadius = 4, yRadius = 4 },
            })
            canvas:appendElements({
                type = "text",
                frame = { x = PX, y = mid - badge_h/2 + 2, w = badge_w, h = badge_h },
                text = hs.styledtext.new(label, {
                    font = FONT_BOLD, color = compactBadgeTextColor,
                    paragraphStyle = { alignment = "center" },
                }),
            })

            -- Tab name (dimmed, +2 to compensate for text top-padding)
            local text_h = 16
            local name = s.tab_name or "?"
            if #name > 22 then name = name:sub(1, 20) .. "\u{2026}" end
            local compactNameColor = flash and FLASH_INVERT_TEXT or DIM_WHITE
            canvas:appendElements({
                type = "text",
                frame = { x = PX + badge_w + 8, y = mid - text_h/2 + 2, w = w - 150, h = text_h },
                text = hs.styledtext.new(name, { font = FONT_SMALL, color = compactNameColor }),
            })

            -- Status (right-aligned, uniform dimmed green for all inactive)
            local icon = s.icon or ""
            local detail = s.detail or ""
            local sc = { red = 0.45, green = 0.82, blue = 0.50, alpha = 0.65 }
            local compactStatusColor = flash and FLASH_INVERT_TEXT or sc
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
                frame = { x = w - 110, y = mid - text_h/2 + 2, w = 96, h = text_h },
                text = hs.styledtext.new(status, {
                    font = FONT_SMALL, color = compactStatusColor,
                    paragraphStyle = { alignment = "right" },
                }),
            })

            y = y + ROW_HEIGHT_COMPACT + ROW_GAP
        end

        if settingsExpanded then
            y = y + SETTINGS_SECTION_GAP
            drawSettingsDrawer(y, w)
        end
    end

    drawWidgetFlash()

    -- Hide entirely when no sessions, show when there are
    if visible and (#sessions > 0 or settingsExpanded) then canvas:show() else canvas:hide() end
end

-- Manage animation timers based on whether active sessions exist
local function updateSpinnerTimer()
    local hasMotion = next(flashState) ~= nil
    for _, s in ipairs(sessions) do
        local a = s.activity or "Init"
        if a == "Thinking" or a == "Tool" or (a == "Waiting" and (settings.waitingPulse or settings.waitingReminderSound)) then hasMotion = true; break end
    end
    if hasMotion and not spinnerTimer then
        spinnerTimer = hs.timer.doEvery(0.08, function()
            spinnerIndex = (spinnerIndex % #SPINNER_FRAMES) + 1
            cleanupExpiredFlashes()
            playWaitingReminderSound()
            if not dragging then redraw() end
            updateSpinnerTimer()
        end)
    elseif not hasMotion and spinnerTimer then
        spinnerTimer:stop(); spinnerTimer = nil
        spinnerIndex = 1
    end

end

local function handleHitbox(hitbox)
    if hitbox.id == "settings.toggle" then
        settingsExpanded = not settingsExpanded
        if settingsExpanded then
            expanded = true
            pinned = true
        end
        redraw()
        updateSpinnerTimer()
        return true
    elseif hitbox.id == "settings.item" and hitbox.setting then
        settings[hitbox.setting] = not settings[hitbox.setting]
        saveSettings()
        redraw()
        updateSpinnerTimer()
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function onFileChange()
    if os.time() < ignoreUpdatesUntil then return end
    loadSessions(); redraw(); updateSpinnerTimer()
end

local function toggleVisibility()
    visible = not visible
    if visible then loadSessions(); redraw(); updateSpinnerTimer(); canvas:show() else canvas:hide(); updateSpinnerTimer() end
end

local function dismissSessionAtY(mouseY)
    if not expanded or #sessions == 0 then return false end
    local activeSessions, inactiveSessions = partitionSessions()
    local f = canvas:frame()
    local localY = mouseY - f.y
    if localY < HEADER_HEIGHT then return false end

    -- Walk the layout to find which session was hit
    local y = HEADER_HEIGHT
    local s = nil

    -- Check active tier
    for _, sess in ipairs(activeSessions) do
        if localY >= y and localY < y + ROW_HEIGHT then s = sess; break end
        y = y + ROW_HEIGHT + ROW_GAP
    end

    -- Separator
    if not s and #activeSessions > 0 and #inactiveSessions > 0 then
        y = y + SEPARATOR_HEIGHT
    end

    -- Check inactive tier
    if not s then
        for _, sess in ipairs(inactiveSessions) do
            if localY >= y and localY < y + ROW_HEIGHT_COMPACT then s = sess; break end
            y = y + ROW_HEIGHT_COMPACT + ROW_GAP
        end
    end

    if not s then return false end
    if not s._zj_session then return false end

    -- 0. Persist to denylist so this row can never reappear, even if the plugin
    -- re-creates the session in-memory or reads a stale file. Survives reboots.
    if s.pane_id then
        addToDenylist(s._zj_session, s.pane_id)
    end

    -- 1. Try signaling the live plugin (works if Zellij session is alive).
    -- "Dismiss" tells the plugin to remove the session AND block this pane_id
    -- from re-creation for 30 min — surviving stuck-Init hook loops.
    if s.pane_id then
        local payload = string.format('{"hook_event":"Dismiss","pane_id":%d}', s.pane_id)
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
            local a = existing.activity or "Init"
            if a == "Thinking" or a == "Tool" then
                data.counts.active = data.counts.active + 1
            elseif a == "Waiting" then
                data.counts.waiting = data.counts.waiting + 1
            elseif a == "Done" or a == "Idle" or a == "Init" then
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
    loadSessions(); redraw(); updateSpinnerTimer()
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
    loadSessions(); redraw(); updateSpinnerTimer()
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
    loadSettings()
    local rx, ry = screenBottomRight()
    canvas = hs.canvas.new({ x = rx - PILL_WIDTH - OFFSET_X, y = ry - HEADER_HEIGHT - OFFSET_Y, w = PILL_WIDTH, h = HEADER_HEIGHT })
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas:clickActivating(false)
    canvas:mouseCallback(function(_, msg)
        if msg == "mouseDown" then
            local mouse = hs.mouse.absolutePosition()
            hitboxMouseDown = hitboxAtMouse(mouse)
            if hitboxMouseDown then return end
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
                    -- Cancel long-press on drag and pause animations
                    dragging = true
                    if longPressTimer then longPressTimer:stop(); longPressTimer = nil end
                    local f = canvas:frame()
                    canvas:frame({ x = dragStart.cx + dx, y = dragStart.cy + dy, w = f.w, h = f.h })
                end
                return false
            end)
            dragTap:start()
        elseif msg == "mouseUp" then
            local mouse = hs.mouse.absolutePosition()
            if hitboxMouseDown then
                local hitbox = hitboxAtMouse(mouse)
                if hitbox and hitbox.id == hitboxMouseDown.id and hitbox.setting == hitboxMouseDown.setting then
                    handleHitbox(hitbox)
                end
                hitboxMouseDown = nil
                dragStart = nil
                dragging = false
                stopDrag()
                if longPressTimer then longPressTimer:stop(); longPressTimer = nil end
                return
            end
            local wasDrag = false
            if dragStart then
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
            dragging = false
            stopDrag()
            -- Cancel long-press if released before 3s
            if longPressTimer then longPressTimer:stop(); longPressTimer = nil end
            if not wasDrag then
                -- Single click: toggle pin
                pinned = not pinned
                expanded = pinned
                if not expanded then settingsExpanded = false end
                loadSessions(); redraw(); updateSpinnerTimer()
            end
        elseif msg == "mouseEnter" then
            if not pinned then expanded = true; loadSessions(); redraw(); updateSpinnerTimer() end
        elseif msg == "mouseExit" then
            if not pinned then expanded = false; loadSessions(); redraw(); updateSpinnerTimer() end
        end
    end)

    loadSessions(); redraw(); updateSpinnerTimer()

    pathwatcher = hs.pathwatcher.new(STATUS_DIR, onFileChange)
    pathwatcher:start()
    hotkey = hs.hotkey.bind({ "ctrl", "alt" }, "c", toggleVisibility)
    hotkeyReset = hs.hotkey.bind({ "ctrl", "alt" }, "r", resetSessions)
end

function M.stop()
    if spinnerTimer then spinnerTimer:stop(); spinnerTimer = nil end
    if hotkey then hotkey:delete() end
    if hotkeyReset then hotkeyReset:delete() end
    if pathwatcher then pathwatcher:stop() end
    if canvas then canvas:delete() end
    stopDrag()
    canvas = nil; pathwatcher = nil; hotkey = nil; hotkeyReset = nil
end

M.start()
return M
