#!/usr/bin/env bash
set -e

echo "============================================================"
echo "        RSC Toolkit – TTS (Piper) Bootstrap Installer"
echo "============================================================"

# Resolve BASE_DIR to the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"

VENV_DIR="$BASE_DIR/venv"
BIN_DIR="$BASE_DIR/bin"
VOICE_DIR="$BASE_DIR/voices"
CONFIG_DIR="$BASE_DIR/config"

SAY_SCRIPT="$BIN_DIR/say"
CONFIG_FILE="$CONFIG_DIR/say.conf"

DEFAULT_VOICE_NAME="en_US-amy-medium.onnx"
# Direct download (NOT the /blob/ URL)
DEFAULT_VOICE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx"
DEFAULT_VOICE_JSON_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json"

echo "[1/8] Preparing directory structure..."

mkdir -p "$BIN_DIR"
mkdir -p "$VOICE_DIR"
mkdir -p "$CONFIG_DIR"

echo "Base directory: $BASE_DIR"
echo "Venv directory: $VENV_DIR"
echo "Voices directory: $VOICE_DIR"
echo "Config directory: $CONFIG_DIR"
echo

# ------------------------------------------------------------
# 2. Check for required tools (play from sox, nc)
# ------------------------------------------------------------
echo "[2/8] Checking required tools (sox/play, nc)..."

MISSING=0

if ! command -v play >/dev/null 2>&1; then
    echo "  - 'play' not found (from 'sox' package)."
    MISSING=1
fi

if ! command -v nc >/dev/null 2>&1; then
    echo "  - 'nc' (netcat) not found."
    MISSING=1
fi

if [[ $MISSING -eq 1 ]]; then
    echo
    echo "Please install the missing tools, e.g. on Ubuntu:"
    echo "  sudo apt install sox netcat"
    echo
    read -rp "Press Enter to continue once installed (or Ctrl+C to abort)..."
fi

echo "Tool check complete."
echo

# ------------------------------------------------------------
# 3. Create (or rebuild) virtual environment
# ------------------------------------------------------------
echo "[3/8] Creating virtual environment at: $VENV_DIR"

if [[ -d "$VENV_DIR" ]]; then
    echo "Existing venv found."
    read -rp "Rebuild it? This will delete and recreate it. [y/N] " rebuild
    if [[ "$rebuild" =~ ^[Yy]$ ]]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
    else
        echo "Keeping existing venv."
    fi
else
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing piper-tts into venv..."
pip install piper-tts

echo "Venv setup complete."
echo

# ------------------------------------------------------------
# 4. Verify Piper CLI has --model
# ------------------------------------------------------------
PIPER_BIN="$VENV_DIR/bin/piper"

echo "[4/8] Verifying Piper CLI..."

if ! "$PIPER_BIN" --help | grep -q -- "--model"; then
    echo "ERROR: Piper in venv does not support --model."
    echo "       This likely means the wrong 'piper' package is installed."
    echo "       Ensure you're using 'piper-tts'."
    exit 1
fi

echo "Piper CLI looks good."
echo

# ------------------------------------------------------------
# 5. Create default config file
# ------------------------------------------------------------
echo "[5/8] Creating default config (if missing)..."

if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
# RSC TTS (say) configuration
# Values are simple bash KEY="value" entries.

voice="$DEFAULT_VOICE_NAME"
length_scale="0.99"
gain_db="2"
remote_host="raspberrypi.local"
remote_port="12345"
EOF
    echo "Created config: $CONFIG_FILE"
else
    echo "Config already exists, leaving as-is: $CONFIG_FILE"
fi

echo

# ------------------------------------------------------------
# 6. Ensure default voice model exists
# ------------------------------------------------------------
echo "[6/8] Checking for default voice model..."

VOICE_PATH="$VOICE_DIR/$DEFAULT_VOICE_NAME"

if [[ -f "$VOICE_PATH" ]]; then
    echo "Voice model already present: $VOICE_PATH"
else
    echo "Default voice model not found at:"
    echo "  $VOICE_PATH"
    read -rp "Download en_US-amy-medium.onnx from HuggingFace now? [Y/n] " dl
    if [[ ! "$dl" =~ ^[Nn]$ ]]; then
        echo "Downloading..."
        # you can use curl or wget; here we use wget if available
        if command -v wget >/dev/null 2>&1; then
            wget -O "$VOICE_PATH" "$DEFAULT_VOICE_URL"
            wget -O "$VOICE_PATH" "$DEFAULT_VOICE_JSON_URL"
        # then trying curl if wget unavailable
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "$VOICE_PATH" "$DEFAULT_VOICE_URL"
            curl -L -o "$VOICE_PATH" "$DEFAULT_VOICE_JSON_URL"
        else
            echo "Neither wget nor curl found. Please install one and run again."
            exit 1
        fi
        echo "Downloaded voice to: $VOICE_PATH"
    else
        echo "Skipping download. Make sure to place $DEFAULT_VOICE_NAME in:"
        echo "  $VOICE_DIR"
    fi
fi

echo

# ------------------------------------------------------------
# 7. Create the 'say' script
# ------------------------------------------------------------
echo "[7/8] Installing 'say' script..."

cat > "$SAY_SCRIPT" << 'EOF'
#!/usr/bin/env bash

# RSC Toolkit – TTS helper: say
# Uses Piper (piper-tts) in a local venv and voices stored inside the toolkit.

# Resolve base dir (../ from this script, assuming bin/say)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VENV_DIR="$BASE_DIR/venv"
PIPER_BIN="$VENV_DIR/bin/piper"

CONFIG_FILE="$BASE_DIR/config/say.conf"
VOICE_DIR="$BASE_DIR/voices"

# Load config if present
voice="en_US-amy-medium.onnx"
length_scale="0.99"
gain_db="2"
remote_host="raspberrypi.local"
remote_port="12345"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

DEFAULT_MODEL="$VOICE_DIR/$voice"

say() {
    local text="$1"; shift || true
    local target="${1:-local}"

    if [[ -z "$text" ]]; then
        echo "[say] ERROR: No text provided."
        echo "Usage: say \"hello world\" [host|host:port]"
        return 1
    fi

    # Check Piper binary exists
    if [[ ! -x "$PIPER_BIN" ]]; then
        echo "[say] ERROR: Piper binary missing at: $PIPER_BIN"
        echo "[say] Run the TTS installer again: tts/install.sh"
        return 1
    fi

    # Quick sanity check for CLI compatibility
    if ! "$PIPER_BIN" --help | grep -q -- "--model"; then
        echo "[say] ERROR: Piper binary does not support --model. Wrong version?"
        return 1
    fi

    # Check model file
    if [[ ! -f "$DEFAULT_MODEL" ]]; then
        echo "[say] ERROR: Voice model not found at: $DEFAULT_MODEL"
        echo "[say] Make sure the .onnx file is in: $VOICE_DIR"
        return 1
    fi

    # Call Piper, feed text via stdin for compatibility with different versions
    "$PIPER_BIN" \
        --model "$DEFAULT_MODEL" \
        --length_scale "$length_scale" \
        --output_file - \
    <<< "$text" \
    | {
        if [[ "$target" == "local" ]]; then
            # Local playback
            play -t wav -
        else
            # Remote streaming
            local host="${target%:*}"
            local port="${target#*:}"
            [[ "$host" == "$port" ]] && port="$remote_port"

            sox -t wav - -t wav - rate -v 24000 tempo 0.95 gain -n "$gain_db" \
            | nc -q 0 "$host" "$port"
        fi
    }
}

# If script invoked directly, run say() with args.
if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
    say "$@"
fi
EOF

chmod +x "$SAY_SCRIPT"

echo "'say' script installed at: $SAY_SCRIPT"
echo

# ------------------------------------------------------------
# 8. Offer to add to ~/.bashrc
# ------------------------------------------------------------
echo "[8/8] Add 'say' to your shell (source in ~/.bashrc)..."

BASHRC="$HOME/.bashrc"
SOURCE_LINE="source \"$SAY_SCRIPT\""

if grep -Fq "$SOURCE_LINE" "$BASHRC" 2>/dev/null; then
    echo "Entry already present in $BASHRC, skipping."
else
    read -rp "Add 'source bin/say' to your ~/.bashrc? [Y/n] " addbash
    if [[ ! "$addbash" =~ ^[Nn]$ ]]; then
        echo >> "$BASHRC"
        echo "# RSC Toolkit – TTS" >> "$BASHRC"
        echo "$SOURCE_LINE" >> "$BASHRC"
        echo "Added to $BASHRC"
        # Auto source .bashrc if user agrees
        echo
        read -rp "Source ~/.bashrc now to enable 'say'? [Y/n] " src
        if [[ ! "$src" =~ ^[Nn]$ ]]; then
            # shellcheck disable=SC1090
            source "$HOME/.bashrc"
            echo "Reloaded ~/.bashrc"
        else
            echo "Open a new shell or run: source ~/.bashrc"
        fi
    else
        echo "Skipping .bashrc modification. You can manually add:"
        echo "  $SOURCE_LINE"
    fi
fi


echo
echo "============================================================"
echo "Installation complete!"
echo
echo "Try in a new shell (or after 'source ~/.bashrc'):"
echo "  say \"Hello, world!\""
echo "============================================================"
