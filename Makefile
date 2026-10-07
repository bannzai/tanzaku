XCODEPROJ := Tanzaku.xcodeproj
SCHEME := Tanzaku
CONFIGURATION := Debug
# 成果物のパスを決定的にし、システムの DerivedData を汚さないためリポジトリ内に置く。
DERIVED_DATA := tmp/DerivedData
# CI には署名 ID が無いため、CI は SIGNING_FLAGS を ad-hoc 署名の設定で上書きする (.github/workflows/ci.yml)。
SIGNING_FLAGS ?= -allowProvisioningUpdates

IOS_SCHEME := TanzakuiOS
PACKAGE_DIR := TanzakuKit

.PHONY: build-macos build-ios test dmg clean

build-macos:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=macOS' $(SIGNING_FLAGS) build

# 実機向けは provisioning profile が要り CI の ad-hoc 署名では通らないため、シミュレータ向けにビルドする。
build-ios:
	xcodebuild -project $(XCODEPROJ) -scheme $(IOS_SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS Simulator' $(SIGNING_FLAGS) build

test:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS' $(SIGNING_FLAGS) test
	cd $(PACKAGE_DIR) && xcodebuild -scheme TanzakuKit -derivedDataPath $(CURDIR)/$(DERIVED_DATA) -destination 'platform=macOS' $(SIGNING_FLAGS) test

# Developer ID で署名・公証・staple した Mac 版の DMG を tmp/distribution/Tanzaku-<版>.dmg に作る。必要な環境変数と証明書は AGENTS.md「Mac 版のリリース」。
dmg:
	bash scripts/macos/build_notarized_dmg.sh

clean:
	rm -rf $(DERIVED_DATA)

# Release ビルドを /Applications に配置して普段使いできるようにする
# Release にする理由・/Applications に置く理由・lsregister -f を打つ理由:
#   https://github.com/bannzai/PUTS/blob/main/documents/adr/0009-install-release-build-to-applications.md
# 起動は自動では行わない (ssh 越しの実行を想定)
.PHONY: macos
INSTALL_APP := /Applications/Tanzaku.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

macos:
	xcodebuild -project 'Tanzaku.xcodeproj' -scheme 'Tanzaku' \
		-configuration Release \
		-destination 'platform=macOS' \
		-derivedDataPath 'tmp/DerivedData' \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		build
	rm -rf $(INSTALL_APP)
	ditto 'tmp/DerivedData/Build/Products/Release/Tanzaku.app' $(INSTALL_APP)
	$(LSREGISTER) -f $(INSTALL_APP)
	@echo "起動するには: open $(INSTALL_APP)"

# Debug ビルドを Release と同じ /Applications/Tanzaku.app に上書き配置する。
# Debug ビルドにしか無い操作 (開発者メニュー等) を普段使いのデータに対して行うための一時的な配置で、
# 終わったら make macos で Release に戻す
# 起動は自動では行わない (ssh 越しの実行を想定)
.PHONY: macos-debug

macos-debug:
	xcodebuild -project 'Tanzaku.xcodeproj' -scheme 'Tanzaku' \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath 'tmp/DerivedData' \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		build
	rm -rf $(INSTALL_APP)
	ditto 'tmp/DerivedData/Build/Products/Debug/Tanzaku.app' $(INSTALL_APP)
	$(LSREGISTER) -f $(INSTALL_APP)
	@echo "起動するには: open $(INSTALL_APP)"
	@echo "Release に戻すには: make macos"

# 引数なしの make で macos を実行する (人が手で動作確認するための入口。検査・テストは CI が行う)
.DEFAULT_GOAL := macos

.PHONY: verify
# 前提の 3 つは同じ tmp/DerivedData を使うため、make -j でも直列に実行する (並列だと xcodebuild の build.db がロックで失敗する)
.NOTPARALLEL: verify
verify: build-macos build-ios test
