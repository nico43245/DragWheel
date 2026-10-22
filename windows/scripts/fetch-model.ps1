# Downloads the U²-Net (u2netp) background-removal model and verifies its checksum.
# Model: https://github.com/xuebinqin/U-2-Net (Apache-2.0). ONNX export hosted by the rembg project.
$ErrorActionPreference = 'Stop'

$url = 'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx'
$sha256 = '309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8'
$dir = Join-Path $PSScriptRoot '..\models'
$file = Join-Path $dir 'u2netp.onnx'

New-Item -ItemType Directory -Force -Path $dir | Out-Null
if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash.ToLower() -ne $sha256) {
    Write-Host "Downloading u2netp.onnx…"
    Invoke-WebRequest -Uri $url -OutFile $file
}
$actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $sha256) {
    Remove-Item $file
    throw "Checksum mismatch for u2netp.onnx: $actual"
}
Write-Host "✓ models/u2netp.onnx ($sha256)"
