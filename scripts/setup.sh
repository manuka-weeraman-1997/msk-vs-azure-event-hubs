#!/usr/bin/env bash
# Create a local virtualenv, install producer and consumer dependencies, and
# copy example configs if they are missing. Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  PYTHON=python
fi

echo "Creating virtualenv in $ROOT/.venv"
"$PYTHON" -m venv .venv

if [ -f .venv/bin/activate ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
else
  # Windows (Git Bash)
  # shellcheck disable=SC1091
  source .venv/Scripts/activate
fi

python -m pip install --upgrade pip
python -m pip install -r producer/requirements.txt -r consumer/requirements.txt

for component in producer consumer; do
  example="$component/config/config.example.yaml"
  target="$component/config/config.yaml"
  if [ ! -f "$target" ]; then
    cp "$example" "$target"
    echo "Created $target from example (placeholders only, edit before use)"
  fi
done

if [ ! -f kafka/configs/client.properties ]; then
  cp kafka/configs/client.properties.example kafka/configs/client.properties
  echo "Created kafka/configs/client.properties from example"
fi

echo
echo "Done. Activate with: source .venv/bin/activate (or .venv/Scripts/activate)"
echo "Then set KAFKA_PLATFORM and the variables in producer/README.md."
