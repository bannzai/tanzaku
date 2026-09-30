#!/bin/bash
# Sparkle の appcast (docs/appcast.xml) に、GitHub Releases に置いた DMG の版を足す。
#
# 使い方: bash scripts/macos/update_appcast.sh <DMG のパス> <リリースの tag>
#
# appcast の各版のダウンロード先は、その版の tag の GitHub Releases の asset にする。
# 今の docs/appcast.xml を読み、足した結果で上書きする。appcast の古い版は消さない (--maximum-versions 0)。
# 冪等: 同じ DMG で何度実行しても同じ版の項目を作り直すだけになる。
#
# 必要なもの: 環境変数 SPARKLE_PRIVATE_KEY (Sparkle の EdDSA の秘密鍵。generate_keys -x で書き出した内容)
# 終了コード: 0 成功 / 1 appcast の生成の失敗 / 2 引数・環境変数の不足
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: bash scripts/macos/update_appcast.sh <DMG のパス> <リリースの tag>" >&2
  exit 2
fi
DMG_PATH="$1"
RELEASE_TAG="$2"
APPCAST_PATH="docs/appcast.xml"
APPCAST_DIRECTORY="tmp/distribution/appcast"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "Error: 環境変数 SPARKLE_PRIVATE_KEY が未設定 (AGENTS.md「Mac 版のリリース」)" >&2
  exit 2
fi
if [ ! -f "${DMG_PATH}" ]; then
  echo "Error: ${DMG_PATH} が無い。先に make dmg を実行する" >&2
  exit 2
fi

sparkle_bin_directory="$(bash scripts/macos/fetch_sparkle_tools.sh)"

# generate_appcast は、同じディレクトリの appcast.xml に、そのディレクトリの配布物の版を足す。
rm -rf "${APPCAST_DIRECTORY}"
mkdir -p "${APPCAST_DIRECTORY}"
cp "${APPCAST_PATH}" "${APPCAST_DIRECTORY}/appcast.xml"
cp "${DMG_PATH}" "${APPCAST_DIRECTORY}/"
printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${sparkle_bin_directory}/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/bannzai/tanzaku/releases/download/${RELEASE_TAG}/" \
  --maximum-versions 0 \
  "${APPCAST_DIRECTORY}"
cp "${APPCAST_DIRECTORY}/appcast.xml" "${APPCAST_PATH}"
