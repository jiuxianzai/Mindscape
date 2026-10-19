.PHONY: generate build run clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project Mindscape.xcodeproj -scheme Mindscape -configuration Debug -derivedDataPath build build

run: build
	open build/Build/Products/Debug/Mindscape.app

clean:
	rm -rf build Mindscape.xcodeproj
