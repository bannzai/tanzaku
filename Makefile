XCODEPROJ := Tanzaku.xcodeproj
SCHEME := Tanzaku
CONFIGURATION := Debug
# 成果物のパスを決定的にし、システムの DerivedData を汚さないためリポジトリ内に置く。
DERIVED_DATA := tmp/DerivedData
# CI には署名 ID が無いため、CI は SIGNING_FLAGS を ad-hoc 署名の設定で上書きする (.github/workflows/ci.yml)。
SIGNING_FLAGS ?= -allowProvisioningUpdates

IOS_SCHEME := TanzakuiOS
PACKAGE_DIR := TanzakuKit

.PHONY: build-macos build-ios test clean

build-macos:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=macOS' $(SIGNING_FLAGS) build

# 実機向けは provisioning profile が要り CI の ad-hoc 署名では通らないため、シミュレータ向けにビルドする。
build-ios:
	xcodebuild -project $(XCODEPROJ) -scheme $(IOS_SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS Simulator' $(SIGNING_FLAGS) build

test:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS' $(SIGNING_FLAGS) test
	cd $(PACKAGE_DIR) && xcodebuild -scheme TanzakuKit -derivedDataPath $(CURDIR)/$(DERIVED_DATA) -destination 'platform=macOS' $(SIGNING_FLAGS) test

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
