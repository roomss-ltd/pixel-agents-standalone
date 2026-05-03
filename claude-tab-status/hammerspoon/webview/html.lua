-- webview/html.lua - HTML shell and JavaScript renderer for the status webview.

local icons = require("webview.icons")
local ldrs = require("webview.ldrs")
local sharedView = require("webview.views.shared")
local miniView = require("webview.views.mini")
local peekView = require("webview.views.peek")
local detailView = require("webview.views.detail")

local M = {}

function M.script(bridgeScheme)
    return ([[
    (function() {
      if (window.__claudeStatusRendererInstalled && typeof window.renderStatus === "function") return;
      var BRIDGE_SCHEME = "__BRIDGE_SCHEME__";
      var dragOrigin = null;
      var dragClickSuppressed = false;
      var VALID_SETTING_KEYS = { soundsEnabled: true, waitingReminderSound: true, waitingPulse: true, completionFlash: true, processingNeon: true, notificationsEnabled: true };
      var VALID_ACTION_TYPES = { "setting.toggle": true, "settings.toggle": true, "pin.toggle": true, "row.focus": true, "row.dismiss": true, "event.focus": true, "event.dismiss": true, "older.toggle": true, "drag.start": true, "drag.move": true, "drag.end": true, "expand.toggle": true, "expand.set": true, "peek.hover.set": true, "peek.pin.toggle": true, "compact.mode.set": true };
      var LOADER_VARIANTS = [
        { name: "dot-spinner", tag: "l-dot-spinner", speed: 0.9 },
        { name: "quantum", tag: "l-quantum", speed: 1.75 },
        { name: "cardio", tag: "l-cardio", stroke: 4, speed: 2 },
        { name: "trio", tag: "l-trio", speed: 1.3 },
        { name: "grid", tag: "l-grid", speed: 1.5 },
        { name: "chaotic-orbit", tag: "l-chaotic-orbit", speed: 1.5 },
        { name: "hourglass", tag: "l-hourglass", bgOpacity: 0.1, speed: 1.75 },
        { name: "metronome", tag: "l-metronome", speed: 1.6 },
        { name: "reuleaux", tag: "l-reuleaux", stroke: 5, strokeLength: 0.15, bgOpacity: 0.1, speed: 1.2 }
      ];
      var LOADER_ROTATE_INTERVAL_MS = 15000;
      var PEEK_ROTATE_INTERVAL_MS = 10000;
      var PEEK_PRIMARY_TRANSITION_MS = 420;
      var PEEK_ACTIVE_STACK_MAX_ITEMS = 3;
      var loaderVariantIndex = 0;
      var loaderTimer = null;
      var lastLoaderState = {};
      var peekItems = [];
      var peekIndex = 0;
      var peekSignature = "";
      var peekTimer = null;
      var lastPeekHeader = {};

      function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, function(ch) {
          return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[ch];
        });
      }

      function mergeSettings(settings) {
        settings = settings || {};
        if (!settings.values) return settings;
        var merged = {};
        var key;
        for (key in settings.values) {
          if (Object.prototype.hasOwnProperty.call(settings.values, key)) merged[key] = settings.values[key];
        }
        for (key in settings) {
          if (Object.prototype.hasOwnProperty.call(settings, key)) merged[key] = settings[key];
        }
        return merged;
      }

      function setClass(element, className, enabled) {
        if (!element) return;
        if (element.classList) {
          if (enabled) element.classList.add(className);
          else element.classList.remove(className);
          return;
        }
        var current = " " + (element.className || "") + " ";
        var token = " " + className + " ";
        if (enabled && current.indexOf(token) < 0) {
          element.className = (element.className ? element.className + " " : "") + className;
        } else if (!enabled && current.indexOf(token) >= 0) {
          element.className = current.replace(token, " ").replace(/^\s+|\s+$/g, "");
        }
      }

      function postAction(message) {
        if (!message || !VALID_ACTION_TYPES[message.type]) return;
        if (message.type === "setting.toggle" && !VALID_SETTING_KEYS[message.key]) return;
        window.location.href = BRIDGE_SCHEME + "://action?payload=" + encodeURIComponent(JSON.stringify(message));
      }

      function closestTarget(target, selector) {
        while (target && target !== document) {
          if (target.nodeType === 1) {
            var matches = target.matches || target.webkitMatchesSelector || target.msMatchesSelector;
            if (matches && matches.call(target, selector)) return target;
          }
          target = target.parentElement || target.parentNode;
        }
        return null;
      }

      function mergeSettings(settings) {
        settings = settings || {};
        if (!settings.values) return settings;
        var merged = {};
        var key;
        for (key in settings.values) {
          if (Object.prototype.hasOwnProperty.call(settings.values, key)) merged[key] = settings.values[key];
        }
        for (key in settings) {
          if (Object.prototype.hasOwnProperty.call(settings, key)) merged[key] = settings[key];
        }
        return merged;
      }

      function setClass(element, className, enabled) {
        if (!element) return;
        if (element.classList) {
          if (enabled) element.classList.add(className);
          else element.classList.remove(className);
          return;
        }
        var current = " " + (element.className || "") + " ";
        var token = " " + className + " ";
        if (enabled && current.indexOf(token) < 0) {
          element.className = (element.className ? element.className + " " : "") + className;
        } else if (!enabled && current.indexOf(token) >= 0) {
          element.className = current.replace(token, " ").replace(/^\s+|\s+$/g, "");
        }
      }

      function postSettingToggle(key) {
        var message = { type: "setting.toggle", key: key };
        if (!VALID_SETTING_KEYS[message.key]) return;
        postAction(message);
      }

      function requestExpand() {
        var widget = document.querySelector(".widget");
        if (widget && widget.classList.contains("compact")) return false;
        if (widget && widget.classList.contains("peek")) return false;
        return false;
      }

      function handleWidgetHover(hovering, event) {
        if (dragOrigin) return;
        var widget = document.querySelector(".widget");
        if (!widget) return;
        var related = event && event.relatedTarget;
        if (widget && related && widget.contains(related)) return;
        if (widget.classList.contains("peek")) {
          postAction({ type: "peek.hover.set", hovering: hovering });
          return;
        }
        if (widget.classList.contains("compact")) return;
      }

      function renderCounts(counts) {
        counts = counts || {};
        renderHeader({ activeCount: counts.active, waitingCount: counts.waiting, completedCount: counts.done });
      }

      function reducedMotionEnabled() {
        return !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
      }

      function renderLoaderInto(slot, loader) {
        loader = loader || {};
        if (!slot) return;

        setClass(slot, "is-active", !!loader.active);
        if (!loader.active) {
          var widget = closestTarget(slot, ".widget");
          var idleIcon = document.getElementById("coffee-idle-icon-template");
          if (!loader.active && widget && widget.classList.contains("compact")) {
            slot.innerHTML = idleIcon ? idleIcon.innerHTML : "";
          } else {
            slot.innerHTML = "";
          }
          slot.removeAttribute("data-loader-variant");
          return;
        }

        var variant = LOADER_VARIANTS[loaderVariantIndex % LOADER_VARIANTS.length];
        var reducedMotion = reducedMotionEnabled();
        var element = slot.firstElementChild;
        if (!element || slot.getAttribute("data-loader-variant") !== variant.name) {
          slot.innerHTML = "";
          element = document.createElement(variant.tag);
          slot.appendChild(element);
          slot.setAttribute("data-loader-variant", variant.name);
        }
        element.setAttribute("size", String(loader.size || 18));
        element.setAttribute("speed", reducedMotion ? "0" : String(variant.speed || loader.speed || 1.75));
        element.setAttribute("color", loader.color || "var(--active-blue)");
        if (variant.stroke) element.setAttribute("stroke", String(variant.stroke));
        if (variant.strokeLength) element.setAttribute("stroke-length", String(variant.strokeLength));
        if (variant.bgOpacity) element.setAttribute("bg-opacity", String(variant.bgOpacity));
      }

      function renderLoader(loader) {
        loader = loader || {};
        lastLoaderState = loader;
        renderLoaderInto(document.querySelector("[data-loader-slot]"), loader);
      }

      if (!loaderTimer) {
        loaderTimer = setInterval(function() {
          loaderVariantIndex = (loaderVariantIndex + 1) % LOADER_VARIANTS.length;
          renderLoader(lastLoaderState);
          applyPeekItem(currentPeekItem(lastPeekHeader), lastPeekHeader);
        }, LOADER_ROTATE_INTERVAL_MS);
      }

      function peekItemSignature(items) {
        return (items || []).map(function(item) {
          return [item.kind, item._zj_session, item.pane_id, item.tab_num, item.event_id, item.title].join(":");
        }).join("|");
      }

      function currentPeekItem(header) {
        header = header || {};
        var peek = header.peek || {};
        peekItems = peek.items || [];
        if (!peekItems.length) return null;
        if (peek.pinned) peekIndex = 0;
        if (peekIndex >= peekItems.length) peekIndex = 0;
        return peekItems[peekIndex];
      }

      function peekKindLabel(kind) {
        if (kind === "waiting") return "!";
        if (kind === "finished") return "✓";
        return "●";
      }

      function renderPeekMeta(meta, header) {
        if (!meta) return;
        var compact = arguments.length > 2 && arguments[2] === true;
        header = header || {};
        var activeTotal = (header.activeCount || 0) + (header.waitingCount || 0);
        var doneTotal = header.completedCount || 0;
        setClass(meta, "has-active", activeTotal > 0);
        meta.setAttribute("title", String(activeTotal) + " active, " + String(doneTotal) + " done");
        if (compact && activeTotal < 1) {
          meta.innerHTML = "";
          return;
        }
        var parts = [];
        if (activeTotal > 0) {
          parts.push('<span class="peek-stat peek-stat-active" aria-label="' + String(activeTotal) + ' active">' +
            '<span class="peek-stat-icon" aria-hidden="true">&#9679;</span>' +
            '<span class="peek-stat-value">' + String(activeTotal) + '</span>' +
          '</span>');
        }
        if (doneTotal > 0) {
          parts.push('<span class="peek-stat peek-stat-done" aria-label="' + String(doneTotal) + ' done">' +
            '<span class="peek-stat-icon" aria-hidden="true">&#10003;</span>' +
            '<span class="peek-stat-value">' + String(doneTotal) + '</span>' +
          '</span>');
        }
        meta.innerHTML = parts.join("");
      }

      function clearPeekKind(kind) {
        if (!kind) return;
        setClass(kind, "is-loader", false);
        kind.removeAttribute("data-peek-kind-mode");
        kind.innerHTML = "";
        kind.removeAttribute("data-loader-variant");
      }

      function renderPeekLoader(kind, header) {
        if (!kind) return;
        if (kind.getAttribute("data-peek-kind-mode") !== "running") {
          kind.innerHTML = "";
          kind.removeAttribute("data-loader-variant");
          kind.setAttribute("data-peek-kind-mode", "running");
        }
        var sourceLoader = (header && header.loader) || {};
        var peekLoader = {
          active: true,
          size: 18,
          speed: sourceLoader.speed || 1.75,
          color: sourceLoader.color || "var(--active-blue)"
        };
        setClass(kind, "is-loader", true);
        renderLoaderInto(kind, peekLoader);
      }

      function renderPeekKind(kind, item, header) {
        if (!kind) return;
        if (item && item.kind === "running") {
          renderPeekLoader(kind, header);
          return;
        }
        clearPeekKind(kind);
        if (item && item.kind === "idle") {
          var idleIcon = document.getElementById("coffee-idle-icon-template");
          kind.innerHTML = idleIcon ? idleIcon.innerHTML : "";
          return;
        }
        kind.textContent = item ? peekKindLabel(item.kind) : "";
      }

      function renderPeekHistoryRow(item) {
        var row = document.createElement("button");
        row.type = "button";
        row.className = "peek-history-row " + (item && item.kind ? item.kind : "finished");
        row.setAttribute("data-pane-id", item && item.pane_id != null ? String(item.pane_id) : "");
        row.setAttribute("data-zj-session", item && item._zj_session ? item._zj_session : "");
        row.setAttribute("data-tab-num", item && item.tab_num != null ? String(item.tab_num) : "");
        row.setAttribute("data-event-id", item && item.event_id != null ? String(item.event_id) : "");
        row.innerHTML =
          '<span class="peek-history-badge">' + escapeHtml(item && item.display_label ? item.display_label : "") + '</span>' +
          '<span class="peek-history-copy">' +
            '<span class="peek-history-title">' + escapeHtml(item && item.title ? item.title : "Finished") + '</span>' +
            '<span class="peek-history-detail">' + escapeHtml(item && item.detail ? item.detail : "Click to focus") + '</span>' +
          '</span>';
        return row;
      }

      function renderPeekHistory(header) {
        header = header || {};
        var list = document.querySelector("[data-peek-history-list]");
        if (!list) return;
        var peek = header.peek || {};
        var history = peek.history || [];
        list.innerHTML = "";
        if (!history.length) {
          var empty = document.createElement("div");
          empty.className = "peek-history-empty";
          empty.textContent = "No recent finishes";
          list.appendChild(empty);
          return;
        }
        history.forEach(function(item) {
          list.appendChild(renderPeekHistoryRow(item));
        });
      }

      function activePeekItems(header) {
        var peek = (header && header.peek) || {};
        return (peek.items || []).filter(function(item) {
          return item && (item.kind === "running" || item.kind === "waiting");
        });
      }

      function orderedPeekItems(header) {
        var items = activePeekItems(header);
        if (!items.length) return [];
        if (peekIndex >= items.length) peekIndex = 0;
        return items.slice(peekIndex).concat(items.slice(0, peekIndex));
      }

      function renderPeekActiveStackRow(item, index) {
        var row = document.createElement("button");
        row.type = "button";
        row.className = "peek-active-stack-row depth-" + String(index + 1) + " " + (item && item.kind ? item.kind : "running");
        row.setAttribute("data-pane-id", item && item.pane_id != null ? String(item.pane_id) : "");
        row.setAttribute("data-zj-session", item && item._zj_session ? item._zj_session : "");
        row.setAttribute("data-tab-num", item && item.tab_num != null ? String(item.tab_num) : "");
        row.innerHTML =
          '<span class="peek-active-stack-badge">' + escapeHtml(item && item.display_label ? item.display_label : "") + '</span>' +
          '<span class="peek-active-stack-title">' + escapeHtml(item && item.title ? item.title : "Running") + '</span>' +
          '<span class="peek-active-stack-detail">' + escapeHtml(item && item.detail ? item.detail : "Running") + '</span>';
        return row;
      }

      function renderPeekActiveStack(header, primaryItem) {
        var stack = document.querySelector("[data-peek-active-stack]");
        if (!stack) return;
        var ordered = orderedPeekItems(header);
        var rest = ordered.filter(function(item) { return item !== primaryItem; });
        stack.innerHTML = "";
        rest.slice(0, PEEK_ACTIVE_STACK_MAX_ITEMS).forEach(function(item, index) {
          stack.appendChild(renderPeekActiveStackRow(item, index));
        });
        var overflow = Math.max(rest.length - PEEK_ACTIVE_STACK_MAX_ITEMS, 0);
        if (overflow > 0) {
          var more = document.createElement("div");
          more.className = "peek-active-stack-overflow";
          more.setAttribute("data-peek-active-stack-overflow", String(overflow));
          more.textContent = "+" + String(overflow) + " running";
          stack.appendChild(more);
        }
      }

      function renderPeekQueueDivider(header) {
        var divider = document.querySelector("[data-peek-queue-divider]");
        if (!divider) return;
        var hasQueue = activePeekItems(header).length > 1;
        var peek = (header && header.peek) || {};
        var hasHistory = (peek.history || []).length > 0;
        setClass(divider, "visible", hasQueue && hasHistory);
      }

      function applyPeekItem(item, header) {
        var ticker = document.querySelector("[data-peek-ticker]");
        if (!ticker) return;
        var card = document.querySelector("[data-peek-card]");
        var kind = document.querySelector("[data-peek-kind]");
        var badge = document.querySelector("[data-peek-badge]");
        var title = document.querySelector("[data-peek-title]");
        var detail = document.querySelector("[data-peek-detail]");
        var meta = document.querySelector("[data-peek-meta]");
        var isIdle = !!item && item.kind === "idle";
        ticker.setAttribute("data-pane-id", item && item.pane_id != null ? String(item.pane_id) : "");
        ticker.setAttribute("data-zj-session", item && item._zj_session ? item._zj_session : "");
        ticker.setAttribute("data-tab-num", item && item.tab_num != null ? String(item.tab_num) : "");
        ticker.setAttribute("data-event-id", item && item.event_id != null ? String(item.event_id) : "");
        setClass(ticker, "waiting", !!item && item.kind === "waiting");
        setClass(ticker, "working", !!item && item.kind === "running");
        setClass(ticker, "finished", !!item && item.kind === "finished");
        setClass(ticker, "idle", isIdle);
        var settings = window.__claudeStatusSettings || {};
        var widget = document.querySelector(".widget");
        var processingNeonEnabled = settings.processingNeon !== false && widget && widget.classList.contains("peek");
        if (card) {
          if (!processingNeonEnabled) setClass(card, "working", false);
        }
        renderPeekKind(kind, item, header);
        if (badge) badge.textContent = item ? (item.display_label || "") : "";
        if (title) title.textContent = item ? (item.title || "") : "";
        if (detail) detail.textContent = item ? (item.detail || "") : "";
        renderPeekMeta(meta, header, isIdle);
        renderPeekActiveStack(header, item);
        renderPeekQueueDivider(header);
      }

      function renderPeek(header) {
        header = header || {};
        lastPeekHeader = header;
        var peek = header.peek || {};
        var signature = peekItemSignature(peek.items || []);
        if (signature !== peekSignature) {
          peekSignature = signature;
          peekIndex = 0;
        }
        applyPeekItem(currentPeekItem(header), header);
        renderPeekHistory(header);
      }

      function rotatePeekPrimary() {
        var peek = (lastPeekHeader && lastPeekHeader.peek) || {};
        if (peek.hovering || peek.hoverPinned) return;
        if (!peek.active || !peekItems.length || peekItems.length < 2) return;
        var ticker = document.querySelector("[data-peek-ticker]");
        if (!ticker) return;
        setClass(ticker, "is-rotating-out", true);
        window.setTimeout(function() {
          peekIndex = (peekIndex + 1) % peekItems.length;
          setClass(ticker, "is-rotating-out", false);
          applyPeekItem(currentPeekItem(lastPeekHeader), lastPeekHeader);
          setClass(ticker, "is-rotating-in", true);
          window.setTimeout(function() {
            setClass(ticker, "is-rotating-in", false);
          }, PEEK_PRIMARY_TRANSITION_MS);
        }, PEEK_PRIMARY_TRANSITION_MS);
      }

      if (!peekTimer) {
        peekTimer = setInterval(function() {
          rotatePeekPrimary();
        }, PEEK_ROTATE_INTERVAL_MS);
      }

      function renderHeader(header) {
        header = header || {};
        var activeTotal = (header.activeCount || 0) + (header.waitingCount || 0);
        var activeValue = document.querySelector('[data-count="active"] .count-value');
        var completedValue = document.querySelector('[data-count="completed"] .count-value');
        if (activeValue) activeValue.textContent = String(activeTotal);
        if (completedValue) completedValue.textContent = String(header.completedCount || 0);
        renderLoader(header.loader || {});
        renderPeek(header);
        var expand = document.querySelector(".expand-toggle");
        if (expand) {
          expand.setAttribute("aria-expanded", header.expanded ? "true" : "false");
          setClass(expand, "is-expanded", !!header.expanded);
        }
      }

      function isProcessingActivity(activity) {
        activity = String(activity || "Init").toLowerCase();
        return activity === "thinking" || activity === "tool";
      }

      function rowClass(row, className) {
        var activity = String(row.activity || "Init").toLowerCase();
        var waitingClass = activity === "waiting" ? "waiting-row" : "";
        var processingClass = isProcessingActivity(activity) ? "processing-neon" : "";
        return ["row", className || "", waitingClass, processingClass, activity].join(" ");
      }

      function renderRows(rows, className) {
        var settings = window.__claudeStatusSettings || {};
        var widget = document.querySelector(".widget");
        var processingNeonEnabled = settings.processingNeon !== false && widget && widget.classList.contains("expanded");
        var neonAttached = false;
        return (rows || []).map(function(row) {
          var el = document.createElement("article");
          var activity = row.activity;
          var processingClass = processingNeonEnabled && isProcessingActivity(activity) && !neonAttached ? "processing-neon" : "";
          if (processingClass) neonAttached = true;
          el.className = rowClass(row, className).replace("processing-neon", processingClass);
          el.setAttribute("data-pane-id", String(row.pane_id != null ? row.pane_id : ""));
          el.setAttribute("data-zj-session", row._zj_session || "");
          el.setAttribute("data-tab-num", String(row.tab_num != null ? row.tab_num : ""));

          var flash = window.__claudeStatusFlash || {};
          var settings = window.__claudeStatusSettings || {};
          var flashRows = flash.rows || {};
          var flashInfo = flashRows[row._flash_id];
          if (flashInfo && settings.completionFlash) {
            setClass(el, "completion-highlight", true);
          }

          var label = document.createElement("div");
          label.className = "badge tab-badge";
          label.textContent = escapeHtml(row.display_label || row._display_num || row.tab_num || "");

          var body = document.createElement("div");
          body.className = "row-main";
          var title = document.createElement("div");
          title.className = "title";
          title.innerHTML = escapeHtml(row.tab_name || "");
          var detail = document.createElement("div");
          detail.className = "detail";
          detail.innerHTML = escapeHtml(row.detail || "");
          body.appendChild(title);
          body.appendChild(detail);

          var status = document.createElement("div");
          status.className = "status";
          var statusIcon = row.icon || "";
          var statusDetail = row.detail || "";
          var statusText = statusIcon + (statusDetail ? " " + statusDetail : " " + (row.activity || "Init"));
          status.innerHTML = escapeHtml(statusText);

          el.appendChild(label);
          el.appendChild(body);
          el.appendChild(status);
          return el;
        });
      }

      function renderSettings(settings, settingsItems) {
        var root = document.getElementById("settings");
        if (!root) return;
        root.innerHTML = "";
        (settingsItems || []).forEach(function(item) {
          var row = document.createElement("label");
          row.className = "setting";
          row.setAttribute("data-setting", item.key);
          row.textContent = item.label;
          var sw = document.createElement("span");
          sw.className = "switch";
          var input = document.createElement("input");
          input.type = "checkbox";
          input.checked = !!settings[item.key];
          var track = document.createElement("span");
          track.className = "track";
          sw.appendChild(input);
          sw.appendChild(track);
          row.appendChild(sw);
          row.addEventListener("click", function(event) {
            event.preventDefault();
            postSettingToggle(item.key);
          });
          root.appendChild(row);
        });
      }

      function renderOlderFinishedControl(state) {
        var older = state.olderFinished || {};
        if (!state.showOlderFinishedControl || !older.count) return null;
        var shell = document.createElement("div");
        shell.className = "older-finished-toggle-shell";
        var button = document.createElement("button");
        button.type = "button";
        button.className = "older-finished-toggle";
        button.setAttribute("data-action", "older.toggle");
        button.setAttribute("aria-expanded", older.expanded ? "true" : "false");
        button.setAttribute("title", older.expanded ? "Collapse" : "Show all");
        var label = document.createElement("span");
        label.className = "older-finished-label";
        label.textContent = older.expanded ? "Collapse" : "Show all";
        var count = document.createElement("span");
        count.className = "older-finished-count";
        count.textContent = String(older.count);
        button.appendChild(label);
        button.appendChild(count);
        shell.appendChild(button);
        return shell;
      }

      function createOptionsButton() {
        var options = document.createElement("button");
        options.type = "button";
        options.className = "header-icon-button more-toggle bottom-options-toggle";
        options.setAttribute("data-action", "settings.toggle");
        options.setAttribute("aria-label", "Open options");
        options.setAttribute("title", "Options");
        var icon = document.getElementById("settings-icon-template");
        options.innerHTML = icon ? icon.innerHTML : "";
        return options;
      }

      function createPeekActionButton(className, action, label, title, templateId, mode) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "peek-action-button " + className;
        button.setAttribute("data-action", action);
        if (mode) button.setAttribute("data-mode", mode);
        button.setAttribute("aria-label", label);
        button.setAttribute("title", title);
        var icon = document.getElementById(templateId);
        button.innerHTML = icon ? icon.innerHTML : "";
        return button;
      }

      function ensurePeekActionButton(peekActions, className, action, label, title, templateId, mode) {
        var button = peekActions.querySelector("." + className);
        if (!button) {
          button = createPeekActionButton(className, action, label, title, templateId, mode);
          peekActions.appendChild(button);
        }
        return button;
      }

      function renderPeekActions(state) {
        var peekActions = document.querySelector("[data-peek-actions]");
        if (!peekActions) return;
        var header = (state && state.header) || lastPeekHeader || {};
        var peek = header.peek || {};
        peekActions.className = "peek-actions";
        ensurePeekActionButton(peekActions, "peek-minimize-toggle", "compact.mode.set", "Shrink to mini status", "Shrink to mini", "minimize-icon-template", "compact");
        var pin = ensurePeekActionButton(peekActions, "peek-pin-toggle", "peek.pin.toggle", "Pin peek open", "Pin peek open", "pin-icon-template");
        setClass(pin, "is-pinned", !!(peek && peek.hoverPinned));
        pin.setAttribute("aria-pressed", peek && peek.hoverPinned ? "true" : "false");
        ensurePeekActionButton(peekActions, "peek-options-toggle", "settings.toggle", "Open options", "Options", "settings-icon-template");
      }

      function renderBottomActions(state) {
        if (!state.showBottomActions) return null;
        var bottomActions = document.createElement("div");
        bottomActions.className = "bottom-actions";
        var left = document.createElement("div");
        left.className = "bottom-actions-left";
        var center = document.createElement("div");
        center.className = "bottom-actions-center";
        var olderControl = renderOlderFinishedControl(state);
        if (olderControl) center.appendChild(olderControl);
        var options = createOptionsButton();
        bottomActions.appendChild(left);
        bottomActions.appendChild(center);
        bottomActions.appendChild(options);
        return bottomActions;
      }

      window.renderStatus = function(state) {
        state = state || {};
        var widget = document.querySelector(".widget");
        var rows = document.getElementById("rows");
        var settings = mergeSettings(state.settings || {});
        var flash = state.flash || {};
        var effects = state.effects || {};
        if (effects.flash && !flash.widget && !flash.rows) flash = effects.flash;
        window.__claudeStatusSettings = settings;
        window.__claudeStatusFlash = flash;

        setClass(widget, "expanded", !!state.expanded);
        setClass(widget, "peek", state.viewMode === "peek");
        setClass(widget, "compact", state.viewMode === "compact");
        setClass(widget, "peek-hovering", !!state.peekHover);
        setClass(widget, "pinned", !!state.pinned);
        setClass(widget, "widget-flashing", !!(flash.widget && settings.completionFlash));
        setClass(document.body, "waiting-pulse-enabled", !!settings.waitingPulse);

        renderHeader(state.header || {});

        rows.innerHTML = "";
        var active = renderRows(state.activeRows || state.activeSessions || [], "active-row");
        var completed = renderRows(state.recentCompletedRows || state.completedRows || [], "completed-row");
        var older = renderRows(state.olderCompletedRows || [], "completed-row older-finished-row");
        active.forEach(function(row) { rows.appendChild(row); });
        if (state.showDivider) {
          var divider = document.createElement("div");
          divider.className = "divider";
          rows.appendChild(divider);
        }
        completed.forEach(function(row) { rows.appendChild(row); });
        if (state.showOlderFinishedDivider) {
          var olderDivider = document.createElement("div");
          olderDivider.className = "divider older-finished-divider";
          rows.appendChild(olderDivider);
        }
        if (state.olderFinished && state.olderFinished.expanded) {
          older.forEach(function(row) { rows.appendChild(row); });
        }
        var bottomActions = renderBottomActions(state);
        if (bottomActions) {
          rows.appendChild(bottomActions);
        }
        if (!active.length && !completed.length && !older.length && !bottomActions) {
          var empty = document.createElement("div");
          empty.className = "empty";
          empty.textContent = "No Claude sessions";
          rows.appendChild(empty);
        }

        renderSettings(settings, (state.settings && state.settings.items) || state.settingsItems || []);
        renderPeekActions(state);
      };

      window.renderSettings = function(state) {
        state = state || {};
        var settings = mergeSettings(state.settings || {});
        renderSettings(settings, (state.settings && state.settings.items) || state.settingsItems || []);
      };

      document.addEventListener("click", function(event) {
        if (dragClickSuppressed) {
          event.preventDefault();
          event.stopPropagation();
          dragClickSuppressed = false;
          return;
        }
        var control = closestTarget(event.target, "[data-action]");
        var action = control && control.getAttribute && control.getAttribute("data-action");
        if (action === "compact.mode.set") {
          event.stopPropagation();
          postAction({ type: "compact.mode.set", mode: control.getAttribute("data-mode") });
        } else if (action === "expand.toggle") {
          event.stopPropagation();
          postAction({ type: "expand.toggle" });
        } else if (action === "settings.toggle") {
          event.stopPropagation();
          if (requestExpand()) return;
          postAction({ type: "settings.toggle" });
        } else if (action === "peek.pin.toggle") {
          event.stopPropagation();
          postAction({ type: "peek.pin.toggle" });
        } else if (action === "pin.toggle") {
          event.stopPropagation();
          postAction({ type: "pin.toggle" });
        } else if (action === "older.toggle") {
          event.stopPropagation();
          postAction({ type: "older.toggle" });
        } else {
          var peekTarget = closestTarget(event.target, ".peek-ticker");
          var widget = document.querySelector(".widget");
          if (peekTarget && widget && widget.classList.contains("peek")) {
            event.stopPropagation();
            var eventId = peekTarget.getAttribute("data-event-id");
            postAction({
              type: eventId ? "event.focus" : "row.focus",
              id: eventId,
              pane_id: peekTarget.getAttribute("data-pane-id"),
              _zj_session: peekTarget.getAttribute("data-zj-session"),
              tab_num: peekTarget.getAttribute("data-tab-num")
            });
            return;
          }
          var activeStackTarget = closestTarget(event.target, ".peek-active-stack-row");
          if (activeStackTarget) {
            event.stopPropagation();
            postAction({
              type: "row.focus",
              pane_id: activeStackTarget.getAttribute("data-pane-id"),
              _zj_session: activeStackTarget.getAttribute("data-zj-session"),
              tab_num: activeStackTarget.getAttribute("data-tab-num")
            });
            return;
          }
          var historyTarget = closestTarget(event.target, ".peek-history-row");
          if (historyTarget) {
            event.stopPropagation();
            var historyEventId = historyTarget.getAttribute("data-event-id");
            postAction({
              type: historyEventId ? "event.focus" : "row.focus",
              id: historyEventId,
              pane_id: historyTarget.getAttribute("data-pane-id"),
              _zj_session: historyTarget.getAttribute("data-zj-session"),
              tab_num: historyTarget.getAttribute("data-tab-num")
            });
            return;
          }
          var clickedRow = closestTarget(event.target, ".row");
          if (clickedRow && !closestTarget(event.target, "[data-action], label, input, button")) {
            event.stopPropagation();
            postAction({
              type: "row.focus",
              pane_id: clickedRow.getAttribute("data-pane-id"),
              _zj_session: clickedRow.getAttribute("data-zj-session"),
              tab_num: clickedRow.getAttribute("data-tab-num")
            });
            return;
          }
        }
      });

      document.addEventListener("mouseover", function(event) {
        handleWidgetHover(true, event);
      });

      document.addEventListener("mouseout", function(event) {
        handleWidgetHover(false, event);
      });

      document.addEventListener("mousedown", function(event) {
        if (closestTarget(event.target, ".row")) return;
        if (closestTarget(event.target, ".bottom-actions")) return;
        if (closestTarget(event.target, ".peek-history")) return;
        if (closestTarget(event.target, ".collapse-toggle")) return;
        if (closestTarget(event.target, "button")) return;
        if (closestTarget(event.target, "label, input")) return;
        dragOrigin = { x: event.screenX, y: event.screenY };
        dragClickSuppressed = false;
        postAction({ type: "drag.start", x: event.screenX, y: event.screenY });
      });

      document.addEventListener("mousemove", function(event) {
        if (!dragOrigin) return;
        if (Math.abs(event.screenX - dragOrigin.x) > 3 || Math.abs(event.screenY - dragOrigin.y) > 3) {
          dragClickSuppressed = true;
        }
      });

      document.addEventListener("mouseup", function() {
        dragOrigin = null;
      });

      window.__claudeStatusRendererInstalled = true;
    })();
]]):gsub("__BRIDGE_SCHEME__", bridgeScheme or "claude-status")
end

local function settingsScript(bridgeScheme)
    return ([[
    (function() {
      var BRIDGE_SCHEME = "__BRIDGE_SCHEME__";
      var VALID_SETTING_KEYS = { soundsEnabled: true, waitingReminderSound: true, waitingPulse: true, completionFlash: true, processingNeon: true, notificationsEnabled: true };
      var VALID_ACTION_TYPES = { "setting.toggle": true };

      function postAction(message) {
        if (!message || !VALID_ACTION_TYPES[message.type]) return;
        if (message.type === "setting.toggle" && !VALID_SETTING_KEYS[message.key]) return;
        window.location.href = BRIDGE_SCHEME + "://action?payload=" + encodeURIComponent(JSON.stringify(message));
      }

      function renderSettings(settings, settingsItems) {
        var root = document.getElementById("settings");
        if (!root) return;
        root.innerHTML = "";
        (settingsItems || []).forEach(function(item) {
          if (!VALID_SETTING_KEYS[item.key]) return;
          var row = document.createElement("label");
          row.className = "setting";
          row.setAttribute("data-setting", item.key);
          row.textContent = item.label;
          var sw = document.createElement("span");
          sw.className = "switch";
          var input = document.createElement("input");
          input.type = "checkbox";
          input.checked = !!settings[item.key];
          var track = document.createElement("span");
          track.className = "track";
          sw.appendChild(input);
          sw.appendChild(track);
          row.appendChild(sw);
          row.addEventListener("click", function(event) {
            event.preventDefault();
            postAction({ type: "setting.toggle", key: item.key });
          });
          root.appendChild(row);
        });
      }

      window.renderSettings = function(state) {
        state = state || {};
        var settings = mergeSettings(state.settings || {});
        renderSettings(settings, (state.settings && state.settings.items) || state.settingsItems || []);
      };
    })();
]]):gsub("__BRIDGE_SCHEME__", bridgeScheme or "claude-status")
end

function M.eventsScript(bridgeScheme)
    return ([[
    (function() {
      var BRIDGE_SCHEME = "__BRIDGE_SCHEME__";
      var VALID_ACTION_TYPES = { "event.focus": true, "event.dismiss": true };

      function escapeHtml(value) {
        return String(value).replace(/[&<>"']/g, function(ch) {
          return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[ch];
        });
      }

      function postAction(message) {
        if (!message || !VALID_ACTION_TYPES[message.type]) return;
        window.location.href = BRIDGE_SCHEME + "://action?payload=" + encodeURIComponent(JSON.stringify(message));
      }

      function eventIcon(kind) {
        return kind === "waiting" ? "!" : "✓";
      }

      function renderEventRow(event) {
        var row = document.createElement("article");
        row.className = "event-row " + String(event.kind || "finished");
        row.setAttribute("data-event-id", String(event.id || ""));
        row.setAttribute("data-pane-id", String(event.pane_id != null ? event.pane_id : ""));
        row.setAttribute("data-zj-session", event._zj_session || "");
        row.setAttribute("data-tab-num", String(event.tab_num != null ? event.tab_num : ""));

        var badge = document.createElement("div");
        badge.className = "event-badge";
        badge.textContent = escapeHtml(event.display_label || "");

        var copy = document.createElement("div");
        copy.className = "event-copy";
        copy.innerHTML =
          '<div class="event-title">' + escapeHtml(event.title || "") + '</div>' +
          '<div class="event-detail">' + escapeHtml(event.detail || "") + '</div>';

        var status = document.createElement("div");
        status.className = "event-status";
        status.textContent = eventIcon(event.kind);

        var dismiss = document.createElement("button");
        dismiss.className = "event-dismiss";
        dismiss.setAttribute("data-action", "event.dismiss");
        dismiss.setAttribute("aria-label", "Dismiss event");
        dismiss.textContent = "×";

        row.appendChild(badge);
        row.appendChild(copy);
        row.appendChild(status);
        row.appendChild(dismiss);
        return row;
      }

      window.renderEvents = function(state) {
        state = state || {};
        var root = document.getElementById("events");
        if (!root) return;
        root.innerHTML = "";
        (state.events || []).forEach(function(event) {
          root.appendChild(renderEventRow(event));
        });
        if (state.overflow && state.overflow > 0) {
          var overflow = document.createElement("div");
          overflow.className = "event-overflow";
          overflow.textContent = "+" + state.overflow + " more";
          root.appendChild(overflow);
        }
      };

      document.addEventListener("click", function(event) {
        var dismiss = event.target && event.target.closest && event.target.closest('[data-action="event.dismiss"]');
        if (dismiss) {
          var dismissRow = dismiss.closest(".event-row");
          event.preventDefault();
          event.stopPropagation();
          postAction({ type: "event.dismiss", id: dismissRow && dismissRow.getAttribute("data-event-id") });
          return;
        }

        var row = event.target && event.target.closest && event.target.closest(".event-row");
        if (!row) return;
        event.preventDefault();
        event.stopPropagation();
        postAction({
          type: "event.focus",
          id: row.getAttribute("data-event-id"),
          pane_id: row.getAttribute("data-pane-id"),
          _zj_session: row.getAttribute("data-zj-session"),
          tab_num: row.getAttribute("data-tab-num")
        });
      });
    })();
]]):gsub("__BRIDGE_SCHEME__", bridgeScheme or "claude-status")
end

function M.build(options)
    options = options or {}
    local settingsIcon = icons.svg("settings", "control-icon settings-icon")
    local collapseIcon = icons.svg("chevron-up", "control-icon collapse-icon")
    local minimizeIcon = icons.svg("minimize-2", "control-icon minimize-icon")
    local maximizeIcon = icons.svg("maximize-2", "control-icon maximize-icon")
    local pinIcon = icons.svg("pin", "control-icon pin-icon")
    local coffeeIcon = icons.svg("coffee", "control-icon coffee-idle-icon")
    local enlargeIcon = maximizeIcon
    local miniControls = miniView.headerControls({
        enlargeIcon = enlargeIcon,
    })
    local detailControls = detailView.headerControls({
        collapseIcon = collapseIcon,
    })
    local iconTemplates = table.concat({
        sharedView.iconTemplate("settings-icon-template", settingsIcon),
        sharedView.iconTemplate("minimize-icon-template", minimizeIcon),
        sharedView.iconTemplate("maximize-icon-template", maximizeIcon),
        sharedView.iconTemplate("pin-icon-template", pinIcon),
        sharedView.iconTemplate("coffee-idle-icon-template", coffeeIcon),
    }, "\n    ")
    return [[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
]] .. (options.styles or "") .. [[
  </style>
  <script>
]] .. ldrs.script() .. [[
  </script>
  <script>
]] .. settingsScript(options.bridgeScheme) .. [[
  </script>
</head>
<body>
  <main class="widget">
    <div class="widget-flash" id="widget-flash"></div>
    <header class="header">
      <div class="loader-slot" data-loader-slot aria-hidden="true"></div>
      <div class="counts header-counts" id="counts">
        <span class="count compact-count active-count" data-count="active"><span class="count-icon" aria-hidden="true">&#9679;</span><span class="count-value">0</span></span>
        <span class="count compact-count completed-count" data-count="completed"><span class="count-icon" aria-hidden="true">&#10003;</span><span class="count-value">0</span></span>
      </div>
]] .. peekView.ticker() .. [[
      ]] .. miniControls .. [[
      ]] .. detailControls .. [[
    </header>

    <section class="rows" id="rows">
      <div class="empty">No Claude sessions</div>
    </section>
]] .. peekView.history() .. [[
    ]] .. iconTemplates .. [[
  </main>
</body>
</html>
]]
end

function M.buildEvents(options)
    options = options or {}
    return [[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
]] .. (options.styles or "") .. [[
  </style>
  <script>
]] .. M.eventsScript(options.bridgeScheme) .. [[
  </script>
</head>
<body>
  <main class="event-panel" id="events"></main>
</body>
</html>
]]
end

function M.buildSettings(options)
    options = options or {}
    return [[
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
]] .. (options.styles or "") .. [[
  </style>
  <script>
]] .. M.script(options.bridgeScheme) .. [[
  </script>
</head>
<body>
  <main class="settings-panel">
    <header class="settings-panel-header">
      <span class="settings-panel-title">Options</span>
    </header>
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

return M
