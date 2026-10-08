#!/usr/bin/env bash
# Usage: scripts/app-bundle/make-icon.sh [--art SQUARE.png] [--small-crop X,Y,SIZE]
#
# Remakes the app icon from one square picture (default AppIcon-art.png beside this script):
# AppIcon.iconset, the PNGs make-app.sh turns into AppIcon.icns, and Assets.car, the compiled asset
# catalog that macOS 26 and later read first. A Mac with only the Command Line Tools can build the
# app from both files as they are committed; remaking Assets.car needs Xcode's actool.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ART_PATH="${SCRIPT_DIRECTORY}/AppIcon-art.png"
SMALL_CROP="230,250,560"
ICON_SET_DIRECTORY="${SCRIPT_DIRECTORY}/AppIcon.iconset"
ASSET_CATALOG_PATH="${SCRIPT_DIRECTORY}/Assets.car"
ICON_NAME="AppIcon"
MINIMUM_SYSTEM_VERSION="14.0"

fail() {
    echo "error: $1" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --art) ART_PATH="${2:-}"; shift 2 ;;
        --small-crop) SMALL_CROP="${2:-}"; shift 2 ;;
        *) fail "unknown argument $1" ;;
    esac
done

ACTOOL_PATH="$(xcrun --find actool 2>/dev/null || true)"
[[ -n "${ACTOOL_PATH}" ]] || fail "remaking Assets.car needs Xcode's actool; install Xcode or run xcode-select"

WORK_DIRECTORY="$(mktemp -d)"
remove_work_directory() {
    rm -rf "${WORK_DIRECTORY:?}"
}
trap remove_work_directory EXIT

CROP_ARGUMENTS=()
if [[ -n "${SMALL_CROP}" ]]; then
    CROP_ARGUMENTS=(--small-crop "${SMALL_CROP}")
fi
swift "${SCRIPT_DIRECTORY}/make-iconset.swift" --art "${ART_PATH}" --output "${WORK_DIRECTORY}/${ICON_NAME}.iconset" \
    ${CROP_ARGUMENTS[@]+"${CROP_ARGUMENTS[@]}"} < /dev/null

CATALOG_DIRECTORY="${WORK_DIRECTORY}/Assets.xcassets"
APP_ICON_SET_DIRECTORY="${CATALOG_DIRECTORY}/${ICON_NAME}.appiconset"
mkdir -p "${APP_ICON_SET_DIRECTORY}" "${WORK_DIRECTORY}/compiled"
cp "${WORK_DIRECTORY}/${ICON_NAME}.iconset/"*.png "${APP_ICON_SET_DIRECTORY}/"
printf '{"info":{"author":"xcode","version":1}}\n' > "${CATALOG_DIRECTORY}/Contents.json"
{
    printf '{"images":['
    SEPARATOR=""
    for POINTS in 16 32 128 256 512; do
        for SCALE in 1 2; do
            SUFFIX=""
            (( SCALE == 2 )) && SUFFIX="@2x"
            printf '%s{"idiom":"mac","size":"%sx%s","scale":"%sx","filename":"icon_%sx%s%s.png"}' \
                "${SEPARATOR}" "${POINTS}" "${POINTS}" "${SCALE}" "${POINTS}" "${POINTS}" "${SUFFIX}"
            SEPARATOR=","
        done
    done
    printf '],"info":{"author":"xcode","version":1}}\n'
} > "${APP_ICON_SET_DIRECTORY}/Contents.json"

"${ACTOOL_PATH}" --compile "${WORK_DIRECTORY}/compiled" --platform macosx \
    --minimum-deployment-target "${MINIMUM_SYSTEM_VERSION}" --app-icon "${ICON_NAME}" \
    --output-partial-info-plist "${WORK_DIRECTORY}/partial.plist" "${CATALOG_DIRECTORY}" < /dev/null > /dev/null
[[ -f "${WORK_DIRECTORY}/compiled/Assets.car" ]] || fail "actool made no Assets.car"

rm -rf "${ICON_SET_DIRECTORY:?}"
mv "${WORK_DIRECTORY}/${ICON_NAME}.iconset" "${ICON_SET_DIRECTORY}"
mv "${WORK_DIRECTORY}/compiled/Assets.car" "${ASSET_CATALOG_PATH}"
echo "${ICON_SET_DIRECTORY}"
echo "${ASSET_CATALOG_PATH}"
