#!/usr/bin/env bash
# Usage: ./uninstall.sh - remove AgentPet.app, the launch agent and agent-pet's symlinks.
set -euo pipefail

BINARY_LINK_PATH="${HOME}/.local/bin/agent-pet"
APP_INSTALL_PATH="${AGENT_PET_APPLICATIONS_DIRECTORY:-${HOME}/Applications}/AgentPet.app"
SKILL_LINK_PATH="${HOME}/.claude/skills/pet"
PI_EXTENSION_LINK_PATH="${HOME}/.pi/agent/extensions/agent-pet.ts"
STATE_DIRECTORY="${HOME}/.agent-pet"
DAEMON_PID_FILE="${STATE_DIRECTORY}/daemon.pid"
LAUNCH_AGENT_LABEL="com.agent-pet.daemon"
LAUNCH_AGENT_PLIST_PATH="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
LAUNCH_AGENT_SERVICE_TARGET="gui/$(id -u)/${LAUNCH_AGENT_LABEL}"

launchctl bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
rm -f "${LAUNCH_AGENT_PLIST_PATH}"

if [[ -f "${DAEMON_PID_FILE}" ]]; then
    DAEMON_PID="$(cat "${DAEMON_PID_FILE}")"
    if [[ -n "${DAEMON_PID}" ]] && kill -0 "${DAEMON_PID}" 2>/dev/null; then
        kill "${DAEMON_PID}"
        echo "stopped daemon pid ${DAEMON_PID}"
    fi
fi

rm -f "${BINARY_LINK_PATH}"
rm -rf "${APP_INSTALL_PATH:?}"
rm -f "${SKILL_LINK_PATH}"
rm -f "${PI_EXTENSION_LINK_PATH}"

echo "removed ${BINARY_LINK_PATH}"
echo "removed ${APP_INSTALL_PATH}"
echo "removed ${SKILL_LINK_PATH}"
echo "removed ${PI_EXTENSION_LINK_PATH}"
echo "removed ${LAUNCH_AGENT_PLIST_PATH}"
echo "${STATE_DIRECTORY} was left in place; run 'rm -rf ${STATE_DIRECTORY}' if you want it gone"
