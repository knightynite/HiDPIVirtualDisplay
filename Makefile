# Makefile for HiDPI Virtual Display Tool
# Builds a command-line tool for creating virtual displays with HiDPI support

PRODUCT_NAME = hidpi-virtual-display
BUILD_DIR = build
SOURCES_DIR = Sources

# Source files
OBJC_SOURCES = $(SOURCES_DIR)/VirtualDisplayManager.m
SWIFT_SOURCES = $(SOURCES_DIR)/main.swift
HEADERS = $(SOURCES_DIR)/CGVirtualDisplayPrivate.h \
          $(SOURCES_DIR)/VirtualDisplayManager.h \
          $(SOURCES_DIR)/BridgingHeader.h

# Compiler settings
SWIFT_FLAGS = -O -whole-module-optimization
OBJC_FLAGS = -fobjc-arc -fmodules
COMMON_FLAGS = -framework Foundation -framework CoreGraphics

# Bridging header
BRIDGING_HEADER = $(SOURCES_DIR)/BridgingHeader.h

# Entitlements
ENTITLEMENTS = HiDPIVirtualDisplay.entitlements

# Target architecture (universal binary)
ARCH_FLAGS = -arch arm64 -arch x86_64

.PHONY: all clean install run debug release

all: release

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Debug build (faster compilation, includes debug symbols)
debug: $(BUILD_DIR)
	@echo "Building debug version..."
	swiftc $(SWIFT_SOURCES) $(OBJC_SOURCES) \
		-import-objc-header $(BRIDGING_HEADER) \
		-g -Onone \
		$(COMMON_FLAGS) \
		-o $(BUILD_DIR)/$(PRODUCT_NAME)
	@echo "Signing with entitlements..."
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(PRODUCT_NAME) || true
	@echo "Debug build complete: $(BUILD_DIR)/$(PRODUCT_NAME)"

# Release build (optimized, universal binary)
release: $(BUILD_DIR)
	@echo "Building release version..."
	swiftc $(SWIFT_SOURCES) $(OBJC_SOURCES) \
		-import-objc-header $(BRIDGING_HEADER) \
		$(SWIFT_FLAGS) \
		$(COMMON_FLAGS) \
		-o $(BUILD_DIR)/$(PRODUCT_NAME)
	@echo "Signing with entitlements..."
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(BUILD_DIR)/$(PRODUCT_NAME) || true
	@echo "Release build complete: $(BUILD_DIR)/$(PRODUCT_NAME)"

# Install to /usr/local/bin
install: release
	@echo "Installing to /usr/local/bin..."
	sudo cp $(BUILD_DIR)/$(PRODUCT_NAME) /usr/local/bin/
	sudo chmod +x /usr/local/bin/$(PRODUCT_NAME)
	@echo "Installed! Run with: $(PRODUCT_NAME)"

# Run the tool
run: debug
	./$(BUILD_DIR)/$(PRODUCT_NAME)

# Run with list command
list: debug
	./$(BUILD_DIR)/$(PRODUCT_NAME) list

# Run with presets command
presets: debug
	./$(BUILD_DIR)/$(PRODUCT_NAME) presets

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned build directory"

# Help
help:
	@echo "HiDPI Virtual Display Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build release version"
	@echo "  make debug    - Build debug version"
	@echo "  make release  - Build optimized release version"
	@echo "  make install  - Install to /usr/local/bin (requires sudo)"
	@echo "  make run      - Build and run"
	@echo "  make list     - Build and list displays"
	@echo "  make presets  - Build and show presets"
	@echo "  make clean    - Remove build artifacts"
	@echo ""
	@echo "Requirements:"
	@echo "  - macOS 11.0 or later"
	@echo "  - Xcode Command Line Tools"
	@echo "  - SIP may need to be disabled for private API access"
