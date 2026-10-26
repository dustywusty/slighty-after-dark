PROJECT := macos/slightly-after-dark.xcodeproj
SCHEME := slightly-after-dark
CONFIGURATION ?= Release
ASSET_ROOT := shared/after-dark-css
ASSET_REVISION := 20630dba51d49101dba0b52205400d31be9c0c37
BUILD_ROOT ?= $(CURDIR)/Build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData
PRODUCT_NAME := Slightly After Dark.saver
PRODUCT := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PRODUCT_NAME)
INSTALL_DIRECTORY ?= $(HOME)/Library/Screen Savers
INSTALLED_PRODUCT := $(INSTALL_DIRECTORY)/$(PRODUCT_NAME)
LEGACY_INSTALLED_PRODUCT := $(INSTALL_DIRECTORY)/slightly-after-dark.saver
MEMORY_TEST_SECONDS ?= 600
MEMORY_TEST_MAX_GROWTH_MIB ?= 32

.PHONY: bootstrap ensure-assets validate-assets previews build verify memory-test install open uninstall clean

bootstrap:
	git submodule update --init --recursive
	@actual=$$(git -C $(ASSET_ROOT) rev-parse HEAD); \
	if [ "$$actual" != "$(ASSET_REVISION)" ]; then \
		git -C $(ASSET_ROOT) cat-file -e "$(ASSET_REVISION)^{commit}" 2>/dev/null || \
			git -C $(ASSET_ROOT) fetch --quiet origin "$(ASSET_REVISION)"; \
		git -C $(ASSET_ROOT) switch --quiet --detach "$(ASSET_REVISION)"; \
	fi
	@$(MAKE) ensure-assets

ensure-assets:
	@if ! git -C $(ASSET_ROOT) rev-parse --verify HEAD >/dev/null 2>&1; then \
		echo "error: $(ASSET_ROOT) is not initialized; run 'make bootstrap'" >&2; \
		exit 1; \
	fi
	@actual=$$(git -C $(ASSET_ROOT) rev-parse HEAD); \
	if [ "$$actual" != "$(ASSET_REVISION)" ]; then \
		echo "error: $(ASSET_ROOT) is at $$actual, expected $(ASSET_REVISION); run 'make bootstrap'" >&2; \
		exit 1; \
	fi

validate-assets: ensure-assets
	/bin/sh shared/scripts/validate-assets.sh $(ASSET_ROOT)

previews: ensure-assets
	/bin/sh macos/scripts/capture-previews.sh

build: validate-assets
	xcodebuild \
		-quiet \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "generic/platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

verify: build
	/bin/sh macos/scripts/verify-bundle.sh "$(PRODUCT)"
	SAD_WEB_RENDERER=modern xcrun swift macos/scripts/runtime-smoke-test.swift "$(PRODUCT)"
	SAD_WEB_RENDERER=legacy xcrun swift macos/scripts/runtime-smoke-test.swift "$(PRODUCT)"

memory-test: build
	xcrun swift macos/scripts/memory-soak-test.swift "$(PRODUCT)" "$(MEMORY_TEST_SECONDS)" "$(MEMORY_TEST_MAX_GROWTH_MIB)"

install: verify
	/bin/mkdir -p "$(INSTALL_DIRECTORY)"
	/bin/rm -rf "$(INSTALLED_PRODUCT)"
	/bin/rm -rf "$(LEGACY_INSTALLED_PRODUCT)"
	/usr/bin/ditto "$(PRODUCT)" "$(INSTALLED_PRODUCT)"
	@/usr/bin/killall legacyScreenSaver >/dev/null 2>&1 || true
	@/usr/bin/killall legacyScreenSaver-x86_64 >/dev/null 2>&1 || true
	@echo "Installed $(INSTALLED_PRODUCT)"
	@echo "Select Slightly After Dark in System Settings → Wallpaper → Screen Saver."

open: verify
	/usr/bin/open "$(PRODUCT)"

uninstall:
	/bin/rm -rf "$(INSTALLED_PRODUCT)"
	/bin/rm -rf "$(LEGACY_INSTALLED_PRODUCT)"
	@/usr/bin/killall legacyScreenSaver >/dev/null 2>&1 || true
	@/usr/bin/killall legacyScreenSaver-x86_64 >/dev/null 2>&1 || true
	@echo "Removed $(INSTALLED_PRODUCT)"

clean:
	xcodebuild \
		-quiet \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "generic/platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		clean
	/bin/rm -rf "$(DERIVED_DATA)"
