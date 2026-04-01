use std::collections::BTreeMap;
use zellij_tile::prelude::*;

mod event_handler;
mod state;
mod tab_manager;

use state::{HookPayload, PluginState, TIMER_INTERVAL};

register_plugin!(PluginState);

impl ZellijPlugin for PluginState {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::Timer,
            EventType::PermissionRequestResult,
        ]);
        set_timeout(TIMER_INTERVAL);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
                tab_manager::rebuild_pane_map(self);
                tab_manager::update_all_tab_names(self);
                false
            }
            Event::PaneUpdate(manifest) => {
                self.pane_manifest = Some(manifest);
                tab_manager::rebuild_pane_map(self);
                tab_manager::update_all_tab_names(self);
                false
            }
            Event::Timer(_) => {
                let changed = event_handler::cleanup_stale_sessions(self);
                if changed {
                    tab_manager::update_all_tab_names(self);
                }
                set_timeout(TIMER_INTERVAL);
                false
            }
            Event::PermissionRequestResult(_) => {
                // No-op. We already subscribed in load().
                // DO NOT re-subscribe here — duplicate subscriptions cause
                // exponential timer growth (each Timer fires N events,
                // each calling set_timeout, doubling every tick).
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        if pipe_message.name.as_str() != "claude-tab-status" {
            return false;
        }

        let payload_str = match pipe_message.payload {
            Some(ref s) => s,
            None => return false,
        };

        let payload: HookPayload = match serde_json::from_str(payload_str) {
            Ok(p) => p,
            Err(_) => return false,
        };

        event_handler::handle_hook_event(self, payload);
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // This plugin is invisible — no rendering.
    }
}
