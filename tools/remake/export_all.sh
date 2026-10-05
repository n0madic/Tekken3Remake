#!/bin/sh
# Exports every preset of remake/export_presets.cfg (a full, a nomovies and a lite build per platform) and
# prints each build's size. Builds contain converted game data: they are private.
#
#   tools/remake/export_all.sh [preset name ...]
#
# Android release builds are signed with GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
# (by default Godot's debug keystore, for local installs). iOS presets write an Xcode project to
# sign and build in Xcode with your team.
# GODOT may point at the Godot 4.7 binary.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROJECT="$ROOT/remake"
if [ -z "${GODOT:-}" ]; then
	if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else
		GODOT=godot
	fi
fi
DEBUG_KEYSTORE="$HOME/Library/Application Support/Godot/keystores/debug.keystore"
[ -f "$DEBUG_KEYSTORE" ] || DEBUG_KEYSTORE="$HOME/.local/share/godot/keystores/debug.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$DEBUG_KEYSTORE}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android}"

if [ "$#" -eq 0 ]; then
	set -- $(sed -n 's/^name="\(.*\)"$/\1/p' "$PROJECT/export_presets.cfg" | tr ' ' '_')
fi
status=0
for preset in "$@"; do
	name=$(echo "$preset" | tr '_' ' ')
	path=$(awk -v n="name=\"$name\"" '$0 == n { found = 1 } found && /^export_path=/ { sub(/^export_path="/, ""); sub(/"$/, ""); print; exit }' "$PROJECT/export_presets.cfg")
	# An unknown preset has no export path: never derive (and delete) a folder from nothing.
	case "$path" in
		export/*/*) ;;
		*)
			printf '%-14s %8s  (no preset of this name with an export/<dir>/ path)\n' "$name" "FAILED"
			status=1
			continue
			;;
	esac
	dir=$(dirname "$PROJECT/$path")
	rm -rf "$dir"
	mkdir -p "$dir"
	if "$GODOT" --headless --path "$PROJECT" --export-release "$name" "$PROJECT/$path" >"$dir.log" 2>&1 \
			&& [ -n "$(ls -A "$dir")" ]; then
		printf '%-14s %8s  %s\n' "$name" "$(du -sh "$dir" | cut -f1)" "$path"
	else
		printf '%-14s %8s  (see %s)\n' "$name" "FAILED" "$dir.log"
		status=1
	fi
done
exit "$status"
