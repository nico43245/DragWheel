#!/bin/bash
# Same as fetch-model.ps1, for building the Windows app from macOS or Linux.
set -euo pipefail
url='https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx'
sha256='309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8'
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/models"
file="$dir/u2netp.onnx"
mkdir -p "$dir"
if [ ! -f "$file" ] || [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$sha256" ]; then
    echo "Downloading u2netp.onnx…"
    curl -fsSL "$url" -o "$file"
fi
actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
if [ "$actual" != "$sha256" ]; then rm -f "$file"; echo "Checksum mismatch: $actual" >&2; exit 1; fi
echo "✓ models/u2netp.onnx ($sha256)"
