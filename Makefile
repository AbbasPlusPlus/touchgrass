APP      := TouchGrass
# System CLT SwiftPM is broken on this machine; use Homebrew toolchain.
SWIFT    ?= $(shell brew --prefix swift 2>/dev/null)/bin/swift
BUILD    := .build
CONFIG   ?= release
BIN      := $(BUILD)/$(CONFIG)/$(APP)
APPDIR   := build/$(APP).app
CONTENTS := $(APPDIR)/Contents

.PHONY: all build bundle run test clean debug kill install

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

run: kill bundle
	open $(APPDIR)

test:
	$(SWIFT) test

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(APPDIR) /Applications/$(APP).app
	@echo "Installed to /Applications/$(APP).app"

clean:
	rm -rf $(BUILD) build
