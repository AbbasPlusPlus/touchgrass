APP      := TouchGrass
# System CLT SwiftPM is broken on this machine; use Homebrew toolchain.
SWIFT    ?= $(shell brew --prefix swift 2>/dev/null)/bin/swift
BUILD    := .build
CONFIG   ?= release
BIN      := $(BUILD)/$(CONFIG)/$(APP)
# .noindex keeps Spotlight from listing the build artifact as a second copy of the app
APPDIR   := build.noindex/$(APP).app
CONTENTS := $(APPDIR)/Contents

.PHONY: all build bundle run test clean debug kill install release release-dry

all: bundle

build:
	$(SWIFT) build -c $(CONFIG)

debug:
	$(MAKE) CONFIG=debug bundle

bundle: build
	rm -rf $(APPDIR)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/$(APP)
	cp Support/Info.plist $(CONTENTS)/Info.plist
	@# SwiftPM resource bundles (TouchGrass_TGAudio.bundle etc.)
	@for b in $(BUILD)/$(CONFIG)/*.bundle; do [ -d "$$b" ] && cp -R "$$b" $(CONTENTS)/Resources/ || true; done
	@[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns || true
	codesign --force --sign - --entitlements Support/TouchGrass.entitlements $(APPDIR) 2>/dev/null || codesign --force --sign - $(APPDIR)
	@echo "→ $(APPDIR)"

kill:
	-pkill -x $(APP) 2>/dev/null || true

# run installs to /Applications first — launching from build.noindex would re-register
# a second copy with Launch Services (the "several versions installed" bug).
run: kill install
	open /Applications/$(APP).app

test:
	$(SWIFT) test

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(APPDIR) /Applications/$(APP).app
	@echo "Installed to /Applications/$(APP).app"

# Cuts a release: stamps VERSION into the bundle, zips it, publishes the GitHub release and
# pushes the appcast. `make release-dry VERSION=x.y.z` stops after the local zip + appcast.
release:
	@[ -n "$(VERSION)" ] || { echo "usage: make release VERSION=x.y.z" >&2; exit 1; }
	bash Support/release.sh $(VERSION)

release-dry:
	@[ -n "$(VERSION)" ] || { echo "usage: make release-dry VERSION=x.y.z" >&2; exit 1; }
	DRY_RUN=1 bash Support/release.sh $(VERSION)

clean:
	rm -rf $(BUILD) build build.noindex dist
