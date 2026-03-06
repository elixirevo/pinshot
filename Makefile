APP_NAME = PinShot
BUNDLE_ID = com.elixirevo.PinShot
SRC_DIR = Sources
OUT_DIR = build
APP_BUNDLE = $(OUT_DIR)/$(APP_NAME).app
APP_INFO_PLIST = $(APP_BUNDLE)/Contents/Info.plist
DIST_DIR = dist
ARCH ?= $(shell uname -m)
ARCHS = arm64 x86_64
DMG_PATH = $(DIST_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH).dmg
UNIVERSAL_DMG_PATH = $(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.dmg
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

universal:
	@if [ -z "$(VERSION)" ] || [ -z "$(BUILD)" ]; then \
		echo "Usage: make universal VERSION=1.0.1 BUILD=1"; \
		exit 1; \
	fi
	rm -rf artifacts/arm64 artifacts/x86_64 $(APP_BUNDLE)
	$(MAKE) all VERSION=$(VERSION) BUILD=$(BUILD) ARCH=arm64 OUT_DIR=artifacts/arm64
	$(MAKE) all VERSION=$(VERSION) BUILD=$(BUILD) ARCH=x86_64 OUT_DIR=artifacts/x86_64
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp -R artifacts/arm64/$(APP_NAME).app/Contents/* $(APP_BUNDLE)/Contents/
	lipo -create \
		artifacts/arm64/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) \
		artifacts/x86_64/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) \
		-output $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@echo "Built universal app: $(APP_BUNDLE)"

sign-adhoc: universal
	codesign --force --deep --sign - --timestamp=none "$(APP_BUNDLE)"
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	@echo "Signed app with ad-hoc identity"

dmg-universal: sign-adhoc
	chmod +x scripts/create_dmg.sh
	./scripts/create_dmg.sh "$(APP_BUNDLE)" "$(UNIVERSAL_DMG_PATH)" "$(APP_NAME)" "$(APP_NAME)"
	codesign --force --sign - --timestamp=none "$(UNIVERSAL_DMG_PATH)"
	@echo "Created and signed universal DMG: $(UNIVERSAL_DMG_PATH)"

clean:
	rm -rf $(OUT_DIR)
