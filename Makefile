APP_NAME  = ClaudeStatus
BUILD_DIR = build
APP       = $(BUILD_DIR)/$(APP_NAME).app
BIN       = .build/release/$(APP_NAME)
# The macOS 27 SDK's SwiftUI macros (@State) need a SwiftUIMacros compiler
# plugin that Command Line Tools do not ship, so build against the 26.5 SDK.
SDK      ?= /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

.PHONY: build app run install check fixtures clean

build:
	SDKROOT=$(SDK) swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - $(APP)

run: app
	-pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP)

install: app
	-pkill -x $(APP_NAME) 2>/dev/null || true
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	cp -R $(APP) $(HOME)/Applications/
	open $(HOME)/Applications/$(APP_NAME).app

check: build
	$(BIN) --selftest $(FIXTURE)

fixtures:
	mkdir -p fixtures
	curl -s https://status.claude.com/ -o fixtures/homepage.html
	curl -s https://status.claude.com/api/v2/summary.json -o fixtures/summary.json
	curl -s "https://status.claude.com/uptime_showcase?components=$$(grep -o 'data-uptime-lazy="[a-z0-9]*"' fixtures/homepage.html | cut -d'"' -f2 | sort -u | paste -sd, -)" -o fixtures/uptime_showcase.json

clean:
	rm -rf .build $(BUILD_DIR) fixtures
