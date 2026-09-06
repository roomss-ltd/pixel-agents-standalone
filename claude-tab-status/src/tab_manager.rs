use std::collections::HashSet;

use crate::state::{unix_now, Activity, PluginState, SessionInfo};
use zellij_tile::prelude::*;

const WORKING_MARKER: &str = "●";
const DEVIN_POLL_CONTEXT: &str = "agenttab-devin-activity";

fn is_rename_mode(state: &PluginState) -> bool {
    matches!(
        state.input_mode,
        InputMode::RenameTab | InputMode::RenamePane
    )
}

fn strip_working_marker(name: &str) -> String {
    name.trim_end()
        .strip_suffix(WORKING_MARKER)
        .unwrap_or(name.trim_end())
        .trim_end()
        .to_string()
}

pub fn refresh_base_names(state: &mut PluginState) {
    if is_rename_mode(state) {
        return;
    }
    let ids: HashSet<usize> = state.tabs.iter().map(|tab| tab.tab_id).collect();
    state.tab_base_names.retain(|id, _| ids.contains(id));
    for tab in &state.tabs {
        state
            .tab_base_names
            .insert(tab.tab_id, strip_working_marker(&tab.name));
    }
}

fn tab_is_working(state: &PluginState, tab_position: usize) -> bool {
    state.sessions.values().any(|session| {
        state.pane_to_tab.get(&session.pane_id) == Some(&tab_position)
            && matches!(session.activity, Activity::Thinking | Activity::Tool(_))
    })
}

pub fn update_tab_indicator(state: &mut PluginState, tab_position: usize) {
    if is_rename_mode(state) {
        return;
    }
    let Some(tab_index) = state
        .tabs
        .iter()
        .position(|tab| tab.position == tab_position)
    else {
        return;
    };
    let tab_id = state.tabs[tab_index].tab_id;
    let Some(base) = state.tab_base_names.get(&tab_id) else {
        return;
    };
    let desired = if tab_is_working(state, tab_position) {
        format!("{} {}", base, WORKING_MARKER)
    } else {
        base.clone()
    };
    if state.tabs[tab_index].name != desired {
        rename_tab_with_id(tab_id as u64, &desired);
        // Reflect the requested name locally so back-to-back hook events do
        // not enqueue the same rename before Zellij sends its TabUpdate.
        state.tabs[tab_index].name = desired;
    }
}

pub fn update_all_tab_indicators(state: &mut PluginState) {
    let positions: Vec<usize> = state.tabs.iter().map(|tab| tab.position).collect();
    for position in positions {
        update_tab_indicator(state, position);
    }
}

#[derive(serde::Deserialize)]
struct DevinActivityRow {
    title: String,
    last_activity_at: u64,
    active_tools: u32,
    active_subagents: u32,
}

fn normalized_title(title: &str) -> String {
    title.trim().to_lowercase()
}

fn devin_activity_from_json(output: &[u8], title: &str, now: u64) -> Activity {
    let rows: Vec<DevinActivityRow> = serde_json::from_slice(output).unwrap_or_default();
    let wanted = normalized_title(title);
    let Some(row) = rows
        .iter()
        .find(|row| normalized_title(&row.title) == wanted)
    else {
        return Activity::Idle;
    };
    if row.active_subagents > 0 {
        Activity::Tool("Subagent".into())
    } else if row.active_tools > 0 {
        Activity::Tool("Working".into())
    } else if now.saturating_sub(row.last_activity_at) < 30 {
        Activity::Thinking
    } else {
        Activity::Idle
    }
}

pub fn request_devin_activity(state: &mut PluginState) {
    let has_devin = state.sessions.values().any(|s| s.agent_kind == "devin");
    let now = unix_now();
    if !has_devin
        || state.devin_poll_in_flight
        || now.saturating_sub(state.last_devin_poll) < crate::state::DEVIN_POLL_INTERVAL
    {
        return;
    }
    state.last_devin_poll = now;
    state.devin_poll_in_flight = true;
    let mut context = std::collections::BTreeMap::new();
    context.insert("kind".into(), DEVIN_POLL_CONTEXT.into());
    run_command(
        &[
            "/bin/sh",
            "-c",
            r#"/usr/bin/sqlite3 -readonly -json "$HOME/.local/share/devin/cli/sessions.db" "SELECT COALESCE(s.title, '') AS title, s.last_activity_at, (SELECT COUNT(*) FROM tool_call_state AS t WHERE t.session_id = s.id AND (t.tool_call_update_json IS NULL OR json_extract(t.tool_call_update_json, '$.status') NOT IN ('completed','failed'))) AS active_tools, (SELECT COUNT(*) FROM tool_call_state AS t WHERE t.session_id = s.id AND t.tool_call_json LIKE '%inferenceToolName%run_subagent%' AND (t.tool_call_update_json IS NULL OR json_extract(t.tool_call_update_json, '$.status') NOT IN ('completed','failed'))) AS active_subagents FROM sessions AS s WHERE COALESCE(s.hidden, 0) = 0;""#,
        ],
        context,
    );
}

pub fn apply_devin_activity_result(
    state: &mut PluginState,
    exit_code: Option<i32>,
    stdout: &[u8],
) -> bool {
    state.devin_poll_in_flight = false;
    let now = unix_now();
    let mut changed = false;
    for session in state
        .sessions
        .values_mut()
        .filter(|s| s.agent_kind == "devin")
    {
        let activity = if exit_code == Some(0) {
            devin_activity_from_json(stdout, session.agent_title.as_deref().unwrap_or(""), now)
        } else {
            Activity::Idle
        };
        if session.activity != activity {
            session.activity = activity;
            session.last_event_ts = now;
            changed = true;
        }
    }
    changed
}

pub fn is_devin_activity_result(context: &std::collections::BTreeMap<String, String>) -> bool {
    context.get("kind").map(String::as_str) == Some(DEVIN_POLL_CONTEXT)
}

/// Count total non-plugin panes across all tabs.
pub fn count_terminal_panes(manifest: &PaneManifest) -> usize {
    manifest
        .panes
        .values()
        .flat_map(|panes| panes.iter())
        .filter(|p| !p.is_plugin)
        .count()
}

/// Rebuild pane_id → tab_index mapping from current tabs + pane manifest.
pub fn rebuild_pane_map(state: &mut PluginState) {
    state.pane_to_tab.clear();

    let manifest = match &state.pane_manifest {
        Some(m) => m,
        None => return,
    };

    let mut recognized = Vec::new();
    for tab in &state.tabs {
        if let Some(panes) = manifest.panes.get(&tab.position) {
            for pane in panes {
                if !pane.is_plugin {
                    state.pane_to_tab.insert(pane.id, tab.position);
                    if !pane.exited {
                        if let Some(kind) = agent_kind(pane) {
                            recognized.push((pane.id, kind.to_string(), pane.title.clone()));
                        }
                    }
                }
            }
        }
    }

    let now = unix_now();
    let live_devin: std::collections::HashSet<u32> = recognized
        .iter()
        .filter_map(|(pane_id, kind, _)| (kind == "devin").then_some(*pane_id))
        .collect();

    for (pane_id, kind, title) in recognized {
        if let Some(session) = state.sessions.get_mut(&pane_id) {
            if session.agent_kind == "unknown" || session.agent_kind.is_empty() {
                session.agent_kind = kind;
            }
            if session.agent_kind == "devin" {
                session.agent_title = Some(trim_devin_title(&title).to_string());
            }
        } else if kind == "devin" {
            let session_id = format!("devin-pane-{}", pane_id);
            state.sessions.insert(
                pane_id,
                SessionInfo {
                    run_id: format!("{}:{}:{}:auto", session_id, pane_id, now),
                    session_id,
                    agent_kind: kind,
                    agent_title: Some(trim_devin_title(&title).to_string()),
                    pane_id,
                    activity: Activity::Idle,
                    last_event_ts: now,
                    last_tool_name: None,
                    cwd: None,
                },
            );
        }
    }

    state.sessions.retain(|pane_id, session| {
        !session.session_id.starts_with("devin-pane-") || live_devin.contains(pane_id)
    });
}

fn trim_devin_title(title: &str) -> &str {
    title
        .strip_prefix("devin:")
        .or_else(|| title.strip_prefix("Devin:"))
        .map(str::trim)
        .unwrap_or(title)
}

fn agent_kind(pane: &PaneInfo) -> Option<&'static str> {
    let command = pane
        .terminal_command
        .as_deref()
        .unwrap_or("")
        .to_ascii_lowercase();
    let title = pane.title.to_ascii_lowercase();
    if command
        .split_whitespace()
        .any(|part| part.ends_with("devin"))
        || title.starts_with("devin:")
    {
        Some("devin")
    } else if command.contains("codex") || title.starts_with("codex") {
        Some("codex")
    } else if command.contains("teamclaude")
        || command
            .split_whitespace()
            .any(|part| part.ends_with("claude"))
    {
        Some("claude")
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovers_devin_command_panes() {
        let mut state = PluginState::default();
        state.tabs = vec![TabInfo {
            position: 0,
            name: "Tab Pandora".into(),
            ..Default::default()
        }];
        state.pane_manifest = Some(PaneManifest {
            panes: [(
                0,
                vec![PaneInfo {
                    id: 7,
                    title: "devin: fix the dashboard".into(),
                    terminal_command: Some("devin".into()),
                    ..Default::default()
                }],
            )]
            .into_iter()
            .collect(),
        });

        rebuild_pane_map(&mut state);

        let session = state
            .sessions
            .get(&7)
            .expect("Devin pane should become an agent session");
        assert_eq!(session.session_id, "devin-pane-7");
        assert_eq!(session.agent_kind, "devin");
        assert_eq!(session.agent_title.as_deref(), Some("fix the dashboard"));
        assert_eq!(session.activity, crate::state::Activity::Idle);
    }

    #[test]
    fn strips_only_the_plugin_working_marker() {
        assert_eq!(strip_working_marker("Agenttab ●"), "Agenttab");
        assert_eq!(strip_working_marker("User ✓"), "User ✓");
    }

    #[test]
    fn aggregates_working_state_across_every_pane_in_a_tab() {
        let mut state = PluginState::default();
        state.pane_to_tab.insert(7, 2);
        state.pane_to_tab.insert(8, 2);
        state.sessions.insert(
            7,
            SessionInfo {
                session_id: "done".into(),
                run_id: "done:7".into(),
                agent_kind: "codex".into(),
                agent_title: None,
                pane_id: 7,
                activity: Activity::Done,
                last_event_ts: 1,
                last_tool_name: None,
                cwd: None,
            },
        );
        state.sessions.insert(
            8,
            SessionInfo {
                session_id: "working".into(),
                run_id: "working:8".into(),
                agent_kind: "claude".into(),
                agent_title: None,
                pane_id: 8,
                activity: Activity::Tool("Bash".into()),
                last_event_ts: 1,
                last_tool_name: Some("Bash".into()),
                cwd: None,
            },
        );

        assert!(tab_is_working(&state, 2));
        assert!(!tab_is_working(&state, 1));
    }

    #[test]
    fn devin_requires_database_activity_evidence() {
        let active = br#"[{"title":"Fix dashboard","last_activity_at":100,"active_tools":1,"active_subagents":0}]"#;
        assert_eq!(
            devin_activity_from_json(active, "fix dashboard", 200),
            Activity::Tool("Working".into())
        );

        let recent = br#"[{"title":"Fix dashboard","last_activity_at":190,"active_tools":0,"active_subagents":0}]"#;
        assert_eq!(
            devin_activity_from_json(recent, "Fix dashboard", 200),
            Activity::Thinking
        );

        assert_eq!(
            devin_activity_from_json(recent, "Different session", 200),
            Activity::Idle
        );
    }
}
