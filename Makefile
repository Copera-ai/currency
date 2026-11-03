# Copera Currency for macOS. Requires Xcode, xcodegen and (optionally) swiftlint (Homebrew).
PROJECT      := CoperaCurrency.xcodeproj
SCHEME       := CoperaCurrency
DERIVED_DATA := build/DerivedData
APP          := $(DERIVED_DATA)/Build/Products/Debug/Copera Currency.app
KIT          := Packages/CurrencyKit

.PHONY: gen build run test lint release publish sparkle-key clean

gen:
	xcodegen generate --spec project.yml

# Unsigned Debug build (no signing identity needed), Apple Silicon only.
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO build

run: build
	open "$(APP)"

# All logic (and its tests) lives in the CurrencyKit package.
test:
	cd "$(KIT)" && swift test

lint:
	@if command -v swiftlint >/dev/null 2>&1; then swiftlint lint --strict; \
	else echo "swiftlint not installed (brew install swiftlint): skipping"; fi

# Signed + notarized DMG and zip in build/release/dist (nothing is uploaded).
# Usage: make release VERSION=x.y.z [BUILD=n] [SKIP_NOTARIZE=1]
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z [BUILD=n] [SKIP_NOTARIZE=1]"; exit 1; }
	scripts/release.sh "$(VERSION)" $(if $(BUILD),--build "$(BUILD)") \
		$(if $(filter 1,$(SKIP_NOTARIZE)),--skip-notarize)

# Build, notarize, tag v<x.y.z> and create the GitHub release (with the Sparkle appcast).
# Usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]
publish:
	@test -n "$(VERSION)" || { echo "usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]"; exit 1; }
	VERSION="$(VERSION)" YES="$(YES)" DRY_RUN="$(DRY_RUN)" scripts/publish.sh

# Print the Sparkle EdDSA public key (SUPublicEDKey); creates the key on first use.
sparkle-key:
	@"$$(scripts/sparkle-tools.sh)/generate_keys" --account copera-currency >/dev/null 2>&1 || true
	@"$$(scripts/sparkle-tools.sh)/generate_keys" --account copera-currency -p

clean:
	rm -rf build $(PROJECT) $(KIT)/.build
