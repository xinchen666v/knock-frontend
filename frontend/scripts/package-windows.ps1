<#
.SYNOPSIS
  Build and package the Windows client.

.DESCRIPTION
  Creates dist\knock-windows-x64.zip containing the full Flutter release
  folder, the Visual C++ runtime DLLs, and README-FIRST.txt.
  The release folder must stay intact (data\, flutter_windows.dll, sqlite3.dll).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\package-windows.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\package-windows.ps1 -SkipBuild
#>
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  if (-not $SkipBuild) {
    Write-Host '==> flutter build windows --release'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build failed with exit code $LASTEXITCODE"
    }
  }

  $release = Join-Path $root 'build\windows\x64\runner\Release'
  if (-not (Test-Path (Join-Path $release 'knock.exe'))) {
    throw "Missing $release\knock.exe; build first."
  }

  $dist = Join-Path $root 'dist'
  $stage = Join-Path $dist 'knock-windows-x64'
  $zip = Join-Path $dist 'knock-windows-x64.zip'

  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Path $stage -Force | Out-Null

  Write-Host '==> Copying release folder'
  Copy-Item -Path (Join-Path $release '*') -Destination $stage -Recurse -Force

  Write-Host '==> Copying Visual C++ runtime'
  $crt = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
  foreach ($dll in $crt) {
    $src = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $src) {
      Copy-Item $src (Join-Path $stage $dll) -Force
    } else {
      Write-Warning "Missing $src; target machines need the VC++ 2015-2022 Redistributable."
    }
  }

  Write-Host '==> Adding README-FIRST.txt'
  $readme = Join-Path $PSScriptRoot 'README-FIRST.txt'
  if (-not (Test-Path $readme)) {
    throw "Missing README: $readme"
  }
  Copy-Item $readme (Join-Path $stage 'README-FIRST.txt') -Force

  Write-Host '==> Creating zip'
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

  $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
  $hashFile = "$zip.sha256"
  "$hash  $(Split-Path -Leaf $zip)" | Set-Content -Path $hashFile -Encoding ASCII

  $size = [Math]::Round((Get-Item $zip).Length / 1MB, 1)
  Write-Host ''
  Write-Host "Done: $zip ($size MB)"
  Write-Host "SHA256: $hash"
  Write-Host "Checksum file: $hashFile"
} finally {
  Pop-Location
}