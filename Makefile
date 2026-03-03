APP_NAME = PinShot
BUNDLE_ID = com.elixirevo.PinShot
SRC_DIR = Sources
OUT_DIR = build
APP_BUNDLE = $(OUT_DIR)/$(APP_NAME).app
APP_INFO_PLIST = $(APP_BUNDLE)/Contents/Info.plist
DIST_DIR = dist
ARCH ?= $(shell uname -m)
DMG_PATH = $(DIST_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH).dmg
SWIFTC = swiftc
SWIFT_FLAGS = -O -sdk $(shell xcrun --show-sdk-path --sdk macosx) -target $(ARCH)-apple-macos12.0
VERSION ?= 1.0.0
BUILD ?= 1

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SRC_DIR)/*.swift Info.plist
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp Info.plist $(APP_INFO_PLIST)
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(APP_INFO_PLIST)
	plutil -replace CFBundleVersion -string "$(BUILD)" $(APP_INFO_PLIST)
	cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	$(SWIFTC) $(SWIFT_FLAGS) $(SRC_DIR)/*.swift -o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

release:
	@if [ -z "$(VERSION)" ] || [ -z "$(BUILD)" ]; then \
		echo "Usage: make release VERSION=1.0.0 BUILD=1 ARCH=arm64|x86_64"; \
		exit 1; \
	fi
	$(MAKE) clean
	$(MAKE) all VERSION=$(VERSION) BUILD=$(BUILD) ARCH=$(ARCH)
	@echo "Built $(APP_BUNDLE) with version $(VERSION) ($(BUILD)) for $(ARCH)"

dmg: release
	chmod +x scripts/create_dmg.sh
	./scripts/create_dmg.sh "$(APP_BUNDLE)" "$(DMG_PATH)" "$(APP_NAME)" "$(APP_NAME)"

clean:
	rm -rf $(OUT_DIR)
