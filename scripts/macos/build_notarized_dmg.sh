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
#   - 環境変数 ASC_API_KEY_ID / ASC_API_KEY_ISSUER_ID / ASC_API_KEY_P8_BASE64 (notarytool と、provisioning profile を用意する App Store Connect API の認証)
#   - キーチェーンの検索リストにあるチームの Developer ID Application の証明書と秘密鍵
#   - fastlane の gem (scripts/macos/install_developer_id_profile.rb が spaceship を使う)
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

for command_name in codesign ditto hdiutil jq plutil ruby security spctl xcodebuild xcrun; do
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

# アプリは iCloud (CloudKit) と push の entitlement を持つため (Tanzaku/Tanzaku.entitlements)、それを許す Developer ID 用の
# provisioning profile を署名に使う。署名に使う証明書を含む profile を選ぶため、証明書の SHA-1 を渡す。
PROFILE_UUID="$(ruby scripts/macos/install_developer_id_profile.rb --certificate-sha1 "${SIGNING_IDENTITY}" | sed -n 's/^PROFILE_UUID=//p')"
if [ -z "${PROFILE_UUID}" ]; then
  echo "Error: Developer ID 用の provisioning profile を用意できなかった" >&2
  exit 1
fi

rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIRECTORY}" "${STAGING_DIRECTORY}"
mkdir -p "${DISTRIBUTION_DIRECTORY}"

# 秘密鍵のため自分だけが読める権限で書く。デコードが途中で失敗した不完全なファイルを残さないよう、書き終えてから置き換える。
(
  umask 177
  printf '%s' "${ASC_API_KEY_P8_BASE64}" | base64 --decode > "${ASC_API_KEY_PATH}.tmp"
)
mv -f "${ASC_API_KEY_PATH}.tmp" "${ASC_API_KEY_PATH}"

# 手動の署名で Developer ID Application の証明書と上の profile を使う。Apple Development の証明書・Mac の登録・クラウド署名を
# 使わないため、開発者の Mac でも証明書だけを入れた CI のランナーでも同じコマンドで動く。
# コマンドラインのビルド設定は Swift Package の target にも効き、package の target はプロジェクトのチームを受け継がないため、チームも渡す。
# profile は PROVISIONING_PROFILE_SPECIFIER を直接渡すと Swift Package の target にも効くため、アプリの target の Release だけが
# 読む TANZAKU_MAC_PROVISIONING_PROFILE_SPECIFIER で渡す (Tanzaku.xcodeproj)。
xcodebuild -project Tanzaku.xcodeproj -scheme Tanzaku -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath tmp/DerivedData \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  TANZAKU_MAC_PROVISIONING_PROFILE_SPECIFIER="${PROFILE_UUID}" \
  archive

# iCloudContainerEnvironment: Developer ID の配布物は本番の CloudKit 環境を使う (xcodebuild -help の「iCloudContainerEnvironment」)。
jq -n --arg team "${DEVELOPMENT_TEAM}" --arg profile "${PROFILE_UUID}" \
  '{method: "developer-id", teamID: $team, signingStyle: "manual", signingCertificate: "Developer ID Application",
    provisioningProfiles: {"com.bannzai.tanzaku": $profile}, iCloudContainerEnvironment: "Production"}' \
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
# 署名の entitlement が埋め込んだ profile で許されていないと、起動の時に macOS がアプリを止める。公証と spctl はこれを確かめないため、
# 食い違いが出やすい iCloud の環境と push の環境を profile と比べる。
codesign --display --entitlements - --xml "${EXPORTED_APP}" > "${DISTRIBUTION_DIRECTORY}/app-entitlements.plist"
security cms -D -i "${EXPORTED_APP}/Contents/embedded.provisionprofile" -o "${DISTRIBUTION_DIRECTORY}/embedded-profile.plist"
for entitlement_key in com.apple.developer.icloud-container-environment com.apple.developer.aps-environment; do
  # plutil -extract はキーの「.」を階層の区切りと読むため、「:」で区切る PlistBuddy で読む。
  app_value="$(/usr/libexec/PlistBuddy -c "Print :${entitlement_key}" "${DISTRIBUTION_DIRECTORY}/app-entitlements.plist" 2> /dev/null || true)"
  profile_value="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:${entitlement_key}" "${DISTRIBUTION_DIRECTORY}/embedded-profile.plist" 2> /dev/null || true)"
  if [ -z "${app_value}" ] || [ "${app_value}" != "${profile_value}" ]; then
    echo "Error: ${EXPORTED_APP} の ${entitlement_key} (${app_value:-なし}) が profile (${profile_value:-なし}) と一致しない" >&2
    exit 1
  fi
done

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
