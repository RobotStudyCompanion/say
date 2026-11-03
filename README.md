say — Simple Piper TTS Helper for Local Playback & Remote Streaming

(Part of the Robot Study Companion project)

Overview

say is a lightweight Bash helper that wraps the Piper TTS engine (via piper-tts) and provides:

🔊 Local speech playback via sox/play

📡 Remote audio streaming to another machine (e.g. a Raspberry Pi robot)

🎛️ Configurable model, length-scale, and gain

🚀 Portable script that works across machines via a stable venv path

This script is intended for RSC developers and researchers who need consistent, reproducible local speech synthesis during development.

Features

Uses Piper (pip-installed version, not Ubuntu’s piper package)

Accepts text via pipe, argument, or direct quotation

Automatically:

Generates WAV audio

Plays locally or streams to a target device

Resamples audio for network transmission

Validates that the correct Piper binary is being used

Fully self-contained (no need to modify .bashrc except for sourcing)

Installation
1. Create a dedicated virtual environment for Piper
python3 -m venv ~/Documents/RSC/piper-venv
source ~/Documents/RSC/piper-venv/bin/activate
pip install --upgrade pip
pip install piper-tts

2. Clone or create the say script

Place it inside:

~/Documents/RSC/scripts/say


Make it executable:

chmod +x ~/Documents/RSC/scripts/say

3. Add to your shell

Append to ~/.bashrc:

source "$HOME/Documents/RSC/scripts/say"


Reload:

source ~/.bashrc

Usage
Local playback
say "hello there"

Stream to a remote device
say "robot, wake up" raspberrypi.local

Custom port
say "testing" raspberrypi.local:5000

Optional Environment Variables

Override defaults:

export PIPER_MODEL=~/.local/share/piper/voices/en_US-amy-medium.onnx
export PIPER_LEN=1.1
export PIPER_GAIN_DB=4


These can also be set per-command:

PIPER_GAIN_DB=5 say "this is louder"

Requirements

piper-tts (pip version — not apt install piper)

sox and play

nc (netcat)

To install:

sudo apt install sox netcat
