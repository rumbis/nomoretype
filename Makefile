APP_NAME := TranscriptionApp
BUNDLE_ID := com.influro.transcriptionapp
BUILD_DIR := .build
RESOURCES_DIR := Resources
APP_BUNDLE := $(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources

SOURCES := Sources/TranscriptionApp/*.swift

.PHONY: all build clean run

all: build

# Build with SwiftPM
build:
	@echo "Building $(APP_NAME)..."
	swift build -c release --disable-sandbox
	@echo "Creating app bundle..."
	@mkdir -p "$(APP_MACOS)" "$(APP_RESOURCES)"
	@cp "$(BUILD_DIR)/release/$(APP_NAME)" "$(APP_MACOS)/$(APP_NAME)"
	@cp "$(RESOURCES_DIR)/Info.plist" "$(APP_CONTENTS)/Info.plist"
	@echo "Creating PkgInfo..."
	@echo "APPL????" > "$(APP_CONTENTS)/PkgInfo"
	@echo "Codesigning..."
	@codesign --force --deep --sign "DevCert" "$(APP_BUNDLE)" 2>/dev/null || true
	@echo "✅ $(APP_BUNDLE) created successfully"

# Run the app
run: build
	@echo "Launching $(APP_NAME)..."
	@open "$(APP_BUNDLE)"

# Clean build artifacts
clean:
	@rm -rf "$(BUILD_DIR)"
	@rm -rf "$(APP_BUNDLE)"
	@echo "Cleaned"

# Force rebuild
rebuild: clean build
