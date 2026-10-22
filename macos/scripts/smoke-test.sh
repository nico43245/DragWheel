#!/bin/bash
# Runs every conversion through `DragWheel --run` on generated sample files and checks the results.
# Usage: scripts/smoke-test.sh [path/to/DragWheel.app]
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$DIR/build/DragWheel.app}"
BIN="$APP/Contents/MacOS/DragWheel"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

pass=0
fail=0
check() { # check <description> <command…>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); echo "  ✓ $name"
    else fail=$((fail + 1)); echo "  ✗ $name"; fi
}
run() { "$BIN" --run "$@" 2>/dev/null; }
is_format() { [ "$(sips -g format "$1" 2>/dev/null | awk '/format:/ {print $2}')" = "$2" ]; }

echo "Sample files"
swift - <<'EOF'
import AppKit
let size = NSSize(width: 640, height: 400)
let image = NSImage(size: size, flipped: false) { rect in
    NSGradient(starting: .systemOrange, ending: .systemPink)!.draw(in: rect, angle: 30)
    let text = "DragWheel test 123" as NSString
    text.draw(at: NSPoint(x: 40, y: 180), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 44), .foregroundColor: NSColor.black])
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "photo.png"))
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!.write(to: URL(fileURLWithPath: "photo.jpg"))
try! "{\\rtf1\\ansi {\\b Hello} from DragWheel.\\par Second line.}".write(toFile: "note.rtf", atomically: true, encoding: .utf8)
EOF

echo "Images"
for fmt in png:png webp:webp heic:heic gif:gif avif:avif jpeg:jpeg bmp:bmp tiff:tiff; do
    ext="${fmt%%:*}"; want="${fmt##*:}"
    action="to$(echo "$ext" | tr '[:lower:]' '[:upper:]')"
    out="$(run "$action" photo.png | sed -n 's/^✓ .* → //p')"
    check "$action → $want" is_format "$out" "$want"
done
check "toPDF"            test -s "$(run toPDF photo.png | sed -n 's/^✓ .* → //p')"
check "toDOCX has image" sh -c "unzip -l '$(run toDOCX photo.png | sed -n 's/^✓ .* → //p')' | grep -q media/image1.png"

echo "Tools"
check "compressImage"    sh -c "run() { '$BIN' --run \"\$@\"; }; run compressImage photo.jpg | grep -q '^✓\\|already as small'"
check "stripMetadata"    test -s "$(run stripMetadata photo.jpg | sed -n 's/^✓ .* → //p')"
check "addBackground"    test -s "$(run addBackground photo.png | sed -n 's/^✓ .* → //p')"
check "ocrText finds text" sh -c "grep -qi dragwheel '$(run ocrText photo.png | sed -n 's/^✓ .* → //p')'"

echo "PDF & documents"
note_pdf="$(run docToPDF note.rtf | sed -n 's/^✓ .* → //p')"
check "docToPDF"         test -s "$note_pdf"
merged="$(run mergePDF "$note_pdf" photo.jpg | sed -n 's/^✓ .* → //p')"
check "mergePDF"         test -s "$merged"
check "splitPDF"         test -d "$(run splitPDF "$merged" | sed -n 's/^✓ .* → //p')"
check "pdfToImages"      test -d "$(run pdfToImages "$merged" | sed -n 's/^✓ .* → //p')"
check "toWord"           test -s "$(run toWord "$note_pdf" | sed -n 's/^✓ .* → //p')"
check "wrong input is refused" sh -c "! '$BIN' --run splitPDF photo.png"

if command -v ffmpeg >/dev/null; then
    echo "Video & audio"
    ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=320x240:rate=24:duration=2 \
        -f lavfi -i sine=frequency=440:duration=2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest clip.mov
    for action in toMP4 videoToGIF toMP3 toWAV toMOV toWEBM toM4A mute; do
        check "$action" test -s "$(run "$action" clip.mov | sed -n 's/^✓ .* → //p')"
    done
else
    echo "Video & audio: skipped (ffmpeg not installed)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
