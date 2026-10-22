# Builds the Windows release: a self-contained app folder, a portable .zip and (if Inno Setup is installed) the installer.
# Usage (from the repo root):  pwsh windows/scripts/publish.ps1
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$windows = Join-Path $root 'windows'
$version = (Get-Content (Join-Path $root 'VERSION')).Trim()
$publish = Join-Path $windows 'publish'
$dist = Join-Path $root 'dist'

& (Join-Path $PSScriptRoot 'fetch-model.ps1')

Remove-Item -Recurse -Force $publish -ErrorAction SilentlyContinue
dotnet publish (Join-Path $windows 'src\DragWheel\DragWheel.csproj') -c Release -r win-x64 --self-contained true `
    -p:PublishReadyToRun=true -p:DebugType=None -o $publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "DragWheel-$version-Windows-portable.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip
Write-Host "✓ $zip"

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) {
    & $iscc "/DAppVersion=$version" "/DSourceDir=$publish" (Join-Path $windows 'installer\DragWheel.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
    Write-Host "✓ installer in $dist"
} else {
    Write-Warning 'Inno Setup 6 not found; skipped the installer.'
}
