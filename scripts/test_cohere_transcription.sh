#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="$ROOT/test.txt"
INPUT="$ROOT/test.m4a"
WAV="$ROOT/.build/test.wav"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE" >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Missing $INPUT" >&2
  exit 1
fi

mkdir -p "$ROOT/.build"
ffmpeg -y -loglevel error -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV"

TRIAL_KEY="$(tr -d '\r\n' < "$KEY_FILE")"

curl -sS -X POST "https://api.cohere.com/v2/audio/transcriptions" \
  -H "Authorization: Bearer $TRIAL_KEY" \
  -F "model=cohere-transcribe-03-2026" \
  -F "language=en" \
  -F "file=@$WAV"
