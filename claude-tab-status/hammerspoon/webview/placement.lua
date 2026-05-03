-- webview/placement.lua - anchor-aware frame placement for Hammerspoon webviews.

local M = {}

local DEFAULT_PADDING = 20
local DEFAULT_GAP = 8
local EDGE_SNAP = 90

local function number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function clamp(value, minValue, maxValue)
    if maxValue < minValue then return minValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function normalizeScreen(screenFrame)
    screenFrame = screenFrame or {}
    return {
        x = number(screenFrame.x, 0),
        y = number(screenFrame.y, 0),
        w = number(screenFrame.w or screenFrame.width, 0),
        h = number(screenFrame.h or screenFrame.height, 0),
    }
end

local function normalizeSize(size)
    size = size or {}
    return {
        w = number(size.w or size.width, 0),
        h = number(size.h or size.height, 0),
    }
end

function M.clampFrame(frame, screenFrame, padding)
    frame = frame or {}
    screenFrame = normalizeScreen(screenFrame)
    padding = number(padding, DEFAULT_PADDING)

    local width = number(frame.w or frame.width, 0)
    local height = number(frame.h or frame.height, 0)
    local minX = screenFrame.x + padding
    local minY = screenFrame.y + padding
    local maxX = screenFrame.x + screenFrame.w - padding - width
    local maxY = screenFrame.y + screenFrame.h - padding - height

    return {
        x = clamp(number(frame.x, minX), minX, maxX),
        y = clamp(number(frame.y, minY), minY, maxY),
        w = width,
        h = height,
    }
end

function M.frameForWidget(screenFrame, size, placementState, padding)
    screenFrame = normalizeScreen(screenFrame)
    local normalizedSize = normalizeSize(size)
    placementState = placementState or { kind = "top-right" }
    padding = number(padding, DEFAULT_PADDING)

    local width = normalizedSize.w
    local height = normalizedSize.h
    local kind = placementState.kind or "top-right"
    local frame

    if kind == "top-right" then
        frame = { x = screenFrame.x + screenFrame.w - padding - width, y = screenFrame.y + padding, w = width, h = height }
    elseif kind == "top-left" then
        frame = { x = screenFrame.x + padding, y = screenFrame.y + padding, w = width, h = height }
    elseif kind == "bottom-right" then
        frame = { x = screenFrame.x + screenFrame.w - padding - width, y = screenFrame.y + screenFrame.h - padding - height, w = width, h = height }
    elseif kind == "bottom-left" then
        frame = { x = screenFrame.x + padding, y = screenFrame.y + screenFrame.h - padding - height, w = width, h = height }
    elseif kind == "custom" then
        frame = { x = number(placementState.x, screenFrame.x + padding), y = number(placementState.y, screenFrame.y + padding), w = width, h = height }
    else
        frame = { x = screenFrame.x + screenFrame.w - padding - width, y = screenFrame.y + padding, w = width, h = height }
    end

    return M.clampFrame(frame, screenFrame, padding)
end

function M.inferAnchor(frame, screenFrame, padding)
    frame = frame or {}
    screenFrame = normalizeScreen(screenFrame)
    padding = number(padding, DEFAULT_PADDING)

    local nearest = {
        { kind = "top-right", distance = math.abs(number(frame.x, 0) - (screenFrame.x + screenFrame.w - padding - number(frame.w, 0))) + math.abs(number(frame.y, 0) - (screenFrame.y + padding)) },
        { kind = "top-left", distance = math.abs(number(frame.x, 0) - (screenFrame.x + padding)) + math.abs(number(frame.y, 0) - (screenFrame.y + padding)) },
        { kind = "bottom-right", distance = math.abs(number(frame.x, 0) - (screenFrame.x + screenFrame.w - padding - number(frame.w, 0))) + math.abs(number(frame.y, 0) - (screenFrame.y + screenFrame.h - padding - number(frame.h, 0))) },
        { kind = "bottom-left", distance = math.abs(number(frame.x, 0) - (screenFrame.x + padding)) + math.abs(number(frame.y, 0) - (screenFrame.y + screenFrame.h - padding - number(frame.h, 0))) },
    }

    table.sort(nearest, function(a, b) return a.distance < b.distance end)
    if nearest[1] and nearest[1].distance <= EDGE_SNAP then
        return { kind = nearest[1].kind }
    end

    return { kind = "custom", x = frame.x, y = frame.y }
end

local function fits(frame, screenFrame, padding)
    return frame.x >= screenFrame.x + padding
        and frame.y >= screenFrame.y + padding
        and frame.x + frame.w <= screenFrame.x + screenFrame.w - padding
        and frame.y + frame.h <= screenFrame.y + screenFrame.h - padding
end

local function candidateFrame(name, anchorFrame, width, height, screenFrame, padding, gap, clampCrossAxis)
    local x = anchorFrame.x
    local y = anchorFrame.y

    if name == "right" then
        x = anchorFrame.x + anchorFrame.w + gap
        y = anchorFrame.y
    elseif name == "left" then
        x = anchorFrame.x - gap - width
        y = anchorFrame.y
    elseif name == "below" then
        x = anchorFrame.x
        y = anchorFrame.y + anchorFrame.h + gap
    elseif name == "above" then
        x = anchorFrame.x
        y = anchorFrame.y - gap - height
    end

    if clampCrossAxis and (name == "below" or name == "above") then
        local centeredX = anchorFrame.x + ((anchorFrame.w - width) / 2)
        x = clamp(centeredX, screenFrame.x + padding, screenFrame.x + screenFrame.w - padding - width)
    elseif clampCrossAxis and (name == "left" or name == "right") then
        local centeredY = anchorFrame.y + ((anchorFrame.h - height) / 2)
        y = clamp(centeredY, screenFrame.y + padding, screenFrame.y + screenFrame.h - padding - height)
    end

    return { x = x, y = y, w = width, h = height }
end

function M.placePopover(screenFrame, anchorFrame, popoverSize, options)
    screenFrame = normalizeScreen(screenFrame)
    anchorFrame = anchorFrame or {}
    local normalizedSize = normalizeSize(popoverSize)
    options = options or {}
    local padding = number(options.padding, DEFAULT_PADDING)
    local gap = number(options.gap, DEFAULT_GAP)
    local width = normalizedSize.w
    local height = normalizedSize.h
    local order = options.order or { "right", "left", "below", "above" }
    local firstCandidate = nil

    for _, name in ipairs(order) do
        local candidate = { name = name, frame = candidateFrame(name, anchorFrame, width, height, screenFrame, padding, gap, options.clampCrossAxis == true) }
        if not firstCandidate then firstCandidate = candidate end
        local frame = candidate.frame
        if fits(frame, screenFrame, padding) then
            return frame, candidate.name
        end
    end

    firstCandidate = firstCandidate or { name = "right", frame = candidateFrame("right", anchorFrame, width, height, screenFrame, padding, gap, options.clampCrossAxis == true) }
    return M.clampFrame(firstCandidate.frame, screenFrame, padding), firstCandidate.name
end

return M
