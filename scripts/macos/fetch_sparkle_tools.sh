#!/bin/bash
# アプリに組み込む Sparkle と同じ版の Sparkle の配布物 (generate_appcast・generate_keys など) を
# tmp/sparkle-tools/<版>/ に取得し、ツールのディレクトリ (…/bin) のパスを標準出力に出す。
#
# 版は Tanzaku.xcodeproj/project.pbxproj の Sparkle の exactVersion から読む。
# 冪等: 取得済みなら取得せずにパスだけを出す。
# 終了コード: 0 成功 / 1 版が読めない・sha256 の不一致 / 2 依存コマンドの不足
set -euo pipefail

SPARKLE_DIRECTORY="tmp/sparkle-tools"
# Sparkle の配布物 (Sparkle-<版>.tar.xz) の sha256。project.pbxproj の Sparkle の版を変えた時は、
# https://github.com/sparkle-project/Sparkle/releases のその版の asset の digest に合わせてこの値も変える。
SPARKLE_ARCHIVE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

for command_name in curl shasum tar; do
  if ! command -v "${command_name}" > /dev/null 2>&1; then
    echo "Error: ${command_name} が見つからない" >&2
    exit 2
  fi
done

sparkle_version="$(grep -A 5 'XCRemoteSwiftPackageReference "Sparkle" \*/ = {' Tanzaku.xcodeproj/project.pbxproj | sed -n 's/^[[:space:]]*version = \(.*\);$/\1/p')"
if [ -z "${sparkle_version}" ]; then
  echo "Error: Tanzaku.xcodeproj/project.pbxproj から Sparkle の版を読めない" >&2
  exit 1
fi

sparkle_bin_directory="${SPARKLE_DIRECTORY}/${sparkle_version}/bin"
if [ ! -x "${sparkle_bin_directory}/generate_appcast" ]; then
  sparkle_archive="${SPARKLE_DIRECTORY}/Sparkle-${sparkle_version}.tar.xz"
  mkdir -p "${SPARKLE_DIRECTORY}/${sparkle_version}"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz" -o "${sparkle_archive}"
  if ! echo "${SPARKLE_ARCHIVE_SHA256}  ${sparkle_archive}" | shasum -a 256 -c - > /dev/null; then
    echo "Error: ${sparkle_archive} の sha256 が SPARKLE_ARCHIVE_SHA256 と一致しない (Sparkle の版を変えた時はこのスクリプトの値も変える)" >&2
    exit 1
  fi
  tar -xJf "${sparkle_archive}" -C "${SPARKLE_DIRECTORY}/${sparkle_version}"
fi
echo "${sparkle_bin_directory}"
