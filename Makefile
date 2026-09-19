.PHONY: check format run shots icon archive dmg help

DIR ?= docs/images
IDENTITY = $(shell sed -n 's/^CODE_SIGN_IDENTITY *= *//p' App/Config/Signing.xcconfig)

# Signs with the identity App/Config/Signing.xcconfig names when this Mac has it, and ad-hoc
# otherwise. The build number is the commit count, so Info.plist says which build is running.
XCODEBUILD = if security find-identity -v -p codesigning | grep -qF '"$(IDENTITY)"'; then sign=; else \
		sign=CODE_SIGN_IDENTITY=-; \
		echo 'note: no "$(IDENTITY)" signing identity — signed ad-hoc, so macOS asks for Desktop access again after every rebuild'; \
	fi; \
	xcodebuild -project App/Yongkang.xcodeproj -scheme Yongkang -derivedDataPath .build/xcode -quiet \
		CURRENT_PROJECT_VERSION=$$(git rev-list --count HEAD) $$sign

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
	@echo "built $(CURDIR)/.build/xcode/Yongkang.xcarchive/Products/Applications/Yongkang.app"

# The app beside an Applications link, so opening the image shows where to drag it. Archives
# first, so the image never holds a stale build.
dmg: archive ## Release disk image to drag into Applications; prints the .dmg path.
	@rm -rf .build/dmg && mkdir -p .build/dmg .build/release
	@ditto .build/xcode/Yongkang.xcarchive/Products/Applications/Yongkang.app .build/dmg/Yongkang.app
	@ln -s /Applications .build/dmg/Applications
	@hdiutil create -quiet -ov -volname Yongkang -srcfolder .build/dmg -format UDZO .build/release/Yongkang.dmg
	@echo "built $(CURDIR)/.build/release/Yongkang.dmg"

help: ## List the targets.
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | expand -t 10
