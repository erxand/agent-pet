#!/usr/bin/env bash
# Usage: ./install.sh - build agent-pet and install its binary, skill and sprite packs.
set -euo pipefail

TOOL_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_SOURCE_PATH="${TOOL_DIRECTORY}/.build/release/agent-pet"
BINARY_LINK_PATH="${HOME}/.local/bin/agent-pet"
SKILL_SOURCE_DIRECTORY="${TOOL_DIRECTORY}/skill/pet"
SKILL_LINK_PATH="${HOME}/.claude/skills/pet"
PI_EXTENSION_SOURCE_PATH="${TOOL_DIRECTORY}/pi-extension/agent-pet.ts"
PI_EXTENSION_LINK_PATH="${HOME}/.pi/agent/extensions/agent-pet.ts"
STATE_DIRECTORY="${HOME}/.agent-pet"
SESSIONS_DIRECTORY="${STATE_DIRECTORY}/sessions"
INSTALLED_SPRITES_DIRECTORY="${STATE_DIRECTORY}/sprites"
REPOSITORY_SPRITES_DIRECTORY="${TOOL_DIRECTORY}/sprites"
DAEMON_LOG_PATH="${STATE_DIRECTORY}/daemon.log"
LAUNCH_AGENTS_DIRECTORY="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_LABEL="com.agent-pet.daemon"
LAUNCH_AGENT_PLIST_PATH="${LAUNCH_AGENTS_DIRECTORY}/${LAUNCH_AGENT_LABEL}.plist"
LAUNCH_AGENT_DOMAIN_TARGET="gui/$(id -u)"
LAUNCH_AGENT_SERVICE_TARGET="${LAUNCH_AGENT_DOMAIN_TARGET}/${LAUNCH_AGENT_LABEL}"
LAUNCH_AGENT_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "${HOME}/.local/bin"
mkdir -p "${SESSIONS_DIRECTORY}"
mkdir -p "${INSTALLED_SPRITES_DIRECTORY}"
mkdir -p "${HOME}/.claude/skills"
mkdir -p "${HOME}/.pi/agent/extensions"
mkdir -p "${LAUNCH_AGENTS_DIRECTORY}"

if ! swift build --package-path "${TOOL_DIRECTORY}" -c release; then
    echo "error: swift build failed, agent-pet was not installed" >&2
    exit 1
fi

ln -sfn "${BINARY_SOURCE_PATH}" "${BINARY_LINK_PATH}"
ln -sfn "${SKILL_SOURCE_DIRECTORY}" "${SKILL_LINK_PATH}"
ln -sfn "${PI_EXTENSION_SOURCE_PATH}" "${PI_EXTENSION_LINK_PATH}"

for PACK_SOURCE_DIRECTORY in "${REPOSITORY_SPRITES_DIRECTORY}"/*/; do
    PACK_NAME="$(basename "${PACK_SOURCE_DIRECTORY}")"
    PACK_TARGET_DIRECTORY="${INSTALLED_SPRITES_DIRECTORY}/${PACK_NAME}"
    if [[ -d "${PACK_TARGET_DIRECTORY}" ]]; then
        echo "kept existing sprite pack ${PACK_TARGET_DIRECTORY}"
        continue
    fi
    cp -R "${PACK_SOURCE_DIRECTORY}" "${PACK_TARGET_DIRECTORY}"
    echo "installed sprite pack ${PACK_TARGET_DIRECTORY}"
done

cat > "${LAUNCH_AGENT_PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_SOURCE_PATH}</string>
        <string>daemon</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${LAUNCH_AGENT_PATH}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>${DAEMON_LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${DAEMON_LOG_PATH}</string>
</dict>
</plist>
PLIST

launchctl bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
launchctl bootstrap "${LAUNCH_AGENT_DOMAIN_TARGET}" "${LAUNCH_AGENT_PLIST_PATH}"

echo "linked ${BINARY_LINK_PATH} -> ${BINARY_SOURCE_PATH}"
echo "linked ${SKILL_LINK_PATH} -> ${SKILL_SOURCE_DIRECTORY}"
echo "linked ${PI_EXTENSION_LINK_PATH} -> ${PI_EXTENSION_SOURCE_PATH}"
echo "bootstrapped launch agent ${LAUNCH_AGENT_SERVICE_TARGET} from ${LAUNCH_AGENT_PLIST_PATH}"
echo "new skills are picked up by new Claude Code sessions; restart any open session to use /pet"
