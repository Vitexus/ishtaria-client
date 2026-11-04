.DEFAULT_GOAL := run

GODOT ?= godot4
## The world the desktop builds connect to out of the box (written into the package as release_server.txt; saved settings,
## ISHTARIA_SERVER_URL and --server= still win). Build a source-only client with RELEASE_SERVER= (empty).
RELEASE_SERVER ?= https://ishtaria.vitexsoftware.com/api
GODOT_ARGS ?=
SERVER_URL ?=

ifneq ($(strip $(SERVER_URL)),)
export ISHTARIA_SERVER_URL := $(SERVER_URL)
endif

.PHONY: run editor test-face test-connection test-history test-gathering test-fauna test-portals test-menu test-achievements test-panels test-walk test-social test-trading test-placed test-pending test-magic test-minimap test-story test-cuneiform test-life-ordinal test-tablet test-about test-quest-indicator test-disk-cover test-story-live test-world-view test-characters test-environment test-day-night test-sky-ships test-loading-bar test-controls build build-arm64 build-windows build-macos build-web serve-web build-all help

run:
	"$(GODOT)" --path "$(CURDIR)" $(GODOT_ARGS)

editor:
	"$(GODOT)" --editor --path "$(CURDIR)" $(GODOT_ARGS)

test-connection:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/connection_controls.gd

test-history:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/server_history.gd

test-characters:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_creation.gd

test-face:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_face.gd

test-environment:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/surface_environment.gd

test-gathering:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/gathering_client.gd

test-fauna:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/fauna_client.gd

test-portals:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/portal_client.gd

test-menu:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/escape_menu.gd

test-achievements:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/achievements.gd

test-panels:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/panels_look.gd

test-walk:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/walk_pace.gd

test-social:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/social.gd

test-magic:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/magic_client.gd

test-minimap:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/minimap.gd

test-placed:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/placed_client.gd

test-pending:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/pending_actions.gd

test-trading:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/trading_client.gd

test-world-view:
	"$(GODOT)" --path "$(CURDIR)" --resolution 1600x900 --script res://tests/world_view.gd

test-story-live:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/story_live.gd

test-disk-cover:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/disk_cover.gd

test-about:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/about_card.gd

test-quest-indicator:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/quest_indicator.gd

test-story:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/story_client.gd

test-cuneiform:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/cuneiform.gd

test-life-ordinal:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/life_ordinal.gd

test-tablet:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/tablet_panel.gd

test-controls:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_controls.gd

test-sky-ships:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/sky_ships.gd

test-default-server:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/default_server.gd

test-loading-bar:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/loading_bar.gd

test-day-night:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/day_night.gd

define write_release_server
@if [ -n "$(RELEASE_SERVER)" ]; then printf '%s\n' '$(RELEASE_SERVER)' > "$(CURDIR)/release_server.txt"; else rm -f "$(CURDIR)/release_server.txt"; fi
endef

build:
	mkdir -p "$(CURDIR)/build"
	$(call write_release_server)
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Linux "$(CURDIR)/build/ishtaria-client.x86_64"
	@rm -f "$(CURDIR)/release_server.txt"

build-arm64:
	mkdir -p "$(CURDIR)/build"
	$(call write_release_server)
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release "Linux arm64" "$(CURDIR)/build/ishtaria-client.linux-arm64"
	@rm -f "$(CURDIR)/release_server.txt"

## Needs `PLATFORMS=windows tools/fetch-godot.sh` (with the build's XDG_CONFIG_HOME, see README) for the icon and version resources.
build-windows: export WINEPREFIX ?= $(CURDIR)/build/wine
build-windows: export WINEDEBUG ?= -all
build-windows: export WINEDLLOVERRIDES ?= mscoree,mshtml=
build-windows:
	mkdir -p "$(CURDIR)/build"
	$(call write_release_server)
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Windows "$(CURDIR)/build/ishtaria-client.windows-x86_64.exe"
	@rm -f "$(CURDIR)/release_server.txt"

build-macos:
	mkdir -p "$(CURDIR)/build"
	$(call write_release_server)
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release macOS "$(CURDIR)/build/ishtaria-client.macos.zip"
	@rm -f "$(CURDIR)/release_server.txt"

## The browser build (HTML5 / WebAssembly, no threads) into build/web/. Needs the Godot web export template web_nothreads_release.zip in
## ~/.local/share/godot/export_templates/4.5.stable/ (the Debian templates package has only the Linux ones).
build-web:
	mkdir -p "$(CURDIR)/build/web"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Web "$(CURDIR)/build/web/index.html"

## Serves build/web on http://127.0.0.1:8060/ for a test (the game server's address goes in ?server=).
serve-web: build-web
	python3 -m http.server 8060 --bind 127.0.0.1 --directory "$(CURDIR)/build/web"

build-all: build build-arm64 build-windows build-macos build-web

help:
	@printf '%s\n' \
		'make [run]  Run the client from local sources' \
		'make editor Open the project in Godot' \
		'make build-web  Export the browser build to build/web (needs the web export template)' \
		'make test-connection  Test controls against the local server' \
		'make test-characters  Test character assets and first-run setup' \
		'make test-environment  Test terrain mapping and scenery placement' \
		'make test-day-night  Test solar clock, seasons and lighting' \
		'make test-controls  Test keyboard remapping and mouse camera' \
		'make build  Export the Linux release executable' \
		'make build-arm64  Export the Linux arm64 release executable' \
		'make build-windows  Export the Windows x86-64 executable (unsigned)' \
		'make build-macos  Export the universal macOS app as a zip (unsigned)' \
		'Overrides: GODOT=godot4 SERVER_URL=http://127.0.0.1:7400 GODOT_ARGS="..."'
