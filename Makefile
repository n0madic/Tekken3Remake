# Building the Tekken 3 remake (remake/README.md). `make` or `make help` lists the targets.
#
# Builds and converted data contain game assets: they are private (docs/remake-plan.md).
# GODOT may point at the Godot 4.7 binary; by default the macOS app, else `godot` on the PATH.

GODOT ?= $(shell [ -x /Applications/Godot.app/Contents/MacOS/Godot ] && echo /Applications/Godot.app/Contents/MacOS/Godot || echo godot)
PYTHON ?= python3
PROJECT := remake
EXPORT_DIR := $(PROJECT)/export
PLATFORMS := macos windows linux web android ios
# The presets' names in remake/export_presets.cfg by platform (spaces as underscores for export_all.sh).
PRESET_macos := macOS
PRESET_windows := Windows
PRESET_linux := Linux
PRESET_web := Web
PRESET_android := Android
PRESET_ios := iOS
# The disc conversion's options, the images required: CONVERT_ARGS='--image "<disc>.cue" [--image ...]'.
CONVERT_ARGS ?=
# The layouts' images: LAYOUT_ARGS='--image "<Japan Rev.1>.cue" --image "<other release>.cue" ...'.
LAYOUT_ARGS ?=
# The web build `serve-web` serves (full, nomovies or lite) and its port.
WEB ?= lite
PORT ?= 8060

export GODOT

.DEFAULT_GOAL := help
.PHONY: help convert convert-nomovies convert-lite import run test test-quick test-converter traces layouts export export-full export-nomovies export-lite \
	$(addprefix export-,$(PLATFORMS)) $(foreach p,$(PLATFORMS),export-$(p)-full export-$(p)-nomovies export-$(p)-lite) \
	serve-web clean-export

help:
	@echo "Setup:"
	@echo "  make convert          convert a disc (Japan Rev.1, original Japan or USA) into remake/imported"
	@echo "                        (CONVERT_ARGS='--image \"<disc>.cue\" ...': the images and options)"
	@echo "  make convert-nomovies the same without movies (music kept)"
	@echo "  make convert-lite     the same without music and movies"
	@echo "  make import           import the converted assets into the Godot project"
	@echo "  make traces           golden traces for the tests (work/ tree required)"
	@echo "  make layouts          remake the other releases' layouts (LAYOUT_ARGS: Japan Rev.1 and their images)"
	@echo "Play and test:"
	@echo "  make run              run the game"
	@echo "  make test             all test suites (about three minutes)"
	@echo "  make test-quick       without the trace comparisons (seconds)"
	@echo "  make test-converter   the converter's own tests (unittest, no game data needed)"
	@echo "Builds (remake/export/, sizes printed):"
	@echo "  make export           every platform, full, nomovies and lite"
	@echo "  make export-full      every platform, full builds only (music and movies)"
	@echo "  make export-nomovies  every platform, nomovies builds only (music, no movies)"
	@echo "  make export-lite      every platform, lite builds only (no music, no movies)"
	@echo "  make export-<p>       one platform, all three builds: $(PLATFORMS)"
	@echo "  make export-<p>-<full|nomovies|lite>  one build, e.g. export-web-nomovies"
	@echo "  make serve-web        serve the web build on http://localhost:$(PORT) (WEB=full|nomovies|lite)"
	@echo "  make clean-export     remove the builds"

convert:
	$(PYTHON) tools/remake_import/convert.py $(CONVERT_ARGS)

convert-nomovies:
	$(PYTHON) tools/remake_import/convert.py --no-movies $(CONVERT_ARGS)

convert-lite:
	$(PYTHON) tools/remake_import/convert.py --no-music --no-movies $(CONVERT_ARGS)

import:
	"$(GODOT)" --headless --path $(PROJECT) --import

run:
	"$(GODOT)" --path $(PROJECT)

test:
	tools/remake/run_tests.sh

test-quick:
	tools/remake/run_tests.sh --quick

test-converter:
	$(PYTHON) -m unittest discover -s tools/remake_import/tests -t tools/remake_import

layouts:
	$(PYTHON) tools/remake_import/layout.py $(LAYOUT_ARGS)

traces:
	$(PYTHON) tools/research/export_traces.py
	$(PYTHON) tools/research/flow_trace.py

export:
	tools/remake/export_all.sh

export-full: $(foreach p,$(PLATFORMS),export-$(p)-full)

export-nomovies: $(foreach p,$(PLATFORMS),export-$(p)-nomovies)

export-lite: $(foreach p,$(PLATFORMS),export-$(p)-lite)

$(addprefix export-,$(PLATFORMS)): export-%:
	tools/remake/export_all.sh $(PRESET_$*)_full $(PRESET_$*)_nomovies $(PRESET_$*)_lite

$(foreach p,$(PLATFORMS),export-$(p)-full): export-%-full:
	tools/remake/export_all.sh $(PRESET_$*)_full

$(foreach p,$(PLATFORMS),export-$(p)-nomovies): export-%-nomovies:
	tools/remake/export_all.sh $(PRESET_$*)_nomovies

$(foreach p,$(PLATFORMS),export-$(p)-lite): export-%-lite:
	tools/remake/export_all.sh $(PRESET_$*)_lite

serve-web:
	@[ -f $(EXPORT_DIR)/web-$(WEB)/index.html ] || { echo "no web $(WEB) build: make export-web-$(WEB)"; exit 1; }
	$(PYTHON) -m http.server $(PORT) --bind 127.0.0.1 --directory $(EXPORT_DIR)/web-$(WEB)

clean-export:
	find $(EXPORT_DIR) -mindepth 1 -maxdepth 1 ! -name .gdignore -exec rm -rf {} +
