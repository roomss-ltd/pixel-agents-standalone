# AgentTab — one-shot installer Makefile.
#
# Usage (from the repo root that contains this file):
#
#   make install      Build AgentTab from source, install to /Applications,
#                     launch. The only requirement is Xcode + the macOS
#                     command-line tools (xcode-select --install). Because
#                     the recipient builds the app themselves, Gatekeeper
#                     doesn't apply — no "Apple could not verify…" warning.
#
#   make dmg          Build a redistributable DMG on the Desktop. Useful
#                     for sharing with non-developers; still has the
#                     Gatekeeper warning unless you have an Apple
#                     Developer ID and notarise the build.
#
#   make uninstall    Remove AgentTab from /Applications, strip its Claude
#                     Code hooks, clear stored preferences.
#
#   make build        Build only (no install). Output ends up in build/.
#
#   make clean        Wipe local build artifacts.

.DEFAULT_GOAL := help
.PHONY: help install build dmg uninstall clean

SHELL := /bin/zsh

help:
	@echo "AgentTab — installer targets"
	@echo ""
	@echo "  make install      Build AgentTab and install to /Applications (no Gatekeeper warning)"
	@echo "  make dmg          Build a redistributable DMG on the Desktop"
	@echo "  make uninstall    Remove AgentTab and clean up its hooks + preferences"
	@echo "  make build        Build the Release .app into build/ (no install)"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "First-time use: just run  make install"

install:
	@scripts/install.sh

build:
	@scripts/install.sh --build-only

dmg:
	@scripts/dmg-to-desktop.sh

uninstall:
	@scripts/uninstall.sh

clean:
	@rm -rf build /tmp/agenttab-install-build /tmp/agenttab-dmg* 2>/dev/null || true
	@echo "[clean] removed local build artifacts"
