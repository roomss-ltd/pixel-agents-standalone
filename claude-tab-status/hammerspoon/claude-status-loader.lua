-- claude-status-loader.lua - Hammerspoon entrypoint for Claude status UI.
-- Defaults to the production webview renderer and keeps the canvas renderer as
-- a fallback for this iteration.
--
-- Hammerspoon init.lua example:
--   package.path = package.path .. ";/Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/hammerspoon/?.lua"
--   require("claude-status-loader").start()
--
-- To switch back to canvas:
--   hs.settings.set("claudeStatus.renderer", "canvas")
--   hs.reload()

local M = {}

local STATUS_RENDERER = "webview"
local RENDERER_SETTINGS_KEY = "claudeStatus.renderer"

local RENDERERS = {
    webview = "claude-status-webview",
    canvas = "claude-status",
}

local rendererModule = nil
local rendererName = nil

local function configuredRenderer()
    local configured = hs.settings.get(RENDERER_SETTINGS_KEY)
    if configured == "webview" or configured == "canvas" then
        return configured
    end
    return STATUS_RENDERER
end

local function loadRenderer()
    rendererName = configuredRenderer()
    local moduleName = RENDERERS[rendererName]
    if not moduleName then
        rendererName = STATUS_RENDERER
        moduleName = RENDERERS[rendererName]
    end
    rendererModule = require(moduleName)
    return rendererModule
end

function M.start()
    local renderer = loadRenderer()
    if renderer and renderer.start then renderer.start() end
end

function M.stop()
    if rendererModule and rendererModule.stop then rendererModule.stop() end
    rendererModule = nil
    rendererName = nil
end

function M.toggle()
    local renderer = rendererModule or loadRenderer()
    if renderer and renderer.toggle then renderer.toggle() end
end

function M.renderer()
    return rendererName or configuredRenderer()
end

function M.usingCanvasFallback()
    rendererName = rendererName or configuredRenderer()
    return rendererName == "canvas"
end

return M
