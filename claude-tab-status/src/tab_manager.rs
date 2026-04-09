use std::collections::HashSet;

use crate::state::{PluginState, STATUS_ICONS};
use zellij_tile::prelude::*;

/// Returns true if user is in a mode where we must not rename tabs.
fn is_rename_mode(state: &PluginState) -> bool {
    matches!(state.input_mode, InputMode::RenameTab | InputMode::RenamePane)
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

/// Refresh tab_base_names from current tab list.
/// Cheap O(tabs) — only allocates when a base name actually changed.
pub fn refresh_base_names(state: &mut PluginState) {
    // Remove entries for tabs that no longer exist.
    let positions: HashSet<usize> = state.tabs.iter().map(|t| t.position).collect();
    state.tab_base_names.retain(|k, _| positions.contains(k));

    for tab in &state.tabs {
        let base = strip_status_suffix(&tab.name);
        match state.tab_base_names.get(&tab.position) {
            Some(existing) if existing == &base => {} // unchanged
            _ => {
                state.tab_base_names.insert(tab.position, base);
            }
        }
    }
}

/// Rebuild pane_id → tab_index mapping from current tabs + pane manifest.
pub fn rebuild_pane_map(state: &mut PluginState) {
    state.pane_to_tab.clear();

    let manifest = match &state.pane_manifest {
        Some(m) => m,
        None => return,
    };

    for tab in &state.tabs {
        if let Some(panes) = manifest.panes.get(&tab.position) {
            for pane in panes {
                if !pane.is_plugin {
                    state.pane_to_tab.insert(pane.id, tab.position);
                }
            }
        }
    }
}

/// Extract internal tab key from Zellij's auto-generated name "Tab #N" → Some(N-1).
fn parse_tab_key(base_name: &str) -> Option<usize> {
    base_name
        .strip_prefix("Tab #")
        .and_then(|n| n.parse::<usize>().ok())
        .map(|n| n.saturating_sub(1))
}

/// Update internal key mapping from current tab names.
///
/// Zellij's `rename_tab` API has a bug (as of 0.43.1): the server handler at
/// `screen.rs:5070` does `screen.tabs.get_mut(&tab_index.saturating_sub(1))`,
/// looking up by BTreeMap key (internal index) instead of visual position.
/// Other commands like `GoToTab` correctly use `.find(|t| t.position == pos)`.
///
/// We work around this by extracting internal keys from auto-named tabs
/// ("Tab #N" → key N-1) and passing the correct key to `rename_tab`.
pub fn refresh_tab_keys(state: &mut PluginState) {
    // Remove entries for positions that no longer exist.
    let positions: HashSet<usize> = state.tabs.iter().map(|t| t.position).collect();
    state.tab_internal_keys.retain(|k, _| positions.contains(k));

    for tab in &state.tabs {
        let base = strip_status_suffix(&tab.name);
        if let Some(key) = parse_tab_key(&base) {
            state.tab_internal_keys.insert(tab.position, key);
        }
        // For renamed tabs, keep existing key entry if present.
    }
}

/// Strip any trailing status icon we may have appended.
fn strip_status_suffix(name: &str) -> String {
    let trimmed = name.trim_end();
    for icon in STATUS_ICONS {
        if let Some(base) = trimmed.strip_suffix(icon) {
            return base.trim_end().to_string();
        }
    }
    trimmed.to_string()
}

/// Determine the highest-priority icon for a given tab and rename it.
pub fn update_tab_name(state: &PluginState, tab_index: usize) {
    // Never interfere while user is typing a tab/pane name.
    if is_rename_mode(state) {
        return;
    }

    let base = match state.tab_base_names.get(&tab_index) {
        Some(b) => b,
        None => return,
    };

    // Find the highest-priority activity among all sessions in this tab.
    let best_activity = state
        .sessions
        .values()
        .filter(|s| state.pane_to_tab.get(&s.pane_id) == Some(&tab_index))
        .max_by_key(|s| s.activity.priority());

    let new_name = match best_activity.and_then(|s| s.activity.icon()) {
        Some(icon) => format!("{} {}", base, icon),
        None => base.clone(),
    };

    // Only rename if the name actually changed — avoids triggering
    // a TabUpdate cascade from our own renames.
    let current_name = state
        .tabs
        .iter()
        .find(|t| t.position == tab_index)
        .map(|t| t.name.as_str());

    if current_name != Some(new_name.as_str()) {
        // Zellij bug workaround: rename_tab's server handler looks up by
        // internal BTreeMap key, not visual position. Use tracked internal
        // key when available, fall back to position + 1 (correct only when
        // no tabs have ever been deleted from the session).
        let rename_arg = state
            .tab_internal_keys
            .get(&tab_index)
            .map(|key| (key + 1) as u32)
            .unwrap_or((tab_index + 1) as u32);
        rename_tab(rename_arg, &new_name);
    }
}

/// Update all tabs that have tracked base names.
pub fn update_all_tab_names(state: &PluginState) {
    let tab_indices: Vec<usize> = state.tab_base_names.keys().copied().collect();
    for tab_index in tab_indices {
        update_tab_name(state, tab_index);
    }
}
