.PHONY: build run stop dev python clean

SCHEME   = Jarvis
PROJECT  = Jarvis/Jarvis.xcodeproj
BUILD_DIR = build/Jarvis.app
DEVELOPMENT_TEAM ?= K53J9V75NJ
CODE_SIGN_IDENTITY ?= Apple Development

# ── Swift ─────────────────────────────────────────────────────────────────────

build:
	python3 scripts/generate_swift_contracts.py
	cd Jarvis && xcodegen generate --quiet
	mkdir -p build
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Debug \
	  -derivedDataPath build/DerivedData \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  CODE_SIGN_STYLE=Automatic \
	  CODE_SIGNING_ALLOWED=YES \
	  CODE_SIGNING_REQUIRED=YES \
	  CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" \
	  > build/xcodebuild.log 2>&1
	@grep -E "^(\*\* BUILD|Build|error:|warning:|Compiling|Linking)" build/xcodebuild.log || true

run: build
	open build/DerivedData/Build/Products/Debug/Jarvis.app

stop:
	scripts/stop_jarvis.sh

# ── Python ────────────────────────────────────────────────────────────────────

venv:
	python3 -m venv Python/.venv
	Python/.venv/bin/pip install -r Python/requirements.txt

python:
	cd Python && .venv/bin/python gateway.py

# ── Dev（两个进程一起启动）────────────────────────────────────────────────────

dev:
	@echo "Starting Python gateway..."
	cd Python && python3 gateway.py &
	@sleep 1
	@echo "Launching Jarvis..."
	open build/DerivedData/Build/Products/Debug/Jarvis.app

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf build/DerivedData
