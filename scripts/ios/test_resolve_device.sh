#!/bin/bash
# scripts/ios/resolve_device.sh のテスト。devicectl の出力を偽の UDID の JSON に差し替え、実機の台数ごとの分岐を確かめる。
#
# 使い方: bash scripts/ios/test_resolve_device.sh (make test が実行する)
# 終了コード: 0 全件成功 / 1 失敗あり
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
resolve_device="${script_directory}/resolve_device.sh"
fixture_directory="$(mktemp -d)"
trap 'rm -rf "${fixture_directory}"' EXIT

failure_count=0

# devicectl list devices --json-output の形のうち、resolve_device.sh が読むフィールドだけを持つ 1 台分の JSON
device_json() {
  local udid="$1" identifier="$2" name="$3" reality="$4" connection_state="$5"
  printf '{"identifier":"%s","properties":{"hardware":{"udid":"%s","reality":"%s"},"connection":{"state":"%s"},"state":{"name":"%s"}}}' \
    "${identifier}" "${udid}" "${reality}" "${connection_state}" "${name}"
}

write_fixture() {
  local fixture_name="$1"
  shift
  local devices
  devices="$(IFS=,; printf '%s' "$*")"
  printf '{"result":{"devices":[%s]}}' "${devices}" > "${fixture_directory}/${fixture_name}.json"
}

# 期待する終了コードと、標準出力 (成功時) または標準エラーに含まれる文字列を確かめる
assert_resolve() {
  local test_name="$1" fixture_name="$2" device="$3" expected_exit_code="$4" expected_text="$5"
  local stdout_file="${fixture_directory}/stdout" stderr_file="${fixture_directory}/stderr" exit_code=0
  DEVICECTL_JSON="${fixture_directory}/${fixture_name}.json" DEVICE="${device}" bash "${resolve_device}" > "${stdout_file}" 2> "${stderr_file}" || exit_code=$?

  local output_file="${stderr_file}"
  if [ "${expected_exit_code}" -eq 0 ]; then
    output_file="${stdout_file}"
  fi
  if [ "${exit_code}" -eq "${expected_exit_code}" ] && grep -qF -- "${expected_text}" "${output_file}"; then
    echo "PASS: ${test_name}"
  else
    echo "FAIL: ${test_name} (exit ${exit_code}, 期待 ${expected_exit_code} と「${expected_text}」)"
    sed 's/^/  stdout: /' "${stdout_file}"
    sed 's/^/  stderr: /' "${stderr_file}"
    failure_count=$((failure_count + 1))
  fi
}

phone_a="$(device_json 00000000-DUMMYUDID0000A AAAAAAAA-0000-0000-0000-00000000000A 'Dummy iPhone A' physical connected)"
phone_b="$(device_json 00000000-DUMMYUDID0000B BBBBBBBB-0000-0000-0000-00000000000B 'Dummy iPhone B' physical connected)"
# 名前のバックスラッシュは JSON では \\ と書く
phone_symbols="$(device_json 00000000-DUMMYUDID0000F FFFFFFFF-0000-0000-0000-00000000000F 'Dummy \\(^o^)/' physical connected)"
phone_disconnected="$(device_json 00000000-DUMMYUDID0000C CCCCCCCC-0000-0000-0000-00000000000C 'Dummy iPhone C' physical disconnected)"
simulator="$(device_json DDDDDDDD-0000-0000-0000-00000000000D DDDDDDDD-0000-0000-0000-00000000000D 'Dummy Simulator' simulated connected)"

write_fixture none
write_fixture only_unusable "${phone_disconnected}" "${simulator}"
write_fixture one "${phone_a}" "${phone_disconnected}" "${simulator}"
write_fixture two "${phone_a}" "${phone_b}"
write_fixture symbols "${phone_a}" "${phone_symbols}"
write_fixture two_same_name "${phone_a}" "$(device_json 00000000-DUMMYUDID0000E EEEEEEEE-0000-0000-0000-00000000000E 'Dummy iPhone A' physical connected)"

assert_resolve "実機が 0 台なら止まる" none "" 1 "接続中の実機が無い"
assert_resolve "未接続の実機とシミュレータは数えない" only_unusable "" 1 "接続中の実機が無い"
assert_resolve "接続中の実機が 1 台ならその UDID を出す" one "" 0 "00000000-DUMMYUDID0000A"
assert_resolve "実機が 2 台なら止まる" two "" 1 "接続中の実機が 2 台ある"
assert_resolve "実機が 2 台なら一覧に UDID を出す" two "" 1 "Dummy iPhone B  UDID: 00000000-DUMMYUDID0000B"
assert_resolve "DEVICE に名前を指定すると、その UDID を出す" two "Dummy iPhone B" 0 "00000000-DUMMYUDID0000B"
assert_resolve "DEVICE にバックスラッシュを含む名前を指定すると、その UDID を出す" symbols 'Dummy \(^o^)/' 0 "00000000-DUMMYUDID0000F"
assert_resolve "DEVICE に UDID を指定すると、その UDID を出す" two "00000000-DUMMYUDID0000A" 0 "00000000-DUMMYUDID0000A"
assert_resolve "DEVICE に identifier を指定すると、UDID を出す" two "BBBBBBBB-0000-0000-0000-00000000000B" 0 "00000000-DUMMYUDID0000B"
assert_resolve "DEVICE に一致する実機が無いなら止まる" two "Dummy iPhone Z" 1 "DEVICE=Dummy iPhone Z に一致する接続中の実機が無い"
assert_resolve "DEVICE に未接続の実機を指定すると止まる" one "Dummy iPhone C" 1 "に一致する接続中の実機が無い"
assert_resolve "DEVICE の名前に一致する実機が 2 台なら止まる" two_same_name "Dummy iPhone A" 1 "に一致する接続中の実機が 2 台ある"

if [ "${failure_count}" -ne 0 ]; then
  echo "${failure_count} 件失敗"
  exit 1
fi
echo "全件成功"
