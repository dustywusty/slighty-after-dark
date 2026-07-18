PROJECT := slightly-after-dark.xcodeproj
SCHEME := slightly-after-dark
CONFIGURATION ?= Release
ASSET_REVISION := 20630dba51d49101dba0b52205400d31be9c0c37
BUILD_ROOT ?= $(CURDIR)/Build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData
PRODUCT_NAME := Slightly After Dark.saver
PRODUCT := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PRODUCT_NAME)
INSTALL_DIRECTORY ?= $(HOME)/Library/Screen Savers
INSTALLED_PRODUCT := $(INSTALL_DIRECTORY)/$(PRODUCT_NAME)
LEGACY_INSTALLED_PRODUCT := $(INSTALL_DIRECTORY)/slightly-after-dark.saver

.PHONY: bootstrap ensure-assets validate-assets previews build verify install open uninstall clean

bootstrap:
	git submodule update --init --recursive
	@actual=$$(git -C after-dark-css rev-parse HEAD); \
	if [ "$$actual" != "$(ASSET_REVISION)" ]; then \
		git -C after-dark-css cat-file -e "$(ASSET_REVISION)^{commit}" 2>/dev/null || \
			git -C after-dark-css fetch --quiet origin "$(ASSET_REVISION)"; \
		git -C after-dark-css switch --quiet --detach "$(ASSET_REVISION)"; \
	fi
	@$(MAKE) ensure-assets

ensure-assets:
	@if ! git -C after-dark-css rev-parse --verify HEAD >/dev/null 2>&1; then \
		echo "error: after-dark-css is not initialized; run 'make bootstrap'" >&2; \
		exit 1; \
	fi
	@actual=$$(git -C after-dark-css rev-parse HEAD); \
	if [ "$$actual" != "$(ASSET_REVISION)" ]; then \
		echo "error: after-dark-css is at $$actual, expected $(ASSET_REVISION); run 'make bootstrap'" >&2; \
		exit 1; \
	fi

validate-assets: ensure-assets
	/bin/sh scripts/validate-assets.sh after-dark-css

previews: ensure-assets
	/bin/sh scripts/capture-previews.sh

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
	/bin/sh scripts/verify-bundle.sh "$(PRODUCT)"
	SAD_WEB_RENDERER=modern xcrun swift scripts/runtime-smoke-test.swift "$(PRODUCT)"
	SAD_WEB_RENDERER=legacy xcrun swift scripts/runtime-smoke-test.swift "$(PRODUCT)"

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
