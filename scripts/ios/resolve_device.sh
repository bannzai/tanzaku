#!/bin/bash
# make ios-device がアプリを入れる実機を 1 台に決め、その UDID を標準出力に出す。
#
# 使い方: bash scripts/ios/resolve_device.sh
#
# 対象は xcrun devicectl list devices のうち、実機 (reality が physical) で接続中 (connection の state が connected) の端末。
# 環境変数 DEVICE が空なら、対象が 1 台の時にそれを選ぶ。0 台・2 台以上の時は対象の一覧を出して止まる。
# DEVICE を指定した時は、対象のうち UDID・CoreDevice の identifier・名前のどれかが DEVICE と一致する 1 台を選ぶ。
# 出すのは xcodebuild の -destination id= と devicectl の --device の両方が受け付けるハードウェアの UDID。
#
# 環境変数: DEVICE (任意。UDID か名前) / DEVICECTL_JSON (任意。devicectl list devices --json-output の出力のパス。テストで実機の一覧を差し替える)
# 終了コード: 0 成功 / 1 対象が 0 台・2 台以上、または DEVICE に一致する対象が無い / 2 devicectl の実行の失敗
set -euo pipefail

if [ -n "${DEVICECTL_JSON:-}" ]; then
  devices_json="${DEVICECTL_JSON}"
else
  devices_json="$(mktemp)"
  trap 'rm -f "${devices_json}"' EXIT
  if ! xcrun devicectl list devices --quiet --json-output "${devices_json}" >/dev/null; then
    echo "Error: xcrun devicectl list devices が失敗した" >&2
    exit 2
  fi
fi

# 1 行に 1 台、UDID・identifier・名前をタブ区切りで出す
connected_devices="$(jq -r '
  .result.devices[]
  | select(.properties.hardware.reality == "physical" and .properties.connection.state == "connected")
  | [.properties.hardware.udid, .identifier, .properties.state.name]
  | join("\t")
' "${devices_json}")"

if [ -n "${DEVICE:-}" ]; then
  # awk -v は値のバックスラッシュをエスケープとして解釈し、名前 (例: 「iPhone \(^o^)/」) と一致しなくなるため ENVIRON で渡す
  candidates="$(printf '%s\n' "${connected_devices}" | device="${DEVICE}" awk -F '\t' '$1 == ENVIRON["device"] || $2 == ENVIRON["device"] || $3 == ENVIRON["device"]')"
else
  candidates="${connected_devices}"
fi

if [ -z "${candidates}" ]; then
  candidate_count=0
else
  candidate_count="$(printf '%s\n' "${candidates}" | wc -l | tr -d ' ')"
fi

print_connected_devices() {
  if [ -z "${connected_devices}" ]; then
    echo "  (なし)" >&2
  else
    printf '%s\n' "${connected_devices}" | awk -F '\t' '{ printf "  %s  UDID: %s\n", $3, $1 }' >&2
  fi
}

if [ "${candidate_count}" -eq 1 ]; then
  printf '%s\n' "${candidates}" | cut -f 1
  exit 0
fi

if [ -z "${DEVICE:-}" ] && [ "${candidate_count}" -eq 0 ]; then
  echo "Error: 接続中の実機が無い。iPhone を USB か同じネットワークでつなぎ、ロックを解除してから実行する" >&2
  exit 1
fi

if [ -z "${DEVICE:-}" ]; then
  echo "Error: 接続中の実機が ${candidate_count} 台ある。DEVICE=<UDID か名前> で入れる先を指定する。接続中の実機:" >&2
elif [ "${candidate_count}" -eq 0 ]; then
  echo "Error: DEVICE=${DEVICE} に一致する接続中の実機が無い。接続中の実機:" >&2
else
  echo "Error: DEVICE=${DEVICE} に一致する接続中の実機が ${candidate_count} 台ある。DEVICE に UDID を指定する。接続中の実機:" >&2
fi
print_connected_devices
exit 1
