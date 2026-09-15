# ponytail: check and format only for now; run, shots and archive arrive with the Xcode
# shell (refactor plan PR 2.4), which replaces make-app.sh.
.PHONY: check format

check: ## The definition of done: format lint, build, test.
	swift format lint --strict -r Sources Tests
	swift build
	swift test

format: ## Fix what `make check` lints.
	swift format -i -r Sources Tests
