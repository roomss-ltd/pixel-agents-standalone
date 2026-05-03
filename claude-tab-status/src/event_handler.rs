use crate::state::{unix_now, Activity, HookPayload, PluginState, SessionInfo};
use crate::status_writer;
use crate::tab_manager;
use zellij_tile::prelude::focus_terminal_pane;

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

    let activity = match event {
        "SessionStart" => Activity::Init,
        "UserPromptSubmit" => Activity::Thinking,
        "PreToolUse" => Activity::Tool(payload.tool_name.clone().unwrap_or_default()),
        "PostToolUse" | "PostToolUseFailure" => Activity::Thinking,
        "PermissionRequest" => Activity::Waiting,
        "Stop" => Activity::Done,
        "SubagentStop" => Activity::Done,
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
        });
    if let Some(run_id) = assigned_run_id {
        session.run_id = run_id;
    }

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
