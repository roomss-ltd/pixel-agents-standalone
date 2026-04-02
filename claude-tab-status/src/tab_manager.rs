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
        // rename_tab uses 1-based positions, but TabInfo.position is 0-based.
        rename_tab((tab_index + 1) as u32, &new_name);
    }
}

/// Update all tabs that have tracked base names.
pub fn update_all_tab_names(state: &PluginState) {
    let tab_indices: Vec<usize> = state.tab_base_names.keys().copied().collect();
    for tab_index in tab_indices {
        update_tab_name(state, tab_index);
    }
}
