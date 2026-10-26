.PHONY: generate build run release package install clean dev check

VERSION := 0.5.3
APP := build/Build/Products/Debug/Mindscape.app
RELEASE_APP := build-release/Build/Products/Release/Mindscape.app
DIST := dist
DMG := $(DIST)/Mindscape-$(VERSION).dmg
ZIP := $(DIST)/Mindscape-$(VERSION).zip

generate:
	xcodegen generate

build: generate
	xcodebuild -project Mindscape.xcodeproj -scheme Mindscape -configuration Debug -derivedDataPath build build

run: build
	open $(APP)

release: generate
	xcodebuild -project Mindscape.xcodeproj -scheme Mindscape -configuration Release -derivedDataPath build-release build

package: release
	rm -rf $(DIST)/staging $(DMG) $(ZIP)
	mkdir -p $(DIST)/staging
	cp -R $(RELEASE_APP) $(DIST)/staging/
	ln -s /Applications $(DIST)/staging/Applications
	hdiutil create -volname "Mindscape $(VERSION)" -srcfolder $(DIST)/staging -ov -format UDZO $(DMG)
	ditto -c -k --keepParent $(RELEASE_APP) $(ZIP)

install: package
	rm -rf /Applications/Mindscape.app
	ditto $(DIST)/staging/Mindscape.app /Applications/Mindscape.app
	xattr -dr com.apple.quarantine /Applications/Mindscape.app 2>/dev/null || true
	open /Applications/Mindscape.app

# 没有 Xcode 时的开发构建（只用 Command Line Tools）
dev:
	bash scripts/build-app.sh

# 本地能跑的全部检查
check:
	python3 -m unittest discover -s tests -v
	bash scripts/test-aibridge.sh
	bash scripts/typecheck.sh

clean:
	rm -rf build build-release dist Mindscape.xcodeproj
