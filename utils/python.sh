#!/usr/bin/env bash

set -euo pipefail

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

. .venv/bin/activate
python -m pip install -r utils/requirements.txt

if [ "$#" -gt 0 ]; then
    exec "$@"
fi
