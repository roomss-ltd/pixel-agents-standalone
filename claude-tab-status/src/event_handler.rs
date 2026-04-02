use crate::state::{unix_now, Activity, HookPayload, PluginState, SessionInfo};
use crate::status_writer;
use crate::tab_manager;

pub fn handle_hook_event(state: &mut PluginState, payload: HookPayload) {
    let event = payload.hook_event.as_str();

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

    let session = state
        .sessions
        .entry(payload.pane_id)
        .or_insert_with(|| SessionInfo {
            session_id: payload.session_id.clone().unwrap_or_default(),
            pane_id: payload.pane_id,
            activity: Activity::Init,
            last_event_ts: 0,
            last_tool_name: None,
        });

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
    session.last_event_ts = unix_now();
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
/// Done → Idle transition still happens (for tab icon clearing),
/// but Idle sessions persist until SessionEnd — the overlay keeps showing them.
pub fn cleanup_stale_sessions(state: &mut PluginState) -> bool {
    let now = unix_now();
    let mut changed = false;

    for (_pane_id, session) in state.sessions.iter_mut() {
        let elapsed = now.saturating_sub(session.last_event_ts);
        match session.activity {
            Activity::Done => {
                if elapsed >= crate::state::DONE_TIMEOUT {
                    session.activity = Activity::Idle;
                    changed = true;
                }
            }
            _ => {}
        }
    }

    changed
}
