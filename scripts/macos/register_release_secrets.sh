#!/bin/bash
# リリースの workflow (.github/workflows/release.yml) が使う Secrets を bannzai/tanzaku に登録する。
# 値はどれも標準入力から gh secret set に渡し、コマンドラインの引数・ログに出さない。
#
# 使い方: bash scripts/macos/register_release_secrets.sh <Developer ID Application の .p12 のパス>
#   .p12 はキーチェーンアクセスで証明書 (チーム TQPN82UBBY の Developer ID Application) を書き出したもの。
#   .p12 のパスワードは実行中に入力する。
#
# 必要なもの:
#   - 環境変数 ASC_API_KEY_ID / ASC_API_KEY_ISSUER_ID / ASC_API_KEY_P8_BASE64
#   - ログインキーチェーンの Sparkle の account tanzaku の鍵 (Tanzaku/Info.plist の SUPublicEDKey と対の鍵)
# 冪等: 何度実行しても同じ値で Secrets を上書きするだけになる。
# 終了コード: 0 成功 / 1 登録の失敗 / 2 引数・依存コマンド・値の不足
set -euo pipefail

REPOSITORY="bannzai/tanzaku"
SPARKLE_ACCOUNT="tanzaku"

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: bash scripts/macos/register_release_secrets.sh <Developer ID Application の .p12 のパス>" >&2
  exit 2
fi
P12_PATH="$1"
for command_name in base64 gh; do
  if ! command -v "${command_name}" > /dev/null 2>&1; then
    echo "Error: ${command_name} が見つからない" >&2
    exit 2
  fi
done
# 空の値で既存の Secrets を上書きしないよう、書き込む前にすべての値を確かめる。
for variable_name in ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID ASC_API_KEY_P8_BASE64; do
  if [ -z "${!variable_name:-}" ]; then
    echo "Error: 環境変数 ${variable_name} が未設定" >&2
    exit 2
  fi
done

sparkle_generate_keys="$(bash scripts/macos/fetch_sparkle_tools.sh)/generate_keys"
public_key_in_info_plist="$(plutil -extract SUPublicEDKey raw Tanzaku/Info.plist)"
public_key_in_keychain="$("${sparkle_generate_keys}" --account "${SPARKLE_ACCOUNT}" -p)"
if [ "${public_key_in_keychain}" != "${public_key_in_info_plist}" ]; then
  echo "Error: キーチェーンの Sparkle の鍵 (account ${SPARKLE_ACCOUNT}) が Tanzaku/Info.plist の SUPublicEDKey と対にならない" >&2
  exit 2
fi

read -r -s -p ".p12 のパスワード: " p12_password
echo
if [ -z "${p12_password}" ]; then
  echo "Error: .p12 のパスワードが空" >&2
  exit 2
fi

# generate_keys -x は既にあるファイルへ書き出さないため、自分だけが読めるディレクトリの中のまだ無いファイルを渡す。
sparkle_private_key_directory="$(mktemp -d)"
trap 'rm -rf "${sparkle_private_key_directory}"' EXIT
sparkle_private_key_file="${sparkle_private_key_directory}/sparkle_private_key"
"${sparkle_generate_keys}" --account "${SPARKLE_ACCOUNT}" -x "${sparkle_private_key_file}" > /dev/null
if [ ! -s "${sparkle_private_key_file}" ]; then
  echo "Error: Sparkle の秘密鍵を書き出せなかった" >&2
  exit 1
fi

base64 -i "${P12_PATH}" | gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 -R "${REPOSITORY}"
printf '%s' "${p12_password}" | gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD -R "${REPOSITORY}"
printf '%s' "${ASC_API_KEY_ID}" | gh secret set ASC_API_KEY_ID -R "${REPOSITORY}"
printf '%s' "${ASC_API_KEY_ISSUER_ID}" | gh secret set ASC_API_KEY_ISSUER_ID -R "${REPOSITORY}"
printf '%s' "${ASC_API_KEY_P8_BASE64}" | gh secret set ASC_API_KEY_P8_BASE64 -R "${REPOSITORY}"
gh secret set SPARKLE_PRIVATE_KEY -R "${REPOSITORY}" < "${sparkle_private_key_file}"
gh secret list -R "${REPOSITORY}"
