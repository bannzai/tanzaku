#!/bin/bash
# Mac 版の配布物 (tmp/distribution/Tanzaku-<版>.dmg) を作る。Release をアーカイブして Developer ID Application
# で署名して export し、DMG にして署名・公証・staple し、Gatekeeper と同じ判定で確かめる。
#
# 公証は DMG を 1 回提出する。notarytool はディスクイメージの中のアプリと、Sparkle の XPC サービスなど
# アプリの中のコードもまとめて公証するため。staple は DMG にだけ行う。読み取り専用のイメージの中のアプリは
# 変えられず、コピーしたアプリを最初に開く時は Gatekeeper がオンラインでチケットを確かめるため。
#
# 冪等: アーカイブ・export・DMG は毎回作り直す。
#
# 必要なもの:
#   - 環境変数 ASC_API_KEY_ID / ASC_API_KEY_ISSUER_ID / ASC_API_KEY_P8_BASE64 (notarytool の認証)
#   - キーチェーンの検索リストにあるチームの Developer ID Application の証明書と秘密鍵
# 終了コード: 0 成功 / 1 署名・公証・検証の失敗 / 2 依存コマンド・環境変数・証明書の不足
set -euo pipefail

DISTRIBUTION_DIRECTORY="tmp/distribution"
ARCHIVE_PATH="${DISTRIBUTION_DIRECTORY}/Tanzaku.xcarchive"
EXPORT_DIRECTORY="${DISTRIBUTION_DIRECTORY}/export"
EXPORTED_APP="${EXPORT_DIRECTORY}/Tanzaku.app"
EXPORT_OPTIONS="${DISTRIBUTION_DIRECTORY}/ExportOptions.plist"
STAGING_DIRECTORY="${DISTRIBUTION_DIRECTORY}/dmg"
NOTARIZATION_RESULT="${DISTRIBUTION_DIRECTORY}/notarization.json"
ASC_API_KEY_PATH="${DISTRIBUTION_DIRECTORY}/AuthKey.p8"

for command_name in codesign ditto hdiutil jq plutil security spctl xcodebuild xcrun; do
  if ! command -v "${command_name}" > /dev/null 2>&1; then
    echo "Error: ${command_name} が見つからない" >&2
    exit 2
  fi
done
for variable_name in ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID ASC_API_KEY_P8_BASE64; do
  if [ -z "${!variable_name:-}" ]; then
    echo "Error: 環境変数 ${variable_name} が未設定" >&2
    exit 2
  fi
done

DEVELOPMENT_TEAM="$(xcodebuild -project Tanzaku.xcodeproj -target Tanzaku -configuration Release -showBuildSettings -json | jq -er '.[0].buildSettings.DEVELOPMENT_TEAM')"
# 更新した証明書と前の証明書が両方有効な間は名前が曖昧になるため、DMG の署名には証明書の SHA-1 を渡す。
SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
  | awk -v team="(${DEVELOPMENT_TEAM})\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')"
if [ -z "${SIGNING_IDENTITY}" ]; then
  echo "Error: キーチェーンの検索リストにチーム ${DEVELOPMENT_TEAM} の Developer ID Application の証明書が無い (AGENTS.md「Mac 版のリリース」)" >&2
  exit 2
fi

rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIRECTORY}" "${STAGING_DIRECTORY}"
mkdir -p "${DISTRIBUTION_DIRECTORY}"

# 秘密鍵のため自分だけが読める権限で書く。デコードが途中で失敗した不完全なファイルを残さないよう、書き終えてから置き換える。
(
  umask 177
  printf '%s' "${ASC_API_KEY_P8_BASE64}" | base64 --decode > "${ASC_API_KEY_PATH}.tmp"
)
mv -f "${ASC_API_KEY_PATH}.tmp" "${ASC_API_KEY_PATH}"

# アプリは provisioning profile が要る entitlement を持たない (Tanzaku/Tanzaku.entitlements) ため、手動の署名で
# Developer ID Application の証明書だけを使う。Apple Development の証明書・Mac の登録・クラウド署名を使わないため、
# 開発者の Mac でも証明書だけを入れた CI のランナーでも同じコマンドで動く。
# コマンドラインのビルド設定は Swift Package の target にも効き、package の target はプロジェクトのチームを受け継がないため、チームも渡す。
xcodebuild -project Tanzaku.xcodeproj -scheme Tanzaku -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath tmp/DerivedData \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  archive

jq -n --arg team "${DEVELOPMENT_TEAM}" \
  '{method: "developer-id", teamID: $team, signingStyle: "manual", signingCertificate: "Developer ID Application"}' \
  | plutil -convert xml1 -o "${EXPORT_OPTIONS}" -
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIRECTORY}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}"

# 公証の条件 (チームの Developer ID Application の署名と Hardened Runtime) を満たさないまま提出して待たないよう、先に確かめる。
codesign --verify --deep --strict --verbose=2 "${EXPORTED_APP}"
app_signature="$(codesign --display --verbose=2 "${EXPORTED_APP}" 2>&1)"
if ! grep -q "^Authority=Developer ID Application: .*(${DEVELOPMENT_TEAM})$" <<< "${app_signature}"; then
  echo "Error: ${EXPORTED_APP} がチーム ${DEVELOPMENT_TEAM} の Developer ID Application で署名されていない" >&2
  echo "${app_signature}" >&2
  exit 1
fi
if ! grep -q '^CodeDirectory .*(runtime)' <<< "${app_signature}"; then
  echo "Error: ${EXPORTED_APP} が Hardened Runtime で署名されていない" >&2
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "${EXPORTED_APP}/Contents/Info.plist")"
DMG_PATH="${DISTRIBUTION_DIRECTORY}/Tanzaku-${VERSION}.dmg"
rm -f "${DMG_PATH}"
mkdir -p "${STAGING_DIRECTORY}"
ditto "${EXPORTED_APP}" "${STAGING_DIRECTORY}/Tanzaku.app"
# 開いた DMG の中でアプリを Applications へドラッグして入れられるようにする。
ln -s /Applications "${STAGING_DIRECTORY}/Applications"
hdiutil create -volname Tanzaku -srcfolder "${STAGING_DIRECTORY}" -format UDZO "${DMG_PATH}"
# Gatekeeper はディスクイメージ自体の署名を確かめる (spctl --type open)。
codesign --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"

submission_status=0
xcrun notarytool submit "${DMG_PATH}" \
  --key "${ASC_API_KEY_PATH}" --key-id "${ASC_API_KEY_ID}" --issuer "${ASC_API_KEY_ISSUER_ID}" \
  --wait --output-format json > "${NOTARIZATION_RESULT}" || submission_status=$?
cat "${NOTARIZATION_RESULT}"
echo
if [ "${submission_status}" -ne 0 ] || [ "$(jq -r '.status // empty' "${NOTARIZATION_RESULT}")" != "Accepted" ]; then
  echo "Error: 公証が Accepted にならなかった (notarytool の終了コード ${submission_status})" >&2
  submission_id="$(jq -r '.id // empty' "${NOTARIZATION_RESULT}" 2> /dev/null || true)"
  if [ -n "${submission_id}" ]; then
    # 拒否されたファイルと理由が出る。
    xcrun notarytool log "${submission_id}" \
      --key "${ASC_API_KEY_PATH}" --key-id "${ASC_API_KEY_ID}" --issuer "${ASC_API_KEY_ISSUER_ID}" >&2 || true
  fi
  exit 1
fi

xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
spctl --assess --type execute --verbose=2 "${EXPORTED_APP}"
echo "DMG_PATH=${DMG_PATH}"
