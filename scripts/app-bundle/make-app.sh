#!/usr/bin/env bash
# Usage: scripts/app-bundle/make-app.sh --executable PATH --output DIRECTORY [--icon-set DIRECTORY]
#        [--version X.Y.Z] [--build N] [--sign IDENTITY]
#
# Assembles DIRECTORY/AgentPet.app around a built agent-pet executable:
#
#   AgentPet.app/Contents/Info.plist
#   AgentPet.app/Contents/MacOS/agent-pet
#   AgentPet.app/Contents/Resources/AppIcon.icns
#
# The icon is made from an .iconset directory with iconutil (default: AppIcon.iconset beside this
# script). The version defaults to the VERSION file at the top of the repository and the build
# number to 1. The bundle is signed with IDENTITY when --sign is given, and ad hoc otherwise, so the
# Info.plist is always bound to the signature. Only tools that ship with macOS are used, and the same
# inputs give the same Info.plist, executable and icon every time.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/../.." && pwd)"

APP_NAME="AgentPet"
BUNDLE_IDENTIFIER="com.agent-pet"
EXECUTABLE_NAME="agent-pet"
ICON_NAME="AppIcon"
MINIMUM_SYSTEM_VERSION="14.0"
APPLE_EVENTS_USAGE="AgentPet brings the terminal tab of the session whose pet you clicked to the front."

EXECUTABLE_PATH=""
OUTPUT_DIRECTORY=""
ICON_SET_DIRECTORY="${SCRIPT_DIRECTORY}/${ICON_NAME}.iconset"
VERSION=""
BUILD_NUMBER="1"
SIGNING_IDENTITY="-"

fail() {
    echo "error: $1" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --executable) EXECUTABLE_PATH="${2:-}"; shift 2 ;;
        --output) OUTPUT_DIRECTORY="${2:-}"; shift 2 ;;
        --icon-set) ICON_SET_DIRECTORY="${2:-}"; shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --build) BUILD_NUMBER="${2:-}"; shift 2 ;;
        --sign) SIGNING_IDENTITY="${2:-}"; shift 2 ;;
        *) fail "unknown argument $1" ;;
    esac
done

[[ -n "${EXECUTABLE_PATH}" ]] || fail "--executable is required"
[[ -n "${OUTPUT_DIRECTORY}" ]] || fail "--output is required"
[[ -f "${EXECUTABLE_PATH}" && -x "${EXECUTABLE_PATH}" ]] || fail "${EXECUTABLE_PATH} is not an executable file"
[[ -d "${ICON_SET_DIRECTORY}" ]] || fail "${ICON_SET_DIRECTORY} is not an icon set directory"
[[ -n "${SIGNING_IDENTITY}" ]] || fail "--sign needs an identity"
if [[ -z "${VERSION}" ]]; then
    VERSION="$(tr -d '[:space:]' < "${REPOSITORY_DIRECTORY}/VERSION")"
fi
[[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "version ${VERSION} is not one to three dot separated numbers"
[[ "${BUILD_NUMBER}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "build ${BUILD_NUMBER} is not one to three dot separated numbers"

mkdir -p "${OUTPUT_DIRECTORY}"
OUTPUT_DIRECTORY="$(cd "${OUTPUT_DIRECTORY}" && pwd)"
APP_PATH="${OUTPUT_DIRECTORY}/${APP_NAME}.app"
STAGING_PATH="${OUTPUT_DIRECTORY}/.${APP_NAME}.app.assembling"

rm -rf "${STAGING_PATH:?}"
mkdir -p "${STAGING_PATH}/Contents/MacOS" "${STAGING_PATH}/Contents/Resources"

cp "${EXECUTABLE_PATH}" "${STAGING_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
chmod 755 "${STAGING_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"

if ! iconutil --convert icns --output "${STAGING_PATH}/Contents/Resources/${ICON_NAME}.icns" "${ICON_SET_DIRECTORY}"; then
    rm -rf "${STAGING_PATH:?}"
    fail "iconutil could not make an icon from ${ICON_SET_DIRECTORY}"
fi

cat > "${STAGING_PATH}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MINIMUM_SYSTEM_VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>${APPLE_EVENTS_USAGE}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "${STAGING_PATH}/Contents/PkgInfo"

# Signing the bundle signs its main executable as part of it and binds the Info.plist and the
# icon, so there is no nested code to sign first and no --deep.
if ! codesign --force --sign "${SIGNING_IDENTITY}" "${STAGING_PATH}"; then
    rm -rf "${STAGING_PATH:?}"
    fail "could not sign ${APP_NAME}.app with ${SIGNING_IDENTITY}"
fi

rm -rf "${APP_PATH:?}"
mv "${STAGING_PATH}" "${APP_PATH}"
echo "${APP_PATH}"
