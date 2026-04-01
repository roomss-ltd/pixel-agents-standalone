use crate::state::{PluginState, STATUS_ICONS};
use zellij_tile::prelude::*;

/// Rebuild the pane_id → (tab_index, tab_name) mapping from current tabs + pane manifest.
pub fn rebuild_pane_map(state: &mut PluginState) {
    state.pane_to_tab.clear();

    let manifest = match &state.pane_manifest {
        Some(m) => m,
        None => return,
    };

    for tab in &state.tabs {
        let tab_index = tab.position;
        let tab_name = &tab.name;

        // Capture base name (strip any status icon suffix we may have added).
        let base = strip_status_suffix(tab_name);
        state.tab_base_names.insert(tab_index, base);

        // Map all panes in this tab to the tab.
        // PaneManifest.panes is keyed by tab_index.
        if let Some(panes) = manifest.panes.get(&tab_index) {
            for pane in panes {
                if !pane.is_plugin {
                    state.pane_to_tab.insert(
                        pane.id,
                        (tab_index, tab_name.clone()),
                    );
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
    let base = match state.tab_base_names.get(&tab_index) {
        Some(b) => b,
        None => return,
    };

    // Find the highest-priority activity among all sessions in this tab.
    let best_activity = state
        .sessions
        .values()
        .filter(|s| {
            state
                .pane_to_tab
                .get(&s.pane_id)
                .map(|(idx, _)| *idx == tab_index)
                .unwrap_or(false)
        })
        .max_by_key(|s| s.activity.priority());

    let new_name = match best_activity.and_then(|s| s.activity.icon()) {
        Some(icon) => format!("{} {}", base, icon),
        None => base.clone(),
    };

    rename_tab(tab_index as u32, &new_name);
}

/// Update all tabs that have sessions.
pub fn update_all_tab_names(state: &PluginState) {
    let tab_indices: Vec<usize> = state.tab_base_names.keys().copied().collect();
    for tab_index in tab_indices {
        update_tab_name(state, tab_index);
    }
}
