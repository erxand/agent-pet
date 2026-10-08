#!/usr/bin/env bash
# Usage: ./install.sh - build agent-pet, install AgentPet.app, its skill and sprite packs, and start the daemon.
# AGENT_PET_SIGN_IDENTITY signs the app with that code signing identity, AGENT_PET_APPLICATIONS_DIRECTORY
# moves the app out of ~/Applications.
set -euo pipefail

TOOL_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_BUILD_PATH="${TOOL_DIRECTORY}/.build/release/agent-pet"
APP_BUILD_DIRECTORY="${TOOL_DIRECTORY}/.build/release"
APP_NAME="AgentPet.app"
APPLICATIONS_DIRECTORY="${AGENT_PET_APPLICATIONS_DIRECTORY:-${HOME}/Applications}"
APP_INSTALL_PATH="${APPLICATIONS_DIRECTORY}/${APP_NAME}"
APP_STAGING_PATH="${APPLICATIONS_DIRECTORY}/.${APP_NAME}.installing"
APP_PREVIOUS_PATH="${APPLICATIONS_DIRECTORY}/.${APP_NAME}.previous"
APP_EXECUTABLE_PATH="${APP_INSTALL_PATH}/Contents/MacOS/agent-pet"
MAKE_APP_SCRIPT="${TOOL_DIRECTORY}/scripts/app-bundle/make-app.sh"
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
DAEMON_PID_FILE="${STATE_DIRECTORY}/daemon.pid"
DAEMON_STOP_WAIT_TENTHS=50
LAUNCH_AGENTS_DIRECTORY="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_LABEL="com.agent-pet.daemon"
LAUNCH_AGENT_PLIST_PATH="${LAUNCH_AGENTS_DIRECTORY}/${LAUNCH_AGENT_LABEL}.plist"
LAUNCH_AGENT_DOMAIN_TARGET="gui/$(id -u)"
LAUNCH_AGENT_SERVICE_TARGET="${LAUNCH_AGENT_DOMAIN_TARGET}/${LAUNCH_AGENT_LABEL}"
LAUNCH_AGENT_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BUNDLE_IDENTIFIER="com.agent-pet"
SIGNING_IDENTITY="${AGENT_PET_SIGN_IDENTITY:-}"

mkdir -p "${HOME}/.local/bin"
mkdir -p "${SESSIONS_DIRECTORY}"
mkdir -p "${INSTALLED_SPRITES_DIRECTORY}"
mkdir -p "${HOME}/.claude/skills"
mkdir -p "${HOME}/.pi/agent/extensions"
mkdir -p "${LAUNCH_AGENTS_DIRECTORY}"
mkdir -p "${APPLICATIONS_DIRECTORY}"

if ! swift build --package-path "${TOOL_DIRECTORY}" -c release; then
    echo "error: swift build failed, agent-pet was not installed" >&2
    exit 1
fi

BUILD_NUMBER="$(git -C "${TOOL_DIRECTORY}" rev-list --count HEAD 2>/dev/null || echo 1)"
MAKE_APP_ARGUMENTS=(--executable "${BINARY_BUILD_PATH}" --output "${APP_BUILD_DIRECTORY}" --build "${BUILD_NUMBER}")
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    MAKE_APP_ARGUMENTS+=(--sign "${SIGNING_IDENTITY}")
fi
if ! "${MAKE_APP_SCRIPT}" "${MAKE_APP_ARGUMENTS[@]}" >/dev/null; then
    echo "error: could not assemble ${APP_NAME}, agent-pet was not installed" >&2
    exit 1
fi
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "signed ${APP_NAME} as ${BUNDLE_IDENTIFIER} with ${SIGNING_IDENTITY}"
fi

rm -rf "${APP_STAGING_PATH:?}" "${APP_PREVIOUS_PATH:?}"
ditto "${APP_BUILD_DIRECTORY}/${APP_NAME}" "${APP_STAGING_PATH}"

# What the install replaces is kept until the new app is in place, so a failure on the way
# puts the previous app, plist and link back and starts the previous daemon again.
SAVED_DIRECTORY="$(mktemp -d)"
PREVIOUS_LINK_TARGET="$(readlink "${BINARY_LINK_PATH}" 2>/dev/null || true)"
if [[ -f "${LAUNCH_AGENT_PLIST_PATH}" ]]; then
    cp "${LAUNCH_AGENT_PLIST_PATH}" "${SAVED_DIRECTORY}/previous.plist"
fi
INSTALL_COMMITTED=0

restore_previous_install() {
    local exit_status=$?
    if (( INSTALL_COMMITTED == 1 || exit_status == 0 )); then
        return
    fi
    echo "error: the install failed, putting the previous one back" >&2
    if [[ ! -e "${APP_INSTALL_PATH}" && -d "${APP_PREVIOUS_PATH}" ]]; then
        mv "${APP_PREVIOUS_PATH}" "${APP_INSTALL_PATH}" || true
    fi
    rm -rf "${APP_STAGING_PATH:?}"
    rm -f "${LAUNCH_AGENT_PLIST_PATH:?}.new"
    if [[ -f "${SAVED_DIRECTORY}/previous.plist" ]]; then
        cp "${SAVED_DIRECTORY}/previous.plist" "${LAUNCH_AGENT_PLIST_PATH}" || true
    else
        rm -f "${LAUNCH_AGENT_PLIST_PATH:?}"
    fi
    if [[ -n "${PREVIOUS_LINK_TARGET}" ]]; then
        ln -sfn "${PREVIOUS_LINK_TARGET}" "${BINARY_LINK_PATH}" || true
    fi
    if [[ -f "${LAUNCH_AGENT_PLIST_PATH}" ]]; then
        launchctl bootstrap "${LAUNCH_AGENT_DOMAIN_TARGET}" "${LAUNCH_AGENT_PLIST_PATH}" 2>/dev/null || true
    fi
    rm -rf "${SAVED_DIRECTORY:?}"
}
trap restore_previous_install EXIT

# A daemon that the CLI spawned itself, with no launch agent, is not stopped by a bootout. Left
# running on the old executable, it would make the new daemon see it and leave.
stop_daemon_outside_launchd() {
    local daemon_pid
    [[ -f "${DAEMON_PID_FILE}" ]] || return 0
    daemon_pid="$(cat "${DAEMON_PID_FILE}")"
    [[ "${daemon_pid}" =~ ^[0-9]+$ ]] || return 0
    kill -0 "${daemon_pid}" 2>/dev/null || return 0
    [[ "$(basename "$(ps -p "${daemon_pid}" -o comm= 2>/dev/null)")" == "agent-pet" ]] || return 0
    kill "${daemon_pid}" 2>/dev/null || return 0
    for ((STOP_WAIT = 0; STOP_WAIT < DAEMON_STOP_WAIT_TENTHS; STOP_WAIT++)); do
        kill -0 "${daemon_pid}" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -KILL "${daemon_pid}" 2>/dev/null || true
    echo "stopped daemon pid ${daemon_pid}"
}

# The new plist is in place before the daemon is stopped, so a hook that starts the daemon while
# the app is being replaced loads the new plist, never the old one.
cat > "${LAUNCH_AGENT_PLIST_PATH}.new" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_EXECUTABLE_PATH}</string>
        <string>daemon</string>
    </array>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>${BUNDLE_IDENTIFIER}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${LAUNCH_AGENT_PATH}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
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
mv "${LAUNCH_AGENT_PLIST_PATH}.new" "${LAUNCH_AGENT_PLIST_PATH}"

launchctl bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
stop_daemon_outside_launchd

if [[ -e "${APP_INSTALL_PATH}" ]]; then
    mv "${APP_INSTALL_PATH}" "${APP_PREVIOUS_PATH}"
fi
mv "${APP_STAGING_PATH}" "${APP_INSTALL_PATH}"
ln -sfn "${APP_EXECUTABLE_PATH}" "${BINARY_LINK_PATH}"
INSTALL_COMMITTED=1
trap - EXIT
rm -rf "${APP_PREVIOUS_PATH:?}" "${SAVED_DIRECTORY:?}"

ln -sfn "${SKILL_SOURCE_DIRECTORY}" "${SKILL_LINK_PATH}"
ln -sfn "${PI_EXTENSION_SOURCE_PATH}" "${PI_EXTENSION_LINK_PATH}"

for PACK_SOURCE_DIRECTORY in "${REPOSITORY_SPRITES_DIRECTORY}"/*/; do
    PACK_NAME="$(basename "${PACK_SOURCE_DIRECTORY}")"
    PACK_TARGET_DIRECTORY="${INSTALLED_SPRITES_DIRECTORY}/${PACK_NAME}"
    PACK_INSTALL_ACTION="installed"
    if [[ -d "${PACK_TARGET_DIRECTORY}" ]]; then
        rm -rf "${PACK_TARGET_DIRECTORY}"
        PACK_INSTALL_ACTION="refreshed"
    fi
    cp -R "${PACK_SOURCE_DIRECTORY}" "${PACK_TARGET_DIRECTORY}"
    echo "${PACK_INSTALL_ACTION} sprite pack ${PACK_TARGET_DIRECTORY}"
done

# A hook may have loaded the agent while the app was being replaced, so every attempt boots it out
# first. bootout returns before the service is fully gone, so a bootstrap right after it can fail
# with "Input/output error" while the old job is still tearing down. The kickstart makes sure the
# daemon that runs is the one from the new app.
BOOTSTRAP_ATTEMPTS=10
for ((BOOTSTRAP_ATTEMPT = 1; BOOTSTRAP_ATTEMPT <= BOOTSTRAP_ATTEMPTS; BOOTSTRAP_ATTEMPT++)); do
    launchctl bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
    if launchctl bootstrap "${LAUNCH_AGENT_DOMAIN_TARGET}" "${LAUNCH_AGENT_PLIST_PATH}" 2>/dev/null; then
        break
    fi
    if (( BOOTSTRAP_ATTEMPT == BOOTSTRAP_ATTEMPTS )); then
        echo "error: could not bootstrap ${LAUNCH_AGENT_SERVICE_TARGET}" >&2
        launchctl bootstrap "${LAUNCH_AGENT_DOMAIN_TARGET}" "${LAUNCH_AGENT_PLIST_PATH}"
        exit 1
    fi
    sleep 0.5
done
launchctl kickstart -k "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true

echo "installed ${APP_INSTALL_PATH}"
echo "linked ${BINARY_LINK_PATH} -> ${APP_EXECUTABLE_PATH}"
echo "linked ${SKILL_LINK_PATH} -> ${SKILL_SOURCE_DIRECTORY}"
echo "linked ${PI_EXTENSION_LINK_PATH} -> ${PI_EXTENSION_SOURCE_PATH}"
echo "bootstrapped launch agent ${LAUNCH_AGENT_SERVICE_TARGET} from ${LAUNCH_AGENT_PLIST_PATH}"
echo "shipped sprite packs are refreshed on every install; copy one under a new name in ${INSTALLED_SPRITES_DIRECTORY} to customize it"
echo "new skills are picked up by new Claude Code sessions; restart any open session to use /pet"
