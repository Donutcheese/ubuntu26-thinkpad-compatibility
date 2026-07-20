#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
dot -Tsvg compatibility-flow.dot -o compatibility-flow.svg
dot -Tpng -Gdpi=160 compatibility-flow.dot -o compatibility-flow.png
echo "Rendered compatibility-flow.svg and compatibility-flow.png"
