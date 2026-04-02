-- claude-status.lua — macOS overlay for Claude Code session status
-- Reads JSON from /tmp/claude-tab-status/*.json, renders a floating canvas.

local M = {}

-- Config
local STATUS_DIR = "/tmp/claude-tab-status"
local STALE_THRESHOLD = 120 -- seconds
local OFFSET_X = 10
local OFFSET_Y = 10
local PILL_WIDTH = 210
local EXPANDED_WIDTH = 290
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 28
local FONT_SIZE = 13
local FONT = { name = "Menlo", size = FONT_SIZE }
local FONT_SMALL = { name = "Menlo", size = 11 }
local BG_COLOR = { red = 0.10, green = 0.10, blue = 0.18, alpha = 0.88 }
local TEXT_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.95 }
local MUTED_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.45 }
local SEPARATOR_COLOR = { red = 1, green = 1, blue = 1, alpha = 0.15 }
local CORNER_RADIUS = 8

-- State
local canvas = nil
local pathwatcher = nil
local visible = true
local expanded = false
local sessions = {}
local counts = { active = 0, waiting = 0, done = 0 }

-- Icon colors for the expanded view
local ICON_COLORS = {
    ["\u{25CF}"] = { red = 0.40, green = 0.70, blue = 1.0, alpha = 1 },  -- ● blue
    ["\u{26A1}"] = { red = 1.0,  green = 0.80, blue = 0.20, alpha = 1 }, -- ⚡ yellow
    ["\u{23F8}"] = { red = 1.0,  green = 0.50, blue = 0.30, alpha = 1 }, -- ⏸ orange
    ["\u{2713}"] = { red = 0.40, green = 0.85, blue = 0.45, alpha = 1 }, -- ✓ green
    ["\u{25CB}"] = { red = 0.60, green = 0.60, blue = 0.60, alpha = 1 }, -- ○ gray (Init)
}

---------------------------------------------------------------------------
-- Data loading
---------------------------------------------------------------------------

local function loadSessions()
    sessions = {}
    counts = { active = 0, waiting = 0, done = 0 }

    local now = os.time()

    -- Read all JSON files in the status directory
    local iter, dir = pcall(require("hs.fs").dir, STATUS_DIR)
    if not iter then return end

    for file in dir do
        if file:match("%.json$") then
            local path = STATUS_DIR .. "/" .. file
            local data = hs.json.read(path)
            if data and data.updated_at then
                local age = now - data.updated_at
                if age <= STALE_THRESHOLD and data.sessions then
                    for _, s in ipairs(data.sessions) do
                        table.insert(sessions, s)
                    end
                    -- Use the pre-computed counts from the plugin
                    counts.active = counts.active + (data.counts and data.counts.active or 0)
                    counts.waiting = counts.waiting + (data.counts and data.counts.waiting or 0)
                    counts.done = counts.done + (data.counts and data.counts.done or 0)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Canvas rendering
---------------------------------------------------------------------------

local function screenTopRight()
    local screen = hs.screen.mainScreen():frame()
    return screen.x + screen.w, screen.y
end

local function buildSummaryText()
    local parts = {}
    if counts.active > 0 then
        table.insert(parts, "\u{25CF} " .. counts.active)
    end
    if counts.waiting > 0 then
        table.insert(parts, "\u{23F8} " .. counts.waiting)
    end
    if counts.done > 0 then
        table.insert(parts, "\u{2713} " .. counts.done)
    end
    if #parts == 0 then
        return "0 active"
    end
    return table.concat(parts, "  ")
end

local function redraw()
    if not canvas then return end

    -- Determine dimensions
    local width = expanded and EXPANDED_WIDTH or PILL_WIDTH
    local height = HEADER_HEIGHT
    if expanded and #sessions > 0 then
        height = HEADER_HEIGHT + 1 + (#sessions * ROW_HEIGHT) + 6
    end

    -- Position: top-right corner
    local rx, ry = screenTopRight()
    canvas:frame({
        x = rx - width - OFFSET_X,
        y = ry + OFFSET_Y,
        w = width,
        h = height,
    })

    -- Clear and rebuild elements
    while canvas:elementCount() > 0 do
        canvas:removeElement(1)
    end

    -- Background
    canvas:appendElements({
        type = "rectangle",
        frame = { x = 0, y = 0, w = width, h = height },
        fillColor = BG_COLOR,
        roundedRectRadii = { xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS },
        strokeWidth = 0,
    })

    -- Summary text
    local summaryText = buildSummaryText()
    local summaryColor = (#sessions == 0) and MUTED_COLOR or TEXT_COLOR
    canvas:appendElements({
        type = "text",
        frame = { x = 12, y = 4, w = width - 24, h = HEADER_HEIGHT },
        text = hs.styledtext.new(summaryText, {
            font = FONT,
            color = summaryColor,
        }),
    })

    -- Expanded: separator + session rows
    if expanded and #sessions > 0 then
        local sep_y = HEADER_HEIGHT
        canvas:appendElements({
            type = "rectangle",
            frame = { x = 8, y = sep_y, w = width - 16, h = 1 },
            fillColor = SEPARATOR_COLOR,
            strokeWidth = 0,
        })

        for i, s in ipairs(sessions) do
            local row_y = sep_y + 4 + ((i - 1) * ROW_HEIGHT)

            -- Tab name (left, truncated)
            local name = s.tab_name or "?"
            if #name > 22 then
                name = name:sub(1, 20) .. "\u{2026}"
            end
            canvas:appendElements({
                type = "text",
                frame = { x = 12, y = row_y, w = width - 100, h = ROW_HEIGHT },
                text = hs.styledtext.new(name, {
                    font = FONT_SMALL,
                    color = TEXT_COLOR,
                }),
            })

            -- Icon + detail (right)
            local icon = s.icon or ""
            local detail = s.detail or ""
            local right_text = icon
            if detail ~= "" and detail ~= hs.json.encode(nil) then
                right_text = icon .. " " .. detail
            end
            local icon_color = ICON_COLORS[icon] or TEXT_COLOR
            canvas:appendElements({
                type = "text",
                frame = { x = width - 100, y = row_y, w = 88, h = ROW_HEIGHT },
                text = hs.styledtext.new(right_text, {
                    font = FONT_SMALL,
                    color = icon_color,
                    paragraphStyle = { alignment = "right" },
                }),
            })
        end
    end

    if visible then
        canvas:show()
    else
        canvas:hide()
    end
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function onFileChange(paths, flagTables)
    loadSessions()
    redraw()
end

local function onClick()
    expanded = not expanded
    loadSessions()
    redraw()
end

local function toggleVisibility()
    visible = not visible
    if visible then
        loadSessions()
        redraw()
        canvas:show()
    else
        canvas:hide()
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function M.start()
    -- Ensure status dir exists
    os.execute("mkdir -p " .. STATUS_DIR)

    -- Create canvas
    local rx, ry = screenTopRight()
    canvas = hs.canvas.new({
        x = rx - PILL_WIDTH - OFFSET_X,
        y = ry + OFFSET_Y,
        w = PILL_WIDTH,
        h = HEADER_HEIGHT,
    })
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas:mouseCallback(function(c, msg)
        if msg == "mouseUp" then onClick() end
    end)

    -- Load initial data and draw
    loadSessions()
    redraw()

    -- Watch for file changes (FSEvents — no polling)
    pathwatcher = hs.pathwatcher.new(STATUS_DIR, onFileChange)
    pathwatcher:start()

    -- Bind hotkey: Ctrl+Option+C
    hs.hotkey.bind({ "ctrl", "alt" }, "c", toggleVisibility)
end

function M.stop()
    if pathwatcher then pathwatcher:stop() end
    if canvas then canvas:delete() end
    canvas = nil
    pathwatcher = nil
end

-- Auto-start
M.start()

return M
