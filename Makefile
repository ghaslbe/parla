.PHONY: build app run debug clean

# Build a release .app bundle.
app:
	@bash scripts/bundle.sh release

# Build + launch the app.
run: app
	@echo "==> launching Parla.app"
	@open Parla.app

# Fast debug bundle.
debug:
	@bash scripts/bundle.sh debug

# Just compile (no bundle).
build:
	swift build -c release

clean:
	swift package clean
	rm -rf Parla.app .build
