.PHONY: check format run shots icon archive dmg release help

DIR ?= docs/images
# A release overrides both: the Developer ID identity's full name, and its team.
IDENTITY ?= $(shell sed -n 's/^CODE_SIGN_IDENTITY *= *//p' App/Config/Signing.xcconfig)
TEAM ?=
# The newest v* tag is the version, so tagging is all a release has to do to name itself.
VERSION ?= $(or $(shell git describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//'),0.0.0)
# How notarytool signs in: a profile saved once with `xcrun notarytool store-credentials
# yongkang`; CI passes its API key's flags instead (docs/release.md).
NOTARY ?= --keychain-profile yongkang
ARCHIVED = .build/xcode/Yongkang.xcarchive/Products/Applications/Yongkang.app

# Signs with IDENTITY when this Mac has it, and ad-hoc otherwise. The build number is the commit
# count, which only grows, so Sparkle can tell every build from the one before it.
XCODEBUILD = if security find-identity -v -p codesigning | grep -qF '"$(IDENTITY)"'; then \
		sign='CODE_SIGN_IDENTITY=$(IDENTITY)'; else \
		sign=CODE_SIGN_IDENTITY=-; \
		echo 'note: no "$(IDENTITY)" signing identity — signed ad-hoc, so macOS asks for Desktop access again after every rebuild'; \
	fi; \
	xcodebuild -project App/Yongkang.xcodeproj -scheme Yongkang -derivedDataPath .build/xcode -quiet \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$$(git rev-list --count HEAD) "$$sign" \
		$(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM))

# The app beside an Applications link, so opening the image shows where to drag it.
define image
	@rm -rf .build/dmg && mkdir -p .build/dmg .build/release
	@ditto $(1) .build/dmg/Yongkang.app
	@ln -s /Applications .build/dmg/Applications
	@hdiutil create -quiet -ov -volname Yongkang -srcfolder .build/dmg -format UDZO .build/release/Yongkang.dmg
endef

check: ## The definition of done: format lint, build, test.
	swift format lint --strict -r Sources Tests
	swift build
	swift test

format: ## Fix what `make check` lints.
	swift format -i -r Sources Tests

run: ## Debug build of the app, then open it. Refuses while Yongkang is running.
	@# `open` would only bring the running copy forward, and quitting it would end every agent
	@# session inside it. The pre-2.4 bundle ID counts too: two copies would share the projects.
	@for id in ai.yongkang.Yongkang local.yongkang.app; do \
		if [ -n "$$(lsappinfo find bundleid=$$id)" ]; then \
			echo "Yongkang ($$id) is running: quit Yongkang first — it would take its agent sessions with it"; \
			exit 1; \
		fi; \
	done
	@$(XCODEBUILD) -configuration Debug -destination "platform=macOS,arch=$$(uname -m)" build
	open .build/xcode/Build/Products/Debug/Yongkang.app

shots: ## Render every screen offscreen: make shots DIR=docs/images
	swift run shots $(DIR)

icon: ## Redraw the app icon's 1024 master from AppIcon.swift.
	swift run shots --icon App/Yongkang/Assets.xcassets/AppIcon.appiconset/icon-1024.png

archive: ## Signed Release build; prints the .app path.
	@$(XCODEBUILD) -configuration Release -destination generic/platform=macOS \
		-archivePath .build/xcode/Yongkang.xcarchive archive
	@echo "built $(CURDIR)/$(ARCHIVED)"

# Archives first, so the image never holds a stale build. Only for this Mac: nothing in it is
# notarized, so Gatekeeper stops it anywhere else. `make release` makes the one to hand out.
dmg: archive ## Local disk image to drag into Applications; prints the .dmg path.
	$(call image,$(ARCHIVED))
	@echo "built $(CURDIR)/.build/release/Yongkang.dmg"

# What the release workflow runs on a v* tag, and what you run to debug it: make release
# IDENTITY="Developer ID Application: … (TEAM)" TEAM=TEAM. The app is notarized and stapled on
# its own before it goes in the image, because it leaves the image — dragged out, or unpacked by
# Sparkle — and has to pass Gatekeeper offline from then on. Then the image, for the download.
release: archive ## Developer ID, notarized and stapled dmg for the website and Sparkle.
	@rm -rf .build/export
	xcodebuild -exportArchive -archivePath .build/xcode/Yongkang.xcarchive -exportPath .build/export \
		-exportOptionsPlist App/Config/ExportOptions.plist -quiet
	ditto -c -k --keepParent .build/export/Yongkang.app .build/export/Yongkang.zip
	xcrun notarytool submit .build/export/Yongkang.zip $(NOTARY) --wait
	xcrun stapler staple .build/export/Yongkang.app
	$(call image,.build/export/Yongkang.app)
	codesign --sign "$(IDENTITY)" --timestamp .build/release/Yongkang.dmg
	xcrun notarytool submit .build/release/Yongkang.dmg $(NOTARY) --wait
	xcrun stapler staple .build/release/Yongkang.dmg
	@echo "built $(CURDIR)/.build/release/Yongkang.dmg ($(VERSION))"

help: ## List the targets.
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | expand -t 10
