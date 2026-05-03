-- webview/styles.lua - CSS sections for the Hammerspoon webview renderer.

local M = {}

function M.css()
    return [[
    :root {
      color-scheme: dark;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: transparent;
      --panel-bg: rgba(23, 23, 34, 0.94);
      --panel-border: rgba(128, 128, 148, 0.55);
      --panel-inner-border: rgba(255, 255, 255, 0.04);
      --panel-radius: 12px;
      --text-strong: rgba(255, 255, 255, 0.88);
      --text-muted: rgba(255, 255, 255, 0.35);
      --active-blue: rgb(115, 166, 255);
      --completed-green: rgb(115, 210, 128);
      --waiting-orange: rgb(255, 140, 89);
      --active-row-height: 28px;
      --completed-row-height: 22px;
      --row-gap: 3px;
      --badge-active-bg: rgba(115, 166, 255, 0.15);
      --badge-completed-bg: rgba(115, 210, 128, 0.15);
    }

    * { box-sizing: border-box; }

    html,
    body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: transparent;
    }

    body {
      display: grid;
      place-items: start;
      padding: 0;
      color: var(--text-strong);
      -webkit-user-select: none;
      user-select: none;
    }

    .widget {
      position: relative;
      width: 300px;
      max-height: 700px;
      overflow: visible;
      border: 1.5px solid var(--panel-border);
      border-radius: var(--panel-radius);
      background: var(--panel-bg);
      box-shadow: inset 0 0 0 1px var(--panel-inner-border);
    }

    .widget-flash {
      pointer-events: none;
      position: absolute;
      inset: 0;
      z-index: 5;
      opacity: 0;
      background: rgba(255, 255, 255, 0.72);
    }

    .icon-template {
      display: none;
    }

    .widget.widget-flashing .widget-flash {
      animation: widgetFlash 1.5s ease-out both;
    }

    .widget:not(.expanded) { width: 188px; }

    .widget.peek {
      width: 326px;
      min-height: 64px;
      transition: min-height 180ms cubic-bezier(0.2, 0.8, 0.2, 1);
    }

    .widget.peek.peek-hovering {
      min-height: 64px;
    }

    .widget:not(.expanded) .rows {
      display: none;
    }

    .widget:not(.peek) .peek-history {
      display: none;
    }

    .widget:not(.peek) .peek-ticker,
    .widget:not(.peek) .peek-active-stack,
    .widget:not(.peek) .peek-queue-divider {
      display: none;
    }

    .widget:not(.expanded) .more-toggle {
      display: none;
    }

    .widget:not(.expanded) .collapse-toggle {
      display: none;
    }

    .compact-mode-toggle {
      display: none;
      z-index: 4;
      opacity: 0.72;
      transition: opacity 120ms ease;
    }

    .widget.peek .peek-minimize-toggle {
      display: grid;
    }

    .widget.peek:not(.peek-hovering) .peek-minimize-toggle {
      opacity: 0;
      pointer-events: none;
    }

    .widget:not(.peek):not(.expanded) .mini-enlarge-toggle {
      display: grid;
    }

    .widget.compact .mini-enlarge-toggle {
      position: static;
      inset: auto;
      grid-row: 1;
      grid-column: 3;
      justify-self: end;
      align-self: center;
      width: 26px;
      height: 26px;
      min-width: 26px;
      min-height: 26px;
      box-sizing: border-box;
      border: 0.5px solid transparent;
      background: transparent;
      color: rgba(255, 255, 255, 0.62);
      opacity: 0.78;
      pointer-events: auto;
    }

    .widget.compact .mini-enlarge-toggle:hover {
      border-color: rgba(115, 166, 255, 0.20);
      background: rgba(115, 166, 255, 0.08);
      color: rgba(255, 255, 255, 0.78);
      opacity: 0.95;
    }

    .widget.compact .mini-enlarge-toggle .maximize-icon {
      width: 15px;
      height: 15px;
    }

    .widget.compact .mini-enlarge-toggle .maximize-icon svg {
      width: 15px;
      height: 15px;
    }

    .widget.compact .header {
      grid-template-columns: 24px 1fr 28px;
      padding: 0 10px;
      column-gap: 8px;
    }

    .widget.compact .loader-slot {
      grid-column: 1;
    }

    .widget.compact .header-counts {
      grid-column: 2;
      justify-self: center;
      gap: 8px;
      max-width: 100%;
      overflow: hidden;
    }

    .compact-mode-toggle:hover {
      opacity: 0.95;
    }

    /* Header */
    .header {
      height: 30px;
      display: grid;
      grid-template-columns: 24px minmax(0, 1fr) 24px;
      align-items: center;
      padding: 0 8px;
      gap: 2px;
    }

    .widget.peek .header {
      height: 64px;
      grid-template-columns: minmax(0, 1fr);
      align-content: center;
      padding: 6px 9px;
      gap: 0;
    }

    .widget.peek.peek-hovering .header,
    .widget.peek:focus-within .header {
      height: auto;
      align-content: start;
      gap: 6px;
    }

    .loader-slot {
      width: 24px;
      height: 24px;
      display: grid;
      place-items: center;
      color: var(--active-blue);
    }

    .widget:not(.compact) .loader-slot:not(.is-active)::before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--active-blue);
      box-shadow: 0 0 8px rgba(115, 166, 255, 0.9);
    }

    .widget.compact .loader-slot:not(.is-active) {
      color: rgba(190, 198, 214, 0.58);
    }

    .widget.compact .loader-slot:not(.is-active) .coffee-idle-icon {
      width: 14px;
      height: 14px;
      color: rgba(190, 198, 214, 0.62);
      transform: translateY(0.5px);
    }

    .widget.compact .loader-slot:not(.is-active) .coffee-idle-icon svg {
      width: 14px;
      height: 14px;
    }

    .loader-slot.is-active > * {
      filter: drop-shadow(0 0 6px rgba(115, 166, 255, 0.42));
    }

    .widget.peek .loader-slot,
    .widget.peek .header-counts {
      display: none;
    }

    .counts,
    .header-counts {
      grid-column: 2;
      justify-self: center;
      display: flex;
      justify-content: center;
      gap: 12px;
      font-size: 12px;
      font-weight: 600;
      white-space: nowrap;
      color: var(--text-strong);
    }

    .compact-count {
      height: 18px;
      min-width: 28px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 3px;
      padding: 1px 6px;
      border-radius: 999px;
      font-size: 10px;
      font-weight: 800;
      line-height: 16px;
      font-variant-numeric: tabular-nums;
      border: 0.5px solid rgba(255, 255, 255, 0.06);
      background: rgba(255, 255, 255, 0.035);
    }

    .active-count {
      color: var(--active-blue);
      background: rgba(115, 166, 255, 0.11);
      border-color: rgba(115, 166, 255, 0.18);
    }

    .completed-count {
      color: var(--completed-green);
      background: rgba(116, 204, 139, 0.10);
      border-color: rgba(116, 204, 139, 0.16);
    }

    .active-count .count-icon,
    .completed-count .count-icon,
    .count-value { color: currentColor; }

    .peek-ticker {
      grid-column: 2;
      min-width: 0;
      display: none;
      align-content: center;
      color: var(--text-strong);
    }

    .widget.peek .peek-ticker {
      grid-row: 1;
      grid-column: 1;
      display: grid;
    }

    .peek-card {
      min-width: 0;
      height: 46px;
      display: grid;
      grid-template-columns: 24px 34px minmax(0, 1fr) auto;
      align-items: center;
      column-gap: 10px;
      row-gap: 7px;
      padding: 5px 8px 5px 10px;
      border: 0.5px solid rgba(115, 166, 255, 0.12);
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.025);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.025);
      transition: opacity 320ms ease, transform 420ms cubic-bezier(0.16, 1, 0.3, 1);
    }

    .peek-ticker.is-rotating-out .peek-card {
      transform: translateY(-5px);
      opacity: 0;
    }

    .peek-ticker.is-rotating-in .peek-card {
      animation: peekPrimaryIn 420ms cubic-bezier(0.16, 1, 0.3, 1);
    }

    .peek-kind {
      width: 24px;
      height: 24px;
      display: grid;
      place-items: center;
      border-radius: 999px;
      color: var(--active-blue);
      background: rgba(115, 166, 255, 0.11);
      font-size: 10px;
      font-weight: 800;
      line-height: 24px;
      text-align: center;
    }

    .peek-kind.is-loader {
      background: transparent;
      color: var(--active-blue);
      overflow: visible;
    }

    .peek-kind.is-loader > * {
      max-width: 20px;
      max-height: 20px;
      filter: drop-shadow(0 0 6px rgba(115, 166, 255, 0.5));
    }

    .peek-badge {
      justify-self: start;
      min-width: 26px;
      height: 20px;
      margin-right: -6px;
      padding: 2px 6px;
      border-radius: 6px;
      color: rgba(115, 166, 255, 0.92);
      background: var(--badge-active-bg);
      font-size: 11px;
      font-weight: 800;
      line-height: 16px;
      text-align: center;
    }

    .peek-copy {
      min-width: 0;
      display: grid;
      gap: 1px;
    }

    .peek-line {
      min-width: 0;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .peek-title,
    .peek-detail {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .peek-title {
      font-size: 12px;
      font-weight: 700;
      color: rgba(255, 255, 255, 0.88);
    }

    .peek-detail {
      font-size: 10px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.48);
    }

    .peek-meta {
      justify-self: end;
      flex: 0 0 auto;
      font-size: 10px;
      font-weight: 600;
      color: rgba(255, 255, 255, 0.36);
      white-space: nowrap;
    }

    .peek-stats {
      display: inline-flex;
      align-items: center;
      justify-content: flex-end;
      gap: 4px;
    }

    .peek-stat {
      height: 18px;
      min-width: 28px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 3px;
      padding: 1px 6px;
      border-radius: 999px;
      font-size: 10px;
      font-weight: 800;
      line-height: 16px;
      font-variant-numeric: tabular-nums;
      border: 0.5px solid rgba(255, 255, 255, 0.06);
      background: rgba(255, 255, 255, 0.035);
    }

    .peek-stat-active {
      color: var(--active-blue);
      background: rgba(115, 166, 255, 0.11);
      border-color: rgba(115, 166, 255, 0.18);
    }

    .peek-stat-done {
      color: var(--completed-green);
      background: rgba(116, 204, 139, 0.10);
      border-color: rgba(116, 204, 139, 0.16);
    }

    .peek-stats.has-active .peek-stat-active {
      box-shadow: 0 0 10px rgba(115, 166, 255, 0.16);
    }

    .peek-ticker.waiting {
      filter: drop-shadow(0 0 10px rgba(255, 140, 89, 0.18));
    }

    .peek-ticker.waiting .peek-card {
      border-color: rgba(255, 140, 89, 0.22);
      background: rgba(255, 140, 89, 0.07);
    }

    .peek-ticker.waiting .peek-title,
    .peek-ticker.waiting .peek-detail {
      color: var(--waiting-orange);
    }

    .peek-ticker.waiting .peek-kind,
    .peek-ticker.waiting .peek-badge {
      color: var(--waiting-orange);
      background: rgba(255, 140, 89, 0.14);
    }

    .peek-ticker.finished .peek-title {
      color: var(--completed-green);
    }

    .peek-ticker.finished .peek-kind,
    .peek-ticker.finished .peek-badge {
      color: var(--completed-green);
      background: var(--badge-completed-bg);
    }

    .peek-ticker.idle .peek-card {
      grid-template-columns: 18px minmax(0, 1fr);
      border-color: rgba(255, 255, 255, 0.08);
      background: rgba(255, 255, 255, 0.022);
    }

    .peek-ticker.idle .peek-copy {
      grid-column: 2;
      grid-row: 1;
    }

    .peek-ticker.idle .peek-meta {
      display: none;
    }

    .peek-ticker.idle .peek-kind {
      grid-column: 1;
      grid-row: 1;
      color: rgba(115, 166, 255, 0.7);
      background: rgba(115, 166, 255, 0.08);
      box-shadow: 0 0 14px rgba(115, 166, 255, 0.12);
    }

    .peek-ticker.idle .peek-badge {
      display: none;
    }

    .peek-ticker.idle .peek-title {
      color: rgba(255, 255, 255, 0.72);
    }

    .peek-ticker.idle .peek-detail {
      color: rgba(255, 255, 255, 0.38);
    }

    .peek-active-stack {
      display: grid;
      gap: 4px;
      max-height: 0;
      overflow: hidden;
      opacity: 0;
      transform: translateY(-4px);
      pointer-events: none;
      transition:
        max-height 180ms cubic-bezier(0.2, 0.8, 0.2, 1),
        opacity 140ms ease-out,
        transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1);
    }

    .widget.peek.peek-hovering .peek-active-stack,
    .widget.peek:focus-within .peek-active-stack {
      max-height: 96px;
      opacity: 1;
      transform: translateY(0);
      pointer-events: auto;
    }

    .widget.peek:not(.peek-hovering):not(:focus-within) .peek-active-stack,
    .widget.peek:not(.peek-hovering):not(:focus-within) .peek-queue-divider,
    .widget.peek:not(.peek-hovering):not(:focus-within) .peek-history {
      display: none;
    }

    .peek-active-stack:empty {
      display: none;
    }

    .peek-active-stack-row {
      width: 100%;
      min-width: 0;
      min-height: 25px;
      display: grid;
      grid-template-columns: 30px minmax(0, 1fr) auto;
      align-items: center;
      gap: 7px;
      padding: 3px 7px;
      border: 0.5px solid rgba(115, 166, 255, 0.14);
      border-radius: 7px;
      background: rgba(115, 166, 255, 0.055);
      color: var(--text-strong);
      font: inherit;
      text-align: left;
      cursor: pointer;
    }

    .peek-active-stack-row:hover {
      border-color: rgba(115, 166, 255, 0.28);
      background: rgba(115, 166, 255, 0.095);
    }

    .peek-active-stack-row.waiting {
      border-color: rgba(255, 140, 89, 0.20);
      background: rgba(255, 140, 89, 0.065);
    }

    .peek-active-stack-row.depth-2 {
      opacity: 0.92;
      transform: scale(0.985);
      transform-origin: center top;
    }

    .peek-active-stack-row.depth-3 {
      opacity: 0.82;
      transform: scale(0.97);
      transform-origin: center top;
    }

    .peek-active-stack-badge {
      justify-self: start;
      min-width: 24px;
      height: 18px;
      padding: 2px 5px;
      border-radius: 5px;
      color: rgba(115, 166, 255, 0.92);
      background: var(--badge-active-bg);
      font-size: 10px;
      font-weight: 800;
      line-height: 14px;
      text-align: center;
    }

    .peek-active-stack-title,
    .peek-active-stack-detail {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .peek-active-stack-title {
      font-size: 10px;
      font-weight: 700;
      color: rgba(255, 255, 255, 0.72);
    }

    .peek-active-stack-detail {
      justify-self: end;
      font-size: 9px;
      font-weight: 700;
      color: var(--active-blue);
    }

    .peek-active-stack-overflow {
      justify-self: center;
      padding: 1px 8px;
      border-radius: 999px;
      color: rgba(115, 166, 255, 0.78);
      background: rgba(115, 166, 255, 0.075);
      font-size: 9px;
      font-weight: 800;
    }

    .peek-queue-divider {
      height: 14px;
      max-height: 0;
      overflow: hidden;
      display: flex;
      align-items: center;
      gap: 7px;
      margin: 0 12px;
      border-top: 0;
      opacity: 0;
      transform: scaleX(0.84);
      pointer-events: none;
      transition: opacity 140ms ease, transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1), height 180ms cubic-bezier(0.2, 0.8, 0.2, 1);
    }

    .peek-queue-divider::before,
    .peek-queue-divider::after {
      content: "";
      flex: 1 1 auto;
      border-top: 1px dashed rgba(255, 255, 255, 0.18);
    }

    .peek-queue-divider.visible {
      max-height: 14px;
      opacity: 1;
      transform: scaleX(1);
    }

    .peek-section-label {
      display: inline-block;
      padding: 0 7px;
      background: var(--panel-bg);
      color: rgba(255, 255, 255, 0.34);
      font-size: 8.5px;
      font-weight: 700;
      line-height: 10px;
      letter-spacing: 0;
      text-transform: uppercase;
    }

    .widget.peek:not(.peek-hovering):not(:focus-within) .peek-queue-divider::before,
    .widget.peek:not(.peek-hovering):not(:focus-within) .peek-queue-divider::after {
      border-top-color: transparent;
    }

    .peek-history {
      display: grid;
      gap: 5px;
      max-height: 0;
      overflow: hidden;
      padding: 0 9px;
      opacity: 0;
      transform: translateY(-6px);
      pointer-events: none;
      transition:
        max-height 180ms cubic-bezier(0.2, 0.8, 0.2, 1),
        opacity 140ms ease-out,
        transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1),
        padding-bottom 180ms cubic-bezier(0.2, 0.8, 0.2, 1);
    }

    .widget.peek.peek-hovering .peek-history,
    .widget.peek:focus-within .peek-history {
      max-height: 320px;
      padding-bottom: 9px;
      opacity: 1;
      transform: translateY(0);
      pointer-events: auto;
    }

    .peek-history-list {
      display: grid;
      gap: 4px;
      max-height: 244px;
      overflow-y: auto;
    }

    .peek-history-row {
      width: 100%;
      min-width: 0;
      min-height: 25px;
      display: grid;
      grid-template-columns: 30px minmax(0, 1fr) max-content;
      align-items: center;
      gap: 7px;
      padding: 3px 7px;
      border: 0.5px solid rgba(115, 210, 128, 0.14);
      border-radius: 7px;
      background: rgba(115, 210, 128, 0.06);
      color: var(--text-strong);
      font: inherit;
      text-align: left;
      cursor: pointer;
    }

    .peek-history-row:hover {
      border-color: rgba(115, 210, 128, 0.26);
      background: rgba(115, 210, 128, 0.10);
    }

    .peek-history-badge {
      justify-self: start;
      min-width: 24px;
      height: 18px;
      padding: 2px 5px;
      border-radius: 5px;
      color: var(--completed-green);
      background: var(--badge-completed-bg);
      font-size: 10px;
      font-weight: 800;
      line-height: 14px;
      text-align: center;
      box-shadow: inset 0 0 0 1px rgba(115, 210, 128, 0.18);
    }

    .peek-history-copy {
      min-width: 0;
      display: grid;
      gap: 1px;
    }

    .peek-history-title,
    .peek-history-detail {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .peek-history-title {
      font-size: 10.5px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.76);
    }

    .peek-history-status {
      justify-self: end;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 10px;
      font-weight: 600;
      font-variant-numeric: tabular-nums;
      color: rgba(115, 210, 128, 0.72);
    }

    .peek-history-detail,
    .peek-history-empty {
      font-size: 9px;
      font-weight: 600;
      color: rgba(255, 255, 255, 0.36);
    }

    .peek-history-empty {
      padding: 3px 7px;
    }

    .peek-history-older-divider {
      height: 14px;
      display: flex;
      align-items: center;
      gap: 7px;
      margin: 0 12px;
      border-top: 0;
      text-align: center;
      opacity: 0.62;
    }

    .peek-history-older-divider::before,
    .peek-history-older-divider::after {
      content: "";
      flex: 1 1 auto;
      border-top: 1px dashed rgba(255, 255, 255, 0.18);
    }

    .peek-history-older-toggle-shell {
      grid-column: 2;
      justify-self: center;
      display: grid;
      justify-items: center;
      align-items: center;
      min-height: 24px;
    }

    .peek-history-row.older-finished {
      opacity: 0.78;
    }

    .peek-history-row.older-finished:hover {
      opacity: 0.92;
    }

    .peek-actions {
      display: grid;
      grid-template-columns: 28px minmax(0, 1fr) 28px 28px;
      align-items: center;
      gap: 6px;
      min-height: 24px;
    }

    .peek-options-toggle {
      grid-column: 1;
      justify-self: start;
    }

    .peek-pin-toggle {
      grid-column: 3;
      justify-self: end;
    }

    .peek-minimize-toggle {
      grid-column: 4;
      justify-self: end;
    }

    .peek-action-button {
      height: 22px;
      width: 24px;
      display: grid;
      place-items: center;
      padding: 0;
      border: 0.5px solid rgba(115, 166, 255, 0.22);
      border-radius: 7px;
      background: rgba(115, 166, 255, 0.08);
      color: rgba(255, 255, 255, 0.74);
      cursor: pointer;
      opacity: 0.76;
      transition: opacity 120ms ease, color 120ms ease, background 120ms ease, border-color 120ms ease;
    }

    .peek-action-button:hover {
      opacity: 1;
      color: var(--text-strong);
      background: rgba(115, 166, 255, 0.14);
    }

    .peek-action-button.is-pinned {
      opacity: 1;
      color: var(--active-blue);
      border-color: rgba(115, 166, 255, 0.36);
      background: rgba(115, 166, 255, 0.16);
    }

    .header-icon-button {
      border: 1px solid transparent;
      border-radius: 6px;
      background: transparent;
      color: rgba(255, 255, 255, 0.82);
      font: inherit;
      line-height: 1;
      cursor: default;
    }

    .header-icon-button {
      position: relative;
      width: 22px;
      height: 20px;
      padding: 0;
      display: grid;
      place-items: center;
      background: transparent;
      color: rgba(255, 255, 255, 0.66);
      transition: opacity 120ms ease, color 120ms ease, background 120ms ease, border-color 120ms ease;
    }

    .header-icon-button:hover {
      background: rgba(255, 255, 255, 0.055);
      border-color: rgba(255, 255, 255, 0.10);
      color: rgba(255, 255, 255, 0.86);
    }

    .header-icon-button.compact-mode-toggle {
      display: none;
      width: 26px;
      height: 26px;
      min-width: 26px;
      min-height: 26px;
      z-index: 4;
      opacity: 0.72;
    }

    .header-icon-button.collapse-toggle {
      display: none;
    }

    .widget.peek .peek-minimize-toggle {
      display: grid;
    }

    .widget.peek:not(.peek-hovering) .peek-minimize-toggle {
      opacity: 0;
      pointer-events: none;
    }

    .widget.expanded .compact-mode-toggle {
      display: none;
    }

    .widget.expanded .collapse-toggle {
      display: grid;
    }

    .control-icon {
      display: grid;
      place-items: center;
      pointer-events: none;
    }

    .control-icon svg {
      width: 16px;
      height: 16px;
    }

    .more-toggle {
      opacity: 0.55;
    }

    .collapse-toggle {
      grid-column: 3;
      justify-self: end;
      opacity: 0.55;
    }

    .header:hover .collapse-toggle,
    .collapse-toggle:hover {
      opacity: 0.95;
    }

    .bottom-actions:hover .more-toggle,
    .more-toggle:hover {
      opacity: 0.95;
    }

    /* Rows */
    .rows {
      display: grid;
      gap: var(--row-gap);
      padding: 0 8px 10px;
      overflow: visible;
    }

    .divider {
      height: 16px;
      margin: 0 10px;
      border-top: 1px dashed rgba(255, 255, 255, 0.50);
      transform: translateY(8px);
      opacity: 0.74;
    }

    .row {
      height: var(--active-row-height);
      display: grid;
      grid-template-columns: 34px minmax(0, 1fr) max-content;
      align-items: center;
      gap: 6px;
      border: 0.5px solid rgba(255, 255, 255, 0.08);
      border-radius: 6px;
      padding: 0 5px 0 6px;
      background: rgba(255, 255, 255, 0.025);
    }

    .row.active-row {
      border-color: rgba(115, 166, 255, 0.25);
      background: rgba(115, 166, 255, 0.12);
    }

    .row.processing-neon,
    .peek-ticker.working .peek-card {
      position: relative;
      overflow: visible;
      border-color: rgba(139, 184, 255, 0.52);
      box-shadow:
        inset 0 1px 0 rgba(255, 255, 255, 0.035),
        0 0 10px rgba(115, 166, 255, 0.22),
        0 0 18px rgba(70, 206, 255, 0.10);
    }

    .row.processing-neon > *,
    .peek-ticker.working .peek-card > * {
      position: relative;
      z-index: 2;
    }

    .row.waiting-row {
      border-color: rgba(255, 140, 89, 0.25);
      background: rgba(255, 140, 89, 0.12);
    }

    .row.completed-row {
      height: var(--completed-row-height);
      border-color: rgba(115, 210, 128, 0.12);
      background: rgba(115, 210, 128, 0.06);
      padding-right: 7px;
    }

    .waiting-pulse-enabled .row.waiting-row,
    .waiting-pulse-enabled .row.waiting {
      animation: waitingPulse 1.6s ease-in-out infinite;
    }

    .row.completion-highlight {
      background: rgba(255, 255, 255, 0.92);
      color: rgba(17, 17, 24, 0.96);
      border-color: rgba(255, 255, 255, 0.95);
    }

    .row.completion-highlight .title,
    .row.completion-highlight .status {
      color: rgba(17, 17, 24, 0.96);
      background: transparent;
    }

    .row.completion-highlight .badge {
      color: rgba(17, 17, 24, 0.96);
      background: rgba(17, 17, 24, 0.08);
    }

    .badge,
    .tab-badge {
      justify-self: start;
      min-width: 22px;
      height: 18px;
      padding: 2px 5px;
      border-radius: 5px;
      color: rgba(115, 166, 255, 0.85);
      background: var(--badge-active-bg);
      box-shadow: inset 0 0 0 1px rgba(115, 166, 255, 0.22);
      font-size: 10px;
      font-weight: 700;
      line-height: 14px;
      text-align: center;
    }

    .completed-row .tab-badge {
      min-width: 20px;
      height: 16px;
      border-radius: 4px;
      color: rgba(115, 210, 128, 0.85);
      background: var(--badge-completed-bg);
      box-shadow: inset 0 0 0 1px rgba(115, 210, 128, 0.18);
      line-height: 12px;
    }

    .active-row .tab-badge,
    .waiting-row .tab-badge {
      box-shadow: inset 0 0 0 1px rgba(115, 166, 255, 0.22);
    }

    .row-main {
      min-width: 0;
    }

    .title {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 12px;
      font-weight: 500;
      color: var(--text-strong);
    }

    .completed-row .title {
      font-size: 11px;
      font-weight: 600;
      color: rgba(255, 255, 255, 0.65);
    }

    .detail {
      display: none;
    }

    .status {
      font-size: 10px;
      font-weight: 500;
      color: var(--active-blue);
      text-align: right;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      background: transparent;
    }

    .waiting-row .status { color: var(--waiting-orange); }
    .completed-row .status {
      justify-self: end;
      font-size: 10px;
      font-variant-numeric: tabular-nums;
      color: rgba(115, 210, 128, 0.65);
    }

    .older-finished-divider {
      opacity: 0.46;
    }

    .older-finished-toggle-shell {
      height: var(--completed-row-height);
      display: grid;
      justify-items: center;
      align-items: center;
    }

    .older-finished-toggle {
      width: 150px;
      height: 22px;
      display: grid;
      grid-template-columns: auto auto;
      justify-content: center;
      align-items: center;
      gap: 8px;
      margin: 0;
      padding: 0 10px;
      border: 1px solid rgba(115, 210, 128, 0.10);
      border-radius: 999px;
      background: rgba(115, 210, 128, 0.035);
      color: rgba(255, 255, 255, 0.48);
      font: inherit;
      font-size: 11px;
      font-weight: 600;
      text-align: center;
    }

    .older-finished-toggle:hover,
    .older-finished-toggle[aria-expanded="true"] {
      border-color: rgba(115, 210, 128, 0.18);
      background: rgba(115, 210, 128, 0.055);
      color: rgba(255, 255, 255, 0.62);
    }

    .older-finished-count {
      color: rgba(115, 210, 128, 0.72);
    }

    .older-finished-row {
      opacity: 0.82;
    }

    .bottom-actions {
      height: 26px;
      display: grid;
      grid-template-columns: 24px minmax(0, 1fr) 24px;
      align-items: center;
      gap: 4px;
    }

    .bottom-actions-left {
      min-width: 0;
    }

    .bottom-actions-center {
      display: grid;
      justify-items: center;
      align-items: center;
    }

    .bottom-options-toggle {
      grid-column: 3;
      justify-self: end;
      opacity: 0.42;
    }

    .bottom-options-toggle:hover {
      opacity: 0.92;
    }

    .empty {
      padding: 12px 6px 14px;
      text-align: center;
      font-size: 11px;
      color: rgba(255, 255, 255, 0.42);
    }

    /* Settings */
    .settings-panel {
      width: 220px;
      border: 1.5px solid var(--panel-border);
      border-radius: var(--panel-radius);
      background: var(--panel-bg);
      box-shadow: inset 0 0 0 1px var(--panel-inner-border);
      overflow: hidden;
    }

    .settings-panel-header {
      height: 30px;
      display: grid;
      grid-template-columns: 1fr;
      align-items: center;
      padding: 0 8px 0 10px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    }

    .settings-panel-title {
      font-size: 11px;
      font-weight: 600;
      color: rgba(255, 255, 255, 0.76);
    }

    .settings {
      display: grid;
      padding: 8px;
      gap: 6px;
    }

    .setting {
      display: grid;
      grid-template-columns: 1fr 34px;
      align-items: center;
      gap: 8px;
      height: 28px;
      font-size: 11px;
      color: rgba(255, 255, 255, 0.74);
    }

    .switch {
      position: relative;
      width: 30px;
      height: 18px;
    }

    .switch input {
      position: absolute;
      opacity: 0;
      pointer-events: none;
    }

    .track {
      position: absolute;
      inset: 0;
      border-radius: 9px;
      background: rgba(255, 255, 255, 0.16);
    }

    .track::after {
      content: "";
      position: absolute;
      top: 2px;
      left: 2px;
      width: 14px;
      height: 14px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.9);
      transition: transform 140ms ease;
    }

    .switch input:checked + .track { background: rgba(115, 166, 255, 0.58); }
    .switch input:checked + .track::after { transform: translateX(12px); }

    /* Collapsed events */
    .event-panel {
      width: 244px;
      display: grid;
      gap: 3px;
      padding: 4px;
      border: 1.5px solid var(--panel-border);
      border-radius: var(--panel-radius);
      background: var(--panel-bg);
      box-shadow: inset 0 0 0 1px var(--panel-inner-border), 0 8px 20px rgba(0, 0, 0, 0.18);
      overflow: hidden;
    }

    .event-row {
      position: relative;
      min-height: 32px;
      display: grid;
      grid-template-columns: 30px minmax(0, 1fr) 18px 22px;
      align-items: center;
      gap: 6px;
      padding: 4px 4px 4px 6px;
      border: 0.5px solid rgba(255, 255, 255, 0.07);
      border-radius: 7px;
      background: rgba(255, 255, 255, 0.035);
      color: var(--text-strong);
      overflow: hidden;
    }

    .event-row.finished {
      border-color: rgba(115, 210, 128, 0.16);
      background: rgba(115, 210, 128, 0.075);
    }

    .event-row.waiting {
      border-color: rgba(255, 140, 89, 0.20);
      background: rgba(255, 140, 89, 0.10);
      animation: waitingPulse 1.8s ease-in-out infinite;
    }

    .event-badge {
      justify-self: start;
      min-width: 22px;
      height: 18px;
      padding: 2px 5px;
      border-radius: 5px;
      color: rgba(115, 210, 128, 0.86);
      background: var(--badge-completed-bg);
      font-size: 10px;
      font-weight: 700;
      line-height: 14px;
      text-align: center;
    }

    .event-row.waiting .event-badge {
      color: var(--waiting-orange);
      background: rgba(255, 140, 89, 0.15);
    }

    .event-copy {
      min-width: 0;
    }

    .event-title {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 11px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.86);
    }

    .event-detail {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 9.5px;
      color: rgba(255, 255, 255, 0.48);
    }

    .event-status {
      font-size: 13px;
      color: var(--completed-green);
      text-align: center;
    }

    .event-row.waiting .event-status {
      color: var(--waiting-orange);
    }

    .event-dismiss {
      width: 22px;
      height: 20px;
      padding: 0;
      border: 0.5px solid rgba(255, 255, 255, 0.16);
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.075);
      color: rgba(255, 255, 255, 0.54);
      opacity: 0.9;
      font-size: 12px;
      line-height: 18px;
    }

    .event-row:hover .event-dismiss {
      opacity: 1;
    }

    .event-dismiss:hover {
      color: rgba(255, 255, 255, 0.78);
      background: rgba(255, 255, 255, 0.10);
    }

    .event-overflow {
      height: 18px;
      display: grid;
      place-items: center;
      font-size: 10px;
      color: rgba(255, 255, 255, 0.48);
    }

    @keyframes waitingPulse {
      0%, 100% { box-shadow: 0 0 0 rgba(255, 150, 106, 0.0); }
      50% { box-shadow: 0 0 18px rgba(255, 150, 106, 0.42); }
    }

    @keyframes widgetFlash {
      0% { opacity: 0.85; }
      100% { opacity: 0; }
    }

    @keyframes peekPrimaryIn {
      0% {
        transform: translateY(5px);
        opacity: 0;
      }
      100% {
        transform: translateY(0);
        opacity: 1;
      }
    }

    @media (prefers-reduced-motion: reduce) {
      .widget.peek,
      .peek-active-stack,
      .peek-history {
        transition: none;
      }

      .peek-ticker.is-rotating-out .peek-card {
        transform: none;
        opacity: 1;
      }

      .peek-ticker.is-rotating-in .peek-card {
        animation: none;
      }

      .loader-slot.is-active > * {
        animation: none !important;
        filter: none;
      }

      .row.processing-neon,
      .peek-ticker.working .peek-card {
        animation: none !important;
      }
    }
]]
end

return M
