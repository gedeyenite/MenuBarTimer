#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="MenuBarTimer"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/build"
RELEASE_DIR="${SCRIPT_DIR}/dist"

echo "==> Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}" "${RELEASE_DIR}"
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources"
mkdir -p "${RELEASE_DIR}"

# 1. Compile Swift binary with optimizations
echo "==> Compiling MenuBarTimer.swift..."
swiftc -O "${SCRIPT_DIR}/MenuBarTimer.swift" -o "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 2. Copy Plist and Resources
echo "==> Packaging App Bundle..."
cp "${SCRIPT_DIR}/App-Info.plist" "${BUILD_DIR}/${APP_BUNDLE}/Contents/Info.plist"
if [ -f "${SCRIPT_DIR}/AppIcon.icns" ]; then
    cp "${SCRIPT_DIR}/AppIcon.icns" "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
if [ -f "${SCRIPT_DIR}/icon.png" ]; then
    cp "${SCRIPT_DIR}/icon.png" "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources/icon.png"
fi

# 3. Ad-hoc codesign
echo "==> Code-signing bundle..."
codesign -s - --force --deep "${BUILD_DIR}/${APP_BUNDLE}"

# 4. Install to /Applications
echo "==> Installing to /Applications/${APP_BUNDLE}..."
rm -rf "/Applications/${APP_BUNDLE}"
cp -R "${BUILD_DIR}/${APP_BUNDLE}" "/Applications/${APP_BUNDLE}"

# 5. Register with LaunchServices
echo "==> Registering with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${APP_BUNDLE}"

# 6. Build .alfredworkflow distribution package
echo "==> Building Alfred Workflow distribution package..."
WORKFLOW_STAGING="${BUILD_DIR}/workflow_staging"
mkdir -p "${WORKFLOW_STAGING}"

cp "${SCRIPT_DIR}/info.plist" "${WORKFLOW_STAGING}/info.plist"
if [ -f "${SCRIPT_DIR}/icon.png" ]; then
    cp "${SCRIPT_DIR}/icon.png" "${WORKFLOW_STAGING}/icon.png"
fi
# Copy bundle inside workflow so it can be self-contained
cp -R "${BUILD_DIR}/${APP_BUNDLE}" "${WORKFLOW_STAGING}/${APP_BUNDLE}"

WORKFLOW_OUTPUT="${RELEASE_DIR}/MenuBarTimer.alfredworkflow"
(
    cd "${WORKFLOW_STAGING}"
    zip -q -r "${WORKFLOW_OUTPUT}" .
)

echo "==> Build complete!"
echo "    App installed: /Applications/${APP_BUNDLE}"
echo "    Alfred Workflow: ${WORKFLOW_OUTPUT}"
