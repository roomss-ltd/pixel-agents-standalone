use crate::state::{unix_now, Activity, HookPayload, PluginState, SessionInfo};
use crate::status_writer;
use crate::tab_manager;
use zellij_tile::prelude::{focus_terminal_pane, run_command};

/// TEMP debug trace — appends every hook event + delegation state to a log so
/// we can see the exact backgrounded-agent flow (event order, depth bracketing).
fn dbg_trace(line: &str) {
    let script = format!(
        "printf '[%s] %s\\n' \"$(date +%H:%M:%S)\" '{}' >> /tmp/claude-tab-status-debug.log",
        line.replace('\'', "'\"'\"'")
    );
    run_command(&["bash", "-c", &script], std::collections::BTreeMap::new());
}

fn next_run_id(
    state: &mut PluginState,
    pane_id: u32,
    session_id: Option<&str>,
    now: u64,
) -> String {
    state.run_seq = state.run_seq.saturating_add(1);
    format!(
        "{}:{}:{}:{}",
        session_id.unwrap_or(""),
        pane_id,
        now,
        state.run_seq
    )
}

pub fn handle_hook_event(state: &mut PluginState, payload: HookPayload) {
    let event = payload.hook_event.as_str();
    dbg_trace(&format!(
        "IN  event={} pane={} tool={}",
        event,
        payload.pane_id,
        payload.tool_name.as_deref().unwrap_or("-")
    ));

    // Focus → switch the current client to the tracked terminal pane. This is
    // driven by clicking a row in the Hammerspoon widget and must not mutate
    // status state.
    if event == "Focus" {
        focus_terminal_pane(payload.pane_id, false);
        return;
    }

    // Dismiss → remove session + block this pane_id from re-creation.
    // Sent by the overlay's long-press handler. Distinct from SessionEnd so
    // legitimate session restarts within the same pane still work.
    if event == "Dismiss" {
        if let Some(session) = state.sessions.remove(&payload.pane_id) {
            if let Some(&tab_index) = state.pane_to_tab.get(&session.pane_id) {
                tab_manager::update_tab_name(state, tab_index);
            }
        }
        state.dismissed_until.insert(
            payload.pane_id,
            unix_now() + crate::state::DISMISS_BLOCK_SECS,
        );
        status_writer::write_status_file(state);
        return;
    }

    if event == "ManualInterrupt" {
        let now = unix_now();
        let payload_run_id = payload.run_id.as_deref().unwrap_or("");
        let mut tab_to_update = None;
        let mut changed = false;

        if let Some(session) = state.sessions.get_mut(&payload.pane_id) {
            if payload_run_id.is_empty() || payload_run_id == session.run_id {
                if session.activity != Activity::Done {
                    session.activity = Activity::Done;
                    changed = true;
                }
                session.last_event_ts = now;
                tab_to_update = state.pane_to_tab.get(&session.pane_id).copied();
            }
        }

        if let Some(tab_index) = tab_to_update {
            tab_manager::update_tab_name(state, tab_index);
        }
        if changed {
            status_writer::write_status_file(state);
        }
        return;
    }

    // Drop any other hook event for a pane_id currently blocked.
    if let Some(&until) = state.dismissed_until.get(&payload.pane_id) {
        if unix_now() < until {
            return;
        }
    }

    // SessionEnd → remove session, restore tab name.
    if event == "SessionEnd" {
        if let Some(session) = state.sessions.remove(&payload.pane_id) {
            if let Some(&tab_index) = state.pane_to_tab.get(&session.pane_id) {
                tab_manager::update_tab_name(state, tab_index);
            }
        }
        status_writer::write_status_file(state);
        return;
    }

    // SubagentStop → a SUB-agent (spawned via the Agent/Task tool) finished,
    // NOT the main agent. Do NOT mark Done (that's the main agent's own `Stop`,
    // the real finish — mapping this to Done fired a spurious second "finished"
    // on the dock). Instead bump a per-session counter so the dock can play a
    // distinct "spent casing" animation per sub-agent completion, then write the
    // status WITHOUT changing the activity (it stays working).
    if event == "SubagentStop" {
        let mut write = false;
        if let Some(session) = state.sessions.get_mut(&payload.pane_id) {
            session.subagent_done_seq = session.subagent_done_seq.saturating_add(1);
            session.delegating_depth = session.delegating_depth.saturating_sub(1);
            session.last_event_ts = unix_now();
            // Do NOT fire Done here, even if the main already Stopped. A
            // backgrounded agent's result is injected back as a NEW prompt, so
            // the main always WAKES to process it and emits its own final Stop —
            // THAT is the single completion. Firing here is the premature first
            // finish. Just clear the deferral and stay working.
            if session.delegating_depth == 0 {
                session.stop_pending = false;
            }
            write = true;
        }
        let depth = state.sessions.get(&payload.pane_id).map(|s| s.delegating_depth).unwrap_or(0);
        dbg_trace(&format!("  SubagentStop pane={} depth_after={} (no-fire)", payload.pane_id, depth));
        if write {
            status_writer::write_status_file(state);
        }
        return;
    }

    let mut activity = match event {
        "SessionStart" => Activity::Init,
        "UserPromptSubmit" => Activity::Thinking,
        "PreToolUse" => Activity::Tool(payload.tool_name.clone().unwrap_or_default()),
        "PostToolUse" | "PostToolUseFailure" => Activity::Thinking,
        "PermissionRequest" => Activity::Waiting,
        "Stop" => Activity::Done,
        _ => Activity::Idle,
    };

    let now = unix_now();
    let session_exists = state.sessions.contains_key(&payload.pane_id);
    let assigned_run_id = if event == "UserPromptSubmit" || !session_exists {
        Some(next_run_id(
            state,
            payload.pane_id,
            payload.session_id.as_deref(),
            now,
        ))
    } else {
        None
    };

    let session = state
        .sessions
        .entry(payload.pane_id)
        .or_insert_with(|| SessionInfo {
            session_id: payload.session_id.clone().unwrap_or_default(),
            run_id: assigned_run_id.clone().unwrap_or_default(),
            pane_id: payload.pane_id,
            activity: Activity::Init,
            last_event_ts: 0,
            last_tool_name: None,
            cwd: payload.cwd.clone(),
            subagent_done_seq: 0,
            delegating_depth: 0,
            stop_pending: false,
        });
    if let Some(run_id) = assigned_run_id {
        session.run_id = run_id;
    }
    // Keep cwd fresh — the hook sends it on every event, and an agent
    // can `cd` mid-session.
    if let Some(cwd) = &payload.cwd {
        if !cwd.is_empty() {
            session.cwd = Some(cwd.clone());
        }
    }

    // ── Delegation tracking ──────────────────────────────────────────────
    // `PreToolUse(Agent|Task)` opens a sub-agent; `SubagentStop` (handled
    // above) closes one. A `Stop` that arrives while sub-agents are still
    // outstanding must NOT finish the session — the orchestrated work isn't
    // done. Hold the working state and let the last `SubagentStop` fire the
    // single Done. A new prompt resets the bracket.
    if event == "UserPromptSubmit" {
        session.delegating_depth = 0;
        session.stop_pending = false;
    }
    if event == "PreToolUse"
        && matches!(payload.tool_name.as_deref(), Some("Agent") | Some("Task"))
    {
        session.delegating_depth = session.delegating_depth.saturating_add(1);
    }
    if event == "Stop" && session.delegating_depth > 0 {
        session.stop_pending = true;
        activity = session.activity.clone(); // stay working; defer the finish
    }
    dbg_trace(&format!(
        "  MAIN event={} pane={} depth={} stop_pending={} -> act={:?}",
        event, payload.pane_id, session.delegating_depth, session.stop_pending, activity
    ));

    // Track last tool name across transitions.
    match &activity {
        Activity::Tool(name) => session.last_tool_name = Some(name.clone()),
        Activity::Init => session.last_tool_name = None,
        _ => {} // Thinking/Done/Waiting/Idle preserve last_tool_name
    }
    // UserPromptSubmit → Thinking resets tool context (new turn).
    if event == "UserPromptSubmit" {
        session.last_tool_name = None;
    }

    let activity_changed = session.activity != activity;
    session.activity = activity;
    session.last_event_ts = now;
    if let Some(sid) = &payload.session_id {
        session.session_id = sid.clone();
    }

    // If pane_id is unknown, rebuild map — handles new panes that
    // sent a hook event before PaneUpdate arrived.
    if !state.pane_to_tab.contains_key(&payload.pane_id) {
        tab_manager::rebuild_pane_map(state);
    }

    // Update only the affected tab — not all tabs.
    if let Some(&tab_index) = state.pane_to_tab.get(&payload.pane_id) {
        tab_manager::update_tab_name(state, tab_index);
    }

    // Write status file on activity transitions (real-time updates).
    if activity_changed {
        status_writer::write_status_file(state);
    }
}

/// Clear "Done" sessions on the given tab (called when user focuses a tab).
pub fn clear_done_on_tab(state: &mut PluginState, tab_index: usize) -> bool {
    let mut changed = false;
    for session in state.sessions.values_mut() {
        if session.activity == Activity::Done {
            if state.pane_to_tab.get(&session.pane_id) == Some(&tab_index) {
                session.activity = Activity::Idle;
                changed = true;
            }
        }
    }
    changed
}

/// Clean up stale sessions. Returns true if any state changed.
pub fn cleanup_stale_sessions(state: &mut PluginState) -> bool {
    let now = unix_now();
    let mut changed = false;

    for (_pane_id, session) in state.sessions.iter_mut() {
        let elapsed = now.saturating_sub(session.last_event_ts);
        if matches!(session.activity, Activity::Done) && elapsed >= crate::state::DONE_TIMEOUT {
            session.activity = Activity::Idle;
            changed = true;
        }
    }

    let ghost_ids: Vec<u32> = state
        .sessions
        .iter()
        .filter(|(pane_id, session)| {
            !state.pane_to_tab.contains_key(pane_id)
                && now.saturating_sub(session.last_event_ts) >= crate::state::GHOST_TIMEOUT
        })
        .map(|(pid, _)| *pid)
        .collect();

    for pid in ghost_ids {
        state.sessions.remove(&pid);
        changed = true;
    }

    state.dismissed_until.retain(|_, until| now < *until);

    changed
}
