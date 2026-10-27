.PHONY: generate build run release package publish install cli install-cli clean

# 单一版本来源：project.yml 的 MARKETING_VERSION。发布 beta 时传 PRERELEASE=1。
VERSION := $(shell awk -F'"' '/MARKETING_VERSION:/ {print $$2; exit}' project.yml)
APP := build/Build/Products/Debug/Mindscape.app
RELEASE_APP := build-release/Build/Products/Release/Mindscape.app
DIST := dist
DMG := $(DIST)/Mindscape-$(VERSION).dmg
ZIP := $(DIST)/Mindscape-$(VERSION).zip
SHA := $(DMG).sha256
NOTES := $(DIST)/release-notes.md
CLI_DERIVED := build-cli
CLI_BIN := $(CLI_DERIVED)/Build/Products/Release/mindscape
PRERELEASE ?= 0
PREFIX ?= /usr/local/bin

generate:
	xcodegen generate

build: generate
	xcodebuild -project Mindscape.xcodeproj -scheme Mindscape -configuration Debug -derivedDataPath build build

run: build
	open $(APP)

release: generate
	xcodebuild -project Mindscape.xcodeproj -scheme Mindscape -configuration Release -derivedDataPath build-release build

package: release
	rm -rf $(DIST)/staging $(DMG) $(ZIP) $(SHA)
	mkdir -p $(DIST)/staging
	cp -R $(RELEASE_APP) $(DIST)/staging/
	ln -s /Applications $(DIST)/staging/Applications
	hdiutil create -volname "Mindscape $(VERSION)" -srcfolder $(DIST)/staging -ov -format UDZO $(DMG)
	ditto -c -k --keepParent $(RELEASE_APP) $(ZIP)
	shasum -a 256 $(DMG) > $(SHA)

publish: package
	@test -n "$(VERSION)" || (echo "VERSION 为空"; exit 1)
	@grep -q "MARKETING_VERSION: \"$(VERSION)\"" project.yml || (echo "project.yml 的 MARKETING_VERSION 不是 $(VERSION)"; exit 1)
	@grep -q "^## \[$(VERSION)\]" CHANGELOG.md || (echo "CHANGELOG.md 缺少 $(VERSION) 段落"; exit 1)
	@awk '/^## \[$(VERSION)\]/{flag=1; next} /^## \[/{flag=0} flag' CHANGELOG.md > $(NOTES)
	gh release create v$(VERSION) $(DMG) $(ZIP) $(SHA) \
		--title "Mindscape $(VERSION)" \
		--notes-file $(NOTES) \
		$(if $(filter 1 true yes,$(PRERELEASE)),--prerelease)

cli: generate
	xcodebuild -project Mindscape.xcodeproj -scheme MindscapeCLI -configuration Release -derivedDataPath $(CLI_DERIVED) build

install-cli: cli
	install -d "$(PREFIX)"
	install -m 755 $(CLI_BIN) "$(PREFIX)/mindscape"

install: package
	rm -rf /Applications/Mindscape.app
	ditto $(DIST)/staging/Mindscape.app /Applications/Mindscape.app
	xattr -dr com.apple.quarantine /Applications/Mindscape.app 2>/dev/null || true
	open /Applications/Mindscape.app

clean:
	rm -rf build build-release build-cli dist Mindscape.xcodeproj
