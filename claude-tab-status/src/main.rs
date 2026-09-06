use std::collections::BTreeMap;
use zellij_tile::prelude::*;

mod event_handler;
mod state;
mod status_writer;
mod tab_manager;

use state::{HookPayload, PluginState, TIMER_INTERVAL};

register_plugin!(PluginState);

impl ZellijPlugin for PluginState {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::RunCommands,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::ModeUpdate,
            EventType::Timer,
            EventType::PermissionRequestResult,
            EventType::RunCommandResult,
        ]);
        set_timeout(TIMER_INTERVAL);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                let new_active = tabs.iter().find(|t| t.active).map(|t| t.position);
                let tab_switched = new_active != self.active_tab_index;
                let structure_changed = tabs.len() != self.known_tab_count;

                self.active_tab_index = new_active;
                self.tabs = tabs;
                tab_manager::refresh_base_names(self);

                if structure_changed {
                    // Tabs added/removed: pane mapping is stale.
                    self.known_tab_count = self.tabs.len();
                    tab_manager::rebuild_pane_map(self);
                    tab_manager::update_all_tab_indicators(self);
                } else if tab_switched {
                    // User switched tabs — clear Done (✓) on the focused tab.
                    if let Some(idx) = new_active {
                        if event_handler::clear_done_on_tab(self, idx) {
                            status_writer::write_status_file(self);
                        }
                    }
                }

                false
            }
            Event::PaneUpdate(manifest) => {
                let new_count = tab_manager::count_terminal_panes(&manifest);
                let structure_changed = new_count != self.known_pane_count;

                self.pane_manifest = Some(manifest);

                if structure_changed {
                    self.known_pane_count = new_count;
                }
                // Also refresh when the pane count is stable: a command pane
                // can switch into/out of an agent without changing structure.
                tab_manager::rebuild_pane_map(self);
                tab_manager::update_all_tab_indicators(self);
                tab_manager::request_devin_activity(self);

                false
            }
            Event::ModeUpdate(mode_info) => {
                let was_renaming = matches!(
                    self.input_mode,
                    InputMode::RenameTab | InputMode::RenamePane
                );
                self.input_mode = mode_info.mode;
                if let Some(name) = mode_info.session_name {
                    self.zellij_session_name = name;
                }
                let is_renaming = matches!(
                    self.input_mode,
                    InputMode::RenameTab | InputMode::RenamePane
                );
                if was_renaming && !is_renaming {
                    tab_manager::refresh_base_names(self);
                    tab_manager::update_all_tab_indicators(self);
                }
                false
            }
            Event::Timer(_) => {
                if event_handler::cleanup_stale_sessions(self) {
                    tab_manager::update_all_tab_indicators(self);
                }
                tab_manager::request_devin_activity(self);
                // Always write status file on timer — keeps relative times fresh.
                status_writer::write_status_file(self);
                set_timeout(TIMER_INTERVAL);
                false
            }
            Event::PermissionRequestResult(_) => false,
            Event::RunCommandResult(exit_code, stdout, _stderr, context) => {
                if tab_manager::is_devin_activity_result(&context) {
                    if tab_manager::apply_devin_activity_result(self, exit_code, &stdout) {
                        tab_manager::update_all_tab_indicators(self);
                    }
                    status_writer::write_status_file(self);
                }
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        if pipe_message.name.as_str() != "agent-tab-status-v2" {
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
