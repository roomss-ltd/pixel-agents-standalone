use std::collections::{HashMap, HashSet};

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

/// Rebuild internal key mapping after a TabUpdate.
///
/// Zellij's `rename_tab` API has a bug (as of 0.43.1): the server handler at
/// `screen.rs:5069` does `screen.tabs.get_mut(&tab_index.saturating_sub(1))`,
/// looking up by BTreeMap key (internal index) instead of visual position.
/// When tabs are closed, keys stay (never reused) while positions compact,
/// so key != position+1 and the wrong tab gets renamed.
///
/// We work around this by tracking internal keys for every tab we've seen:
///  - Auto-named tabs ("Tab #N") expose their key directly (N-1).
///  - For user-renamed tabs, we carry keys across events by matching
///    base names. If a tab's key is unknown (it was already renamed when
///    the plugin loaded), we never rename it — safer than guessing.
///
/// `old_tabs` and `old_keys` are the previous snapshot, captured before
/// `state.tabs` was replaced with the new TabUpdate payload.
pub fn refresh_tab_keys(
    state: &mut PluginState,
    old_tabs: &[TabInfo],
    old_keys: &HashMap<usize, usize>,
) {
    // Build name → key map from the previous snapshot. Used to carry keys
    // across structural changes (add/delete/move) by matching base names.
    let mut old_name_to_key: HashMap<String, usize> = HashMap::new();
    for t in old_tabs {
        let base = strip_status_suffix(&t.name);
        if let Some(k) = old_keys.get(&t.position) {
            old_name_to_key.insert(base, *k);
        }
    }

    let structure_changed = state.tabs.len() != old_tabs.len();

    state.tab_internal_keys.clear();

    for tab in &state.tabs {
        let base = strip_status_suffix(&tab.name);

        // 1) Auto-named tabs reveal their key directly — most authoritative.
        if let Some(key) = parse_tab_key(&base) {
            state.tab_internal_keys.insert(tab.position, key);
            continue;
        }

        // 2) Match by base name against previous snapshot (survives
        //    deletions, insertions, and tab moves).
        if let Some(k) = old_name_to_key.get(&base) {
            state.tab_internal_keys.insert(tab.position, *k);
            continue;
        }

        // 3) No name match. If structure is unchanged, positions didn't
        //    shift — assume user renamed this tab in place and carry the
        //    old key at this position.
        if !structure_changed {
            if let Some(k) = old_keys.get(&tab.position) {
                state.tab_internal_keys.insert(tab.position, *k);
            }
        }
        // Otherwise: unknown key. update_tab_name will skip this tab.
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
        // internal BTreeMap key, not visual position. Only rename when we
        // know the key — guessing (e.g. position + 1) risks renaming the
        // wrong tab once any tab has been closed or moved.
        if let Some(&key) = state.tab_internal_keys.get(&tab_index) {
            rename_tab((key + 1) as u32, &new_name);
        }
    }
}

/// Update all tabs that have tracked base names.
pub fn update_all_tab_names(state: &PluginState) {
    let tab_indices: Vec<usize> = state.tab_base_names.keys().copied().collect();
    for tab_index in tab_indices {
        update_tab_name(state, tab_index);
    }
}
