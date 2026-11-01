#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_MODS="${HOME}/.claude/dev-mods"
SETTINGS="${HOME}/.claude/settings.json"
WRITE=0
if [ "${1:-}" = "--write-settings" ]; then
  WRITE=1
fi

if command -v python3 >/dev/null 2>&1; then
  UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
elif command -v uuidgen >/dev/null 2>&1; then
  UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
else
  UUID="context-bar-$(date +%s)"
fi

TARGET="${DEV_MODS}/${UUID}/context-bar"
echo "Installing context-bar mod to:"
echo "  ${TARGET}"

mkdir -p "${TARGET}"
cp -R "${ROOT}/.claude-plugin" "${TARGET}/"
cp -R "${ROOT}/hooks" "${TARGET}/"

echo
echo "Add this under \"env\" in ${SETTINGS}:"
echo
echo "  \"CLAUDE_CODE_PLUGIN_DIRS\": \"${TARGET}\""
echo

if [ "${WRITE}" -ne 1 ]; then
  echo "Settings not modified. Re-run with --write-settings to merge it automatically."
  echo "Then reload the VS Code window."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for --write-settings. Add the key manually and reload." >&2
  exit 1
fi

mkdir -p "$(dirname "${SETTINGS}")"
if [ -f "${SETTINGS}" ]; then
  BACKUP="${SETTINGS}.bak-context-bar-$(date +%Y%m%d-%H%M%S)"
  cp "${SETTINGS}" "${BACKUP}"
  echo "Backup: ${BACKUP}"
fi

python3 - "${SETTINGS}" "${TARGET}" <<'PY'
import json, os, sys

settings_path, target = sys.argv[1], sys.argv[2]
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

env = data.get("env")
if not isinstance(env, dict):
    env = {}
    data["env"] = env

old = env.get("CLAUDE_CODE_PLUGIN_DIRS")
if old and old != target:
    print(f"warning: replacing existing CLAUDE_CODE_PLUGIN_DIRS={old}", file=sys.stderr)
env["CLAUDE_CODE_PLUGIN_DIRS"] = target

with open(settings_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

echo "Updated ${SETTINGS}"
echo "Now reload the VS Code window (Developer: Reload Window)."
