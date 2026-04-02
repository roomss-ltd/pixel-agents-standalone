use std::collections::BTreeMap;
use zellij_tile::prelude::run_command;

use crate::state::{unix_now, Activity, PluginState};

/// Write aggregated session status to /tmp/claude-tab-status/{session}.json.
/// Uses run_command to execute a bash write-then-mv for atomicity.
pub fn write_status_file(state: &PluginState) {
    let raw_name = if state.zellij_session_name.is_empty() {
        "default"
    } else {
        &state.zellij_session_name
    };
    // Sanitize session name for safe use in file paths and shell commands.
    let session_name: String = raw_name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .collect();
    let session_name = if session_name.is_empty() {
        "default".to_string()
    } else {
        session_name
    };

    let json = build_status_json(state);
    let dir = "/tmp/claude-tab-status";
    let tmp_path = format!("{}/{}.tmp", dir, session_name);
    let final_path = format!("{}/{}.json", dir, session_name);

    let script = format!(
        "mkdir -p {} && printf '%s' '{}' > {} && mv {} {}",
        dir,
        json.replace('\'', "'\"'\"'"),
        tmp_path,
        tmp_path,
        final_path,
    );

    run_command(&["bash", "-c", &script], BTreeMap::new());
}

fn build_status_json(state: &PluginState) -> String {
    let now = unix_now();
    let mut sessions_json: Vec<String> = Vec::new();
    let mut count_active: u32 = 0;
    let mut count_waiting: u32 = 0;
    let mut count_done: u32 = 0;

    for session in state.sessions.values() {
        // Resolve tab name and index for this session.
        let tab_index = state.pane_to_tab.get(&session.pane_id).copied();
        let tab_name = tab_index
            .and_then(|idx| state.tab_base_names.get(&idx))
            .map(|s| s.as_str())
            .unwrap_or("unknown");
        // Zellij tab positions are 0-based; display as 1-based.
        let tab_num = tab_index.map(|i| i + 1).unwrap_or(0);

        let (icon, detail, activity_str) = match &session.activity {
            Activity::Thinking => {
                count_active += 1;
                let detail = session.last_tool_name.clone().unwrap_or_default();
                ("\u{25CF}", detail, "Thinking")
            }
            Activity::Tool(name) => {
                count_active += 1;
                ("\u{26A1}", name.clone(), "Tool")
            }
            Activity::Waiting => {
                count_waiting += 1;
                ("\u{23F8}", String::new(), "Waiting")
            }
            Activity::Done => {
                count_done += 1;
                let elapsed = now.saturating_sub(session.last_event_ts);
                let detail = format_elapsed(elapsed);
                ("\u{2713}", detail, "Done")
            }
            Activity::Init => {
                count_active += 1;
                ("\u{25CB}", String::new(), "Init")
            }
            Activity::Idle => {
                count_done += 1;
                let elapsed = now.saturating_sub(session.last_event_ts);
                let detail = format_elapsed(elapsed);
                ("\u{2713}", detail, "Idle")
            }
        };

        let detail_json = if detail.is_empty() {
            "null".to_string()
        } else {
            format!("\"{}\"", escape_json_string(&detail))
        };

        sessions_json.push(format!(
            "{{\"pane_id\":{},\"tab_num\":{},\"tab_name\":\"{}\",\"icon\":\"{}\",\"detail\":{},\"activity\":\"{}\"}}",
            session.pane_id,
            tab_num,
            escape_json_string(tab_name),
            icon,
            detail_json,
            activity_str,
        ));
    }

    format!(
        "{{\"sessions\":[{}],\"counts\":{{\"active\":{},\"waiting\":{},\"done\":{}}},\"updated_at\":{}}}",
        sessions_json.join(","),
        count_active,
        count_waiting,
        count_done,
        now,
    )
}

fn format_elapsed(secs: u64) -> String {
    if secs < 60 {
        format!("{}s ago", secs)
    } else if secs < 3600 {
        format!("{}m ago", secs / 60)
    } else {
        format!("{}h ago", secs / 3600)
    }
}

fn escape_json_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}
