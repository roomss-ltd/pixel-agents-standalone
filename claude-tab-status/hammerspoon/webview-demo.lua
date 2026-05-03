-- webview-demo.lua - DEMO ONLY isolated Hammerspoon webview prototype.
-- Visual reference only; not production code. Production lives in
-- claude-status-webview.lua and is selected by claude-status-loader.lua.
-- Load with:
--   hs -c 'dofile("/Users/cr1g/Projects/own/pixel-agents-standalone/claude-tab-status/hammerspoon/webview-demo.lua").start()'

local M = {}

local webview = nil

local function screenBottomRight()
    local f = hs.screen.mainScreen():frame()
    return f.x + f.w, f.y + f.h
end

local html = [[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  :root {
    color-scheme: dark;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    font-size: 14px;
  }

  * { box-sizing: border-box; }

  html,
  body {
    width: 100%;
    height: 100%;
    margin: 0;
    background: transparent;
    overflow: hidden;
  }

  body {
    display: grid;
    place-items: end;
    padding: 12px;
  }

  .widget {
    width: 300px;
    border: 1px solid rgba(170, 173, 195, 0.58);
    border-radius: 14px;
    background: rgba(23, 23, 34, 0.94);
    box-shadow: 0 18px 48px rgba(0, 0, 0, 0.34);
    color: rgba(255, 255, 255, 0.9);
    overflow: hidden;
  }

  .header {
    height: 34px;
    display: grid;
    grid-template-columns: 32px 1fr 34px;
    align-items: center;
    padding: 0 8px;
  }

  .spinner { color: rgb(121, 174, 255); font-weight: 700; }

  .counts {
    display: flex;
    justify-content: center;
    gap: 14px;
    font-weight: 700;
  }

  .count.active { color: rgb(121, 174, 255); }
  .count.done { color: rgb(137, 219, 147); }

  .header-button {
    width: 26px;
    height: 24px;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.11);
    color: white;
    font: inherit;
    font-weight: 800;
    cursor: pointer;
  }

  .rows {
    display: grid;
    gap: 6px;
    padding: 0 8px 8px;
  }

  .row {
    height: 30px;
    display: grid;
    grid-template-columns: 38px 1fr auto;
    align-items: center;
    gap: 8px;
    padding: 0 10px;
    border: 1px solid rgba(121, 174, 255, 0.26);
    border-radius: 8px;
    background: rgba(121, 174, 255, 0.12);
  }

  .row.waiting {
    border-color: rgba(255, 145, 92, 0.68);
    background: rgba(255, 145, 92, 0.20);
    animation: pulse 1.6s ease-in-out infinite;
  }

  .row.done {
    border-color: rgba(137, 219, 147, 0.18);
    background: rgba(137, 219, 147, 0.07);
    opacity: 0.72;
  }

  @keyframes pulse {
    0%, 100% { box-shadow: inset 0 0 0 1px rgba(255, 145, 92, 0.12); }
    50% { box-shadow: inset 0 0 0 1px rgba(255, 145, 92, 0.76), 0 0 16px rgba(255, 145, 92, 0.18); }
  }

  .badge {
    height: 20px;
    min-width: 28px;
    display: inline-grid;
    place-items: center;
    border-radius: 7px;
    background: rgba(121, 174, 255, 0.18);
    color: rgb(121, 174, 255);
    font-weight: 800;
  }

  .row.done .badge {
    background: rgba(137, 219, 147, 0.16);
    color: rgb(137, 219, 147);
  }

  .title {
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font-weight: 700;
  }

  .status {
    color: rgb(145, 190, 255);
    font-weight: 700;
  }

  .row.waiting .status { color: rgb(255, 170, 121); }
  .row.done .status { color: rgb(120, 196, 133); }

  .divider {
    height: 1px;
    margin: 8px 18px;
    border-top: 1px dashed rgba(255, 255, 255, 0.28);
  }

  .settings {
    display: grid;
    gap: 6px;
    padding: 8px;
    border-top: 1px solid rgba(255, 255, 255, 0.16);
  }

  .setting {
    height: 34px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 10px;
    border: 1px solid rgba(255, 255, 255, 0.10);
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.035);
    font-weight: 700;
  }

  .switch {
    position: relative;
    width: 42px;
    height: 24px;
  }

  .switch input {
    position: absolute;
    opacity: 0;
  }

  .track {
    position: absolute;
    inset: 0;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.18);
    transition: background 160ms ease;
  }

  .track::after {
    content: "";
    position: absolute;
    width: 18px;
    height: 18px;
    top: 3px;
    left: 3px;
    border-radius: 50%;
    background: white;
    transition: transform 160ms ease;
  }

  .switch input:checked + .track {
    background: rgb(123, 201, 140);
  }

  .switch input:checked + .track::after {
    transform: translateX(18px);
  }
</style>
</head>
<body>
  <main class="widget">
    <header class="header">
      <div class="spinner">⠙</div>
      <div class="counts">
        <span class="count active">● 2</span>
        <span class="count done">✓ 11</span>
      </div>
      <button class="header-button" onclick="document.body.classList.toggle('settings-open')">∨</button>
    </header>

    <section class="rows">
      <article class="row">
        <span class="badge">4</span>
        <span class="title">Zellij</span>
        <span class="status">● Bash</span>
      </article>
      <article class="row waiting">
        <span class="badge">10</span>
        <span class="title">Tab #16</span>
        <span class="status">⏸ Read</span>
      </article>
      <div class="divider"></div>
      <article class="row done">
        <span class="badge">5</span>
        <span class="title">Zellij</span>
        <span class="status">✓ 14s ago</span>
      </article>
      <article class="row done">
        <span class="badge">3.3</span>
        <span class="title">MTC</span>
        <span class="status">✓ 26m ago</span>
      </article>
    </section>

    <section class="settings">
      <label class="setting">Sounds <span class="switch"><input type="checkbox" checked><span class="track"></span></span></label>
      <label class="setting">Waiting reminders <span class="switch"><input type="checkbox" checked><span class="track"></span></span></label>
      <label class="setting">Waiting pulse <span class="switch"><input type="checkbox" checked><span class="track"></span></span></label>
      <label class="setting">Finish flash <span class="switch"><input type="checkbox" checked><span class="track"></span></span></label>
    </section>
  </main>
</body>
</html>
]]

function M.stop()
    if webview then
        webview:delete()
        webview = nil
    end
end

function M.start()
    M.stop()
    local rx, ry = screenBottomRight()
    webview = hs.webview.new({ x = rx - 330, y = ry - 390, w = 320, h = 380 })
    webview:windowStyle({ "borderless" })
    webview:level(hs.canvas.windowLevels.floating)
    webview:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    webview:transparent(true)
    webview:allowTextEntry(false)
    webview:html(html)
    webview:show()
    return webview
end

function M.toggle()
    if webview and webview:isVisible() then
        webview:hide()
    elseif webview then
        webview:show()
    else
        M.start()
    end
end

M.start()

return M
