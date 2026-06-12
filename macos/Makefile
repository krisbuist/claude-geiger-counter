APP = Claude Geiger.app
BINARY = .build/release/ClaudeGeiger

.PHONY: build test app clean

build:
	swift build

test:
	swift run GeigerCoreTests

app:
	swift build -c release
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BINARY)" "$(APP)/Contents/MacOS/ClaudeGeiger"
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP) — open it or move it to /Applications"

clean:
	rm -rf .build "$(APP)"
