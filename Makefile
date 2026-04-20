.PHONY: build run dev python clean

SCHEME   = Jarvis
PROJECT  = Jarvis/Jarvis.xcodeproj
BUILD_DIR = build/Jarvis.app

# ── Swift ─────────────────────────────────────────────────────────────────────

build:
	cd Jarvis && xcodegen generate --quiet
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Debug \
	  -derivedDataPath build/DerivedData \
	  CODE_SIGNING_ALLOWED=NO \
	  | grep -E "^(Build|error:|warning:|Compiling|Linking)" || true

run: build
	open build/DerivedData/Build/Products/Debug/Jarvis.app

# ── Python ────────────────────────────────────────────────────────────────────

install-python:
	pip3 install -r Python/requirements.txt

python:
	cd Python && python3 gateway.py

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
