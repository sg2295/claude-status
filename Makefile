APP_NAME  = ClaudeStatus
BUILD_DIR = build
APP       = $(BUILD_DIR)/$(APP_NAME).app
BIN       = .build/release/$(APP_NAME)

.PHONY: build app run install check fixtures clean

build:
	swift build -c release

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

clean:
	rm -rf .build $(BUILD_DIR) fixtures
