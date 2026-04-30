use std::collections::{HashMap, HashSet};

use crate::state::{BootstrapPhase, PluginState, PROBE_MAX, PROBE_PREFIX, STATUS_ICONS};
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

/// Look up the internal BTreeMap key for a tab by parsing its current name.
///
/// Zellij's `rename_tab` API has a bug (as of 0.43.1): the server handler at
/// `screen.rs:5069` does `screen.tabs.get_mut(&tab_index.saturating_sub(1))`,
/// looking up by BTreeMap key (internal index) instead of visual position.
/// When tabs are closed, keys stay (never reused) while positions compact,
/// so key != position+1 and the wrong tab gets renamed.
///
/// To guarantee we never rename an unrelated tab, we only operate on tabs
/// whose name still matches the auto-generated "Tab #N" format (possibly
/// with our status icon appended). That name is a direct, verifiable
/// signal of the tab's real internal key. User-renamed tabs have no such
/// signal, so we leave them alone entirely.
pub fn verified_tab_key(tab: &TabInfo) -> Option<usize> {
    let base = strip_status_suffix(&tab.name);
    parse_tab_key(&base)
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
    // Don't fire renames until we've discovered internal keys.
    if !matches!(state.bootstrap, BootstrapPhase::Complete) {
        return;
    }
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
        // internal BTreeMap key, not visual position. Only rename if the
        // tab's current name still encodes its key ("Tab #N" or "Tab #N <icon>").
        // User-renamed tabs have no verifiable key, so we never touch them —
        // this guarantees creating a new tab can't cascade-rename user tabs.
        let tab = match state.tabs.iter().find(|t| t.position == tab_index) {
            Some(t) => t,
            None => return,
        };
        if let Some(key) = verified_tab_key(tab) {
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

/// Begin bootstrap probing to discover Zellij's internal BTreeMap keys.
///
/// `rename_tab(N)` looks up by `tabs.get_mut(&(N-1))` — internal key, not
/// visual position. We turn that bug into a discovery tool: probe every
/// candidate key with a unique marker, then on the next TabUpdate read which
/// visual position got each marker. After `finish_bootstrap`, the
/// position→key map is complete and renames are deterministic forever.
///
/// Fast-path: if every current tab is still auto-named "Tab #N", we skip
/// probing entirely — keys are recoverable from names.
pub fn start_bootstrap(state: &mut PluginState) {
    if !matches!(state.bootstrap, BootstrapPhase::NotStarted) {
        return;
    }
    // Defer if user is typing — we'll retry from ModeUpdate on exit.
    if matches!(
        state.input_mode,
        InputMode::RenameTab | InputMode::RenamePane
    ) {
        return;
    }
    if state.tabs.is_empty() {
        state.bootstrap = BootstrapPhase::Complete;
        return;
    }

    // Fast-path: every tab still has its auto-generated "Tab #N" name.
    let all_auto_named = state.tabs.iter().all(|t| {
        let base = strip_status_suffix(&t.name);
        parse_tab_key(&base).is_some()
    });
    if all_auto_named {
        refresh_tab_keys(state);
        state.bootstrap = BootstrapPhase::Complete;
        return;
    }

    let saved_names: HashMap<usize, String> = state
        .tabs
        .iter()
        .map(|t| (t.position, t.name.clone()))
        .collect();

    // Issue probe renames. Only valid internal keys produce visible renames;
    // others no-op. Plugin's own update_tab_name is gated on Complete, so it
    // won't fire during this window.
    for k in 0..PROBE_MAX {
        rename_tab((k + 1) as u32, &format!("{}{}", PROBE_PREFIX, k));
    }

    state.bootstrap = BootstrapPhase::Probing { saved_names };
}

/// Read back probe results, populate `tab_internal_keys`, and restore each
/// probed tab to its original name. Called from the next TabUpdate after
/// `start_bootstrap` issued the probes.
pub fn finish_bootstrap(state: &mut PluginState) {
    let saved_names = match std::mem::replace(&mut state.bootstrap, BootstrapPhase::Complete) {
        BootstrapPhase::Probing { saved_names } => saved_names,
        other => {
            state.bootstrap = other;
            return;
        }
    };

    // Parse probe markers → position-to-key map.
    for tab in &state.tabs {
        if let Some(rest) = tab.name.strip_prefix(PROBE_PREFIX) {
            if let Ok(k) = rest.parse::<usize>() {
                state.tab_internal_keys.insert(tab.position, k);
            }
        }
    }

    // Pre-populate base_names from saved (pre-probe) names so that activity
    // events arriving immediately after bootstrap have the right base.
    for (pos, name) in &saved_names {
        let base = strip_status_suffix(name);
        state.tab_base_names.insert(*pos, base);
    }

    // Restore each probed tab to its original name using the discovered key.
    // Tabs whose internal key fell outside PROBE_MAX kept their original
    // names (probe never landed on them) and need no restore.
    for tab in &state.tabs {
        if !tab.name.starts_with(PROBE_PREFIX) {
            continue;
        }
        let original = match saved_names.get(&tab.position) {
            Some(n) => n,
            None => continue,
        };
        let key = match state.tab_internal_keys.get(&tab.position) {
            Some(k) => *k,
            None => continue,
        };
        rename_tab((key + 1) as u32, original);
    }
}
