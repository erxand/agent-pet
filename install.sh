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

# The daemon is stopped before its app is replaced, and the new copy is moved into place whole,
# so nothing ever runs from a half copied bundle.
launchctl bootout "${LAUNCH_AGENT_SERVICE_TARGET}" 2>/dev/null || true
rm -rf "${APP_STAGING_PATH:?}"
ditto "${APP_BUILD_DIRECTORY}/${APP_NAME}" "${APP_STAGING_PATH}"
rm -rf "${APP_INSTALL_PATH:?}"
mv "${APP_STAGING_PATH}" "${APP_INSTALL_PATH}"

ln -sfn "${APP_EXECUTABLE_PATH}" "${BINARY_LINK_PATH}"
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

cat > "${LAUNCH_AGENT_PLIST_PATH}" <<PLIST
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

# bootout returns before the service is fully gone, so an immediate bootstrap can fail with
# "Input/output error" while the old job is still tearing down.
BOOTSTRAP_ATTEMPTS=10
for ((BOOTSTRAP_ATTEMPT = 1; BOOTSTRAP_ATTEMPT <= BOOTSTRAP_ATTEMPTS; BOOTSTRAP_ATTEMPT++)); do
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

echo "installed ${APP_INSTALL_PATH}"
echo "linked ${BINARY_LINK_PATH} -> ${APP_EXECUTABLE_PATH}"
echo "linked ${SKILL_LINK_PATH} -> ${SKILL_SOURCE_DIRECTORY}"
echo "linked ${PI_EXTENSION_LINK_PATH} -> ${PI_EXTENSION_SOURCE_PATH}"
echo "bootstrapped launch agent ${LAUNCH_AGENT_SERVICE_TARGET} from ${LAUNCH_AGENT_PLIST_PATH}"
echo "shipped sprite packs are refreshed on every install; copy one under a new name in ${INSTALLED_SPRITES_DIRECTORY} to customize it"
echo "new skills are picked up by new Claude Code sessions; restart any open session to use /pet"
