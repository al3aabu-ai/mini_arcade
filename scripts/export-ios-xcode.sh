#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNITY_VERSION="${UNITY_VERSION:-6000.3.18f1}"
UNITY_APP="${UNITY_APP:-/Applications/Unity/Hub/Editor/${UNITY_VERSION}/Unity.app/Contents/MacOS/Unity}"
LOG_PATH="${LOG_PATH:-${ROOT_DIR}/Builds/iOS/unity-ios-export.log}"
EXPORT_DIR="${MINI_ARCADE_IOS_EXPORT_PATH:-${ROOT_DIR}/Builds/iOS/MiniArcade-iOS}"

export MINI_ARCADE_IOS_EXPORT_PATH="${EXPORT_DIR}"

if [[ ! -x "${UNITY_APP}" ]]; then
  echo "Unity executable not found: ${UNITY_APP}" >&2
  echo "Install Unity ${UNITY_VERSION} with iOS Build Support, or set UNITY_APP." >&2
  exit 1
fi

mkdir -p "$(dirname "${LOG_PATH}")"

"${UNITY_APP}" \
  -batchmode \
  -quit \
  -projectPath "${ROOT_DIR}" \
  -executeMethod MiniArcade.Editor.IOSBuild.ExportXcodeProject \
  -logFile "${LOG_PATH}"

echo "Exported iOS Xcode project:"
echo "${EXPORT_DIR}"
echo "Unity export log:"
echo "${LOG_PATH}"
