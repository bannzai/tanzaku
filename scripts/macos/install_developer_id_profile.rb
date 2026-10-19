# Mac 版の配布 (Developer ID) に使う provisioning profile を App Store Connect API で用意し、
# Xcode が読む場所に置く。アプリは iCloud (CloudKit) と push の entitlement を持ち、Developer ID で
# 署名したアプリがそれらを使うには、その entitlement を許す Developer ID 用の profile が要る
# ( https://developer.apple.com/developer-id/ )。
#
# 使い方: ruby scripts/macos/install_developer_id_profile.rb --certificate-sha1 <署名に使う証明書の SHA-1> [--recreate]
#
# 冪等: 名前が PROFILE_NAME の profile があり、条件 (下の profile_problems) を満たせばそれを置き直すだけで、作らない。
# 無ければ作る。条件を満たさない時 (App ID の capability を変えて INVALID になった等) は止める。
# --recreate を付けた時だけ、条件を満たさない profile を消して作り直す (消した profile は戻せないため、既定では消さない)。
#
# 必要なもの: 環境変数 ASC_API_KEY_ID / ASC_API_KEY_ISSUER_ID / ASC_API_KEY_P8_BASE64、fastlane (spaceship) の gem
# 出力: 最後の行に PROFILE_UUID=<uuid>
# 終了コード: 0 成功 / 1 profile が条件を満たさない・作れない / 2 引数・環境変数の不足
require 'base64'
require 'digest'
require 'fileutils'
require 'openssl'
require 'optparse'
require 'plist'
require 'spaceship'
require 'time'

BUNDLE_IDENTIFIER = 'com.bannzai.tanzaku'
# App Store Connect で profile を探すための名前。チーム・個人の名前を含めない。
PROFILE_NAME = 'Tanzaku Developer ID'
ICLOUD_CONTAINER_IDENTIFIER = 'iCloud.com.bannzai.tanzaku'
# Xcode 16 以降が provisioning profile を探す場所。
PROFILES_DIRECTORY = File.expand_path('~/Library/Developer/Xcode/UserData/Provisioning Profiles')

certificate_sha1 = nil
recreate = false
OptionParser.new do |parser|
  parser.on('--certificate-sha1 SHA1') { |value| certificate_sha1 = value.upcase }
  parser.on('--recreate') { recreate = true }
end.parse!

if certificate_sha1.nil?
  warn 'Error: --certificate-sha1 が無い'
  exit 2
end
%w[ASC_API_KEY_ID ASC_API_KEY_ISSUER_ID ASC_API_KEY_P8_BASE64].each do |variable_name|
  if ENV[variable_name].to_s.empty?
    warn "Error: 環境変数 #{variable_name} が未設定"
    exit 2
  end
end

Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('ASC_API_KEY_ID'),
  issuer_id: ENV.fetch('ASC_API_KEY_ISSUER_ID'),
  key: Base64.decode64(ENV.fetch('ASC_API_KEY_P8_BASE64'))
)

# 署名に使う証明書を SHA-1 で選ぶ。更新した証明書と前の証明書が両方有効な間も、キーチェーンにある方を使うため。
# G2 の Developer ID Application は App Store Connect API の certificateType の絞り込みに使えないため (fastlane の
# spaceship/lib/spaceship/connect_api/models/certificate.rb)、絞り込まずに取り、型はここで見る。
certificate = Spaceship::ConnectAPI::Certificate.all.find do |candidate|
  [
    Spaceship::ConnectAPI::Certificate::CertificateType::DEVELOPER_ID_APPLICATION,
    Spaceship::ConnectAPI::Certificate::CertificateType::DEVELOPER_ID_APPLICATION_G2
  ].include?(candidate.certificate_type) &&
    Digest::SHA1.hexdigest(Base64.decode64(candidate.certificate_content)).upcase == certificate_sha1
end
if certificate.nil?
  warn "Error: SHA-1 が #{certificate_sha1} の Developer ID Application の証明書が App Store Connect に無い"
  exit 1
end

bundle_id = Spaceship::ConnectAPI::BundleId.find(BUNDLE_IDENTIFIER)
if bundle_id.nil?
  warn "Error: App ID #{BUNDLE_IDENTIFIER} が無い"
  exit 1
end

# profile の中身 (署名した plist) を読む。
def profile_plist(profile)
  pkcs7 = OpenSSL::PKCS7.new(Base64.decode64(profile.profile_content))
  pkcs7.verify([], OpenSSL::X509::Store.new, nil, OpenSSL::PKCS7::NOVERIFY)
  Plist.parse_xml(pkcs7.data)
end

# 配布に使えない理由の一覧。空なら使える。
def profile_problems(profile, certificate)
  problems = []
  problems << "状態が #{profile.profile_state}" unless profile.profile_state == Spaceship::ConnectAPI::Profile::ProfileState::ACTIVE
  # 期限が切れても API の状態が ACTIVE のまま返ることがあるため、期限も見る (fastlane の Profile#valid? と同じ判定)。
  problems << "期限切れ (#{profile.expiration_date})" unless Time.parse(profile.expiration_date) > Time.now
  problems << '署名に使う証明書を含まない' unless profile.certificates.any? { |included| included.id == certificate.id }
  entitlements = profile_plist(profile).fetch('Entitlements', {})
  unless Array(entitlements['com.apple.developer.icloud-container-identifiers']).include?(ICLOUD_CONTAINER_IDENTIFIER)
    problems << "iCloud コンテナ #{ICLOUD_CONTAINER_IDENTIFIER} を含まない (App ID にコンテナを紐付ける前に作った profile)"
  end
  problems << 'push (com.apple.developer.aps-environment) を含まない' unless entitlements.key?('com.apple.developer.aps-environment')
  problems
end

profile = Spaceship::ConnectAPI::Profile.all(filter: { name: PROFILE_NAME }, includes: 'certificates').first
if profile
  problems = profile_problems(profile, certificate)
  unless problems.empty?
    unless recreate
      warn "Error: profile「#{PROFILE_NAME}」を使えない: #{problems.join(' / ')}"
      warn '作り直すには --recreate を付けて実行する (今の profile を消す)'
      exit 1
    end
    profile.delete!
    profile = nil
  end
end
profile ||= Spaceship::ConnectAPI::Profile.create(
  name: PROFILE_NAME,
  profile_type: Spaceship::ConnectAPI::Profile::ProfileType::MAC_APP_DIRECT,
  bundle_id_id: bundle_id.id,
  certificate_ids: [certificate.id]
)
# 作った直後の応答には証明書が入らないため、確かめる前に読み直す。
profile = Spaceship::ConnectAPI::Profile.all(filter: { name: PROFILE_NAME }, includes: 'certificates').first
problems = profile_problems(profile, certificate)
unless problems.empty?
  warn "Error: 作った profile「#{PROFILE_NAME}」を使えない: #{problems.join(' / ')}"
  exit 1
end

FileUtils.mkdir_p(PROFILES_DIRECTORY)
File.binwrite(File.join(PROFILES_DIRECTORY, "#{profile.uuid}.provisionprofile"), Base64.decode64(profile.profile_content))
puts "PROFILE_UUID=#{profile.uuid}"
