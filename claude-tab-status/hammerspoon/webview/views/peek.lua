-- webview/views/peek.lua - Peek status view fragments.

local M = {}

function M.ticker()
    return [[
      <div class="peek-ticker" data-peek-ticker role="button" aria-label="Focus current agent" title="Focus current agent">
        <div class="peek-card" data-peek-card>
          <span class="peek-kind" data-peek-kind></span>
          <span class="peek-badge" data-peek-badge></span>
          <span class="peek-copy">
            <span class="peek-title" data-peek-title></span>
            <span class="peek-detail" data-peek-detail></span>
          </span>
          <span class="peek-meta peek-stats" data-peek-meta></span>
        </div>
      </div>
      <div class="peek-active-stack" data-peek-active-stack></div>
      <div class="peek-queue-divider" data-peek-queue-divider><span class="peek-section-label">Recently active</span></div>
]]
end

function M.history()
    return [[
    <section class="peek-history" data-peek-history aria-label="Recent finished agents">
      <div class="peek-history-list" data-peek-history-list></div>
      <div class="peek-actions" data-peek-actions></div>
    </section>
]]
end

return M
