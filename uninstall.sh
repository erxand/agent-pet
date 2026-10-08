#!/usr/bin/env bash
# Usage: ./uninstall.sh - remove AgentPet.app, the launch agent and agent-pet's symlinks.
set -euo pipefail

BINARY_LINK_PATH="${HOME}/.local/bin/agent-pet"
APP_NAME="AgentPet.app"
APP_EXECUTABLE_SUFFIX="/${APP_NAME}/Contents/MacOS/agent-pet"
APP_INSTALL_PATH="${AGENT_PET_APPLICATIONS_DIRECTORY:-${HOME}/Applications}/${APP_NAME}"
SKILL_LINK_PATH="${HOME}/.claude/skills/pet"
PI_EXTENSION_LINK_PATH="${HOME}/.pi/agent/extensions/agent-pet.ts"
STATE_DIRECTORY="${HOME}/.agent-pet"
DAEMON_PID_FILE="${STATE_DIRECTORY}/daemon.pid"
LAUNCH_AGENT_LABEL="com.agent-pet.daemon"
LAUNCH_AGENT_PLIST_PATH="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
LAUNCH_AGENT_SERVICE_TARGET="gui/$(id -u)/${LAUNCH_AGENT_LABEL}"
LAUNCHCTL="${AGENT_PET_LAUNCHCTL:-/bin/launchctl}"

# launchd has one gui/<uid> domain whatever HOME says, so an uninstall from another HOME would
# remove the account's real agent. Such an uninstall needs a stand-in launchctl.
ACCOUNT_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
if [[ -z "${AGENT_PET_LAUNCHCTL:-}" ]] && { [[ -z "${ACCOUNT_HOME}" ]] || [[ "$(cd "${HOME}" && pwd -P)" != "$(cd "${ACCOUNT_HOME}" 2>/dev/null && pwd -P)" ]]; }; then
    echo "error: HOME (${HOME}) is not this account's home (${ACCOUNT_HOME:-unknown}); set AGENT_PET_LAUNCHCTL to a stand-in launchctl to uninstall there" >&2
    exit 1
fi

# The plist names the app the install put in place, wherever AGENT_PET_APPLICATIONS_DIRECTORY
# pointed then.
if [[ -f "${LAUNCH_AGENT_PLIST_PATH}" ]]; then
    INSTALLED_EXECUTABLE_PATH="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "${LAUNCH_AGENT_PLIST_PATH}" 2>/dev/null || true)"
    if [[ "${INSTALLED_EXECUTABLE_PATH}" == *"${APP_EXECUTABLE_SUFFIX}" ]]; then
        APP_INSTALL_PATH="${INSTALLED_EXECUTABLE_PATH%"${APP_EXECUTABLE_SUFFIX}"}/${APP_NAME}"
    fi
fi
APPLICATIONS_DIRECTORY="$(dirname "${APP_INSTALL_PATH}")"

"${LAUNCHCTL}" bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
rm -f "${LAUNCH_AGENT_PLIST_PATH}"

if [[ -f "${DAEMON_PID_FILE}" ]]; then
    DAEMON_PID="$(cat "${DAEMON_PID_FILE}" 2>/dev/null || true)"
    if [[ "${DAEMON_PID}" =~ ^[0-9]+$ ]] && kill -0 "${DAEMON_PID}" 2>/dev/null \
        && [[ "$(basename "$(ps -p "${DAEMON_PID}" -o comm= 2>/dev/null || true)")" == "agent-pet" ]] \
        && [[ "$(ps -p "${DAEMON_PID}" -o command= 2>/dev/null || true)" == *" daemon" ]]; then
        kill "${DAEMON_PID}"
        echo "stopped daemon pid ${DAEMON_PID}"
    fi
fi

rm -f "${BINARY_LINK_PATH}"
rm -rf "${APP_INSTALL_PATH:?}"
rm -rf "${APPLICATIONS_DIRECTORY:?}/.${APP_NAME}.installing" "${APPLICATIONS_DIRECTORY:?}/.${APP_NAME}.previous"
rm -f "${SKILL_LINK_PATH}"
rm -f "${PI_EXTENSION_LINK_PATH}"

echo "removed ${BINARY_LINK_PATH}"
echo "removed ${APP_INSTALL_PATH}"
echo "removed ${SKILL_LINK_PATH}"
echo "removed ${PI_EXTENSION_LINK_PATH}"
echo "removed ${LAUNCH_AGENT_PLIST_PATH}"
echo "${STATE_DIRECTORY} was left in place; run 'rm -rf ${STATE_DIRECTORY}' if you want it gone"
