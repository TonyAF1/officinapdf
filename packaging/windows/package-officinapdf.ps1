<#
.SYNOPSIS
  Build and package OfficinaPDF for Windows (x64 MSI).

.DESCRIPTION
  The OfficinaPDF counterpart of package.ps1, kept separate so upstream changes to package.ps1
  merge without conflicts. Produces, in -OutDir (default: dist\officinapdf):
    OfficinaPDF-<version>-x64.msi        installer in Italian: Start menu, desktop shortcut, "Apri con",
                                         Windows default apps, "Modifica con OfficinaPDF" for PDF files
    OfficinaPDF-<version>-portable.zip   the same program to unzip anywhere, settings kept beside it

  The binaries link the C runtime statically (+crt-static), so no Visual C++ redistributable is
  needed. Nothing is signed: Windows SmartScreen may warn the first time the MSI runs.

  Needs: Rust (MSVC), the network the first time (cargo xtask models), and WiX v5:
    dotnet tool install --global wix --version 5.0.2
  or -Wix pointing at wix.exe.

.EXAMPLE
  pwsh packaging/windows/package-officinapdf.ps1
  pwsh packaging/windows/package-officinapdf.ps1 -SkipBuild -OutDir "..\Versioni\OfficinaPDF v0.3"
#>
param(
  [switch] $SkipBuild,
  [string] $OutDir,
  [string] $Wix = 'wix'
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-Native([string] $What, [scriptblock] $Block) {
  Write-Output "==> $What"
  & $Block
  if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

# The version lives in one place: [workspace.package] version in the root Cargo.toml.
$Version = $null
$inPkg = $false
foreach ($line in Get-Content (Join-Path $Root 'Cargo.toml')) {
  if ($line -match '^\s*\[') { $inPkg = ($line.Trim() -eq '[workspace.package]'); continue }
  if ($inPkg -and $line -match '^\s*version\s*=\s*"([^"]+)"') { $Version = $Matches[1]; break }
}
if (-not $Version) { throw 'could not read [workspace.package] version from Cargo.toml' }
$MsiVersion = ($Version -split '-')[0]

$Target = 'x86_64-pc-windows-msvc'
$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $Root 'target' }
if (-not $OutDir) { $OutDir = Join-Path $Root 'dist\officinapdf' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

Write-Output "OfficinaPDF $Version for Windows x64"

if (-not $SkipBuild) {
  $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = '-C target-feature=+crt-static'
  $env:PDFCRAFT_REQUIRE_WINRES = '1'
  # The interface translations (PdfCraft's catalogs under OfficinaPDF's name, plus OfficinaPDF's
  # own Italian rows): without them the build is English only.
  if (-not $env:CRAFT_I18N_DIR) { $env:CRAFT_I18N_DIR = & (Join-Path $PSScriptRoot 'officinapdf-traduzioni.ps1') }
  $env:CRAFT_I18N_REQUIRED = '1'
  Push-Location $Root
  try { Invoke-Native 'cargo build' { cargo build --release --locked -p pdfcraft -p pdfcraft-cli --target $Target } }
  finally { Pop-Location }
}
$Bin = Join-Path $TargetDir "$Target\release"
foreach ($exe in 'officinapdf.exe', 'officinapdf-cli.exe') {
  if (-not (Test-Path (Join-Path $Bin $exe))) { throw "$exe not found in $Bin (build without -SkipBuild first)" }
}

$Stage = Join-Path $TargetDir 'officinapdf-package'
Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Bin 'officinapdf.exe'), (Join-Path $Bin 'officinapdf-cli.exe') $Stage
foreach ($f in 'LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE') { Copy-Item (Join-Path $Root $f) $Stage }
Copy-Item (Join-Path $Root 'assets\app-icon\LICENSE-document.txt') $Stage

# OCR models: the app looks in models\ beside officinapdf.exe.
$Models = Join-Path $Stage 'models'
New-Item -ItemType Directory -Force -Path $Models | Out-Null
Push-Location $Root
try { Invoke-Native 'cargo xtask models' { cargo xtask models $Models } } finally { Pop-Location }
Remove-Item -Force (Join-Path $Models '*.part') -ErrorAction SilentlyContinue
if (-not (Test-Path (Join-Path $Models 'ATTRIBUTION.txt'))) { throw "no OCR models in $Models" }

# Empty: OfficinaPDF builds embed no craft-fonts faces (no CRAFT_FONTS_DIR).
$Docs = Join-Path $Stage 'font-licences'
New-Item -ItemType Directory -Force -Path $Docs | Out-Null

$Msi = Join-Path $OutDir "OfficinaPDF-$Version-x64.msi"
Invoke-Native 'wix build' {
  & $Wix build (Join-Path $PSScriptRoot 'officinapdf.wxs') -arch x64 `
    (Join-Path $PSScriptRoot 'officinapdf-installer-ui.wxs') `
    -d "Version=$MsiVersion" -d "BinDir=$Stage" -d "ModelsDir=$Models" -d "IconPath=$(Join-Path $Root 'assets\app-icon\pdfcraft.ico')" `
    -d "DocsDir=$Docs" -d 'HasCraftFontLicences=0' `
    -o $Msi
}
Remove-Item -Force -ErrorAction SilentlyContinue ([IO.Path]::ChangeExtension($Msi, '.wixpdb'))

# ---- portable zip ------------------------------------------------------------------------------
# portable.txt beside officinapdf.exe switches on portable mode: settings and recovery files go to
# OfficinaPDFData\ next to the exe (crates/ui-egui/src/platform/portable.rs).
$Portable = Join-Path $TargetDir "officinapdf-portable\OfficinaPDF-$Version-portable"
Remove-Item -Recurse -Force (Split-Path $Portable) -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Portable | Out-Null
Copy-Item (Join-Path $Stage '*.exe'), (Join-Path $Stage 'LICENSE-*'), (Join-Path $Stage 'NOTICE') $Portable
Copy-Item -Recurse $Models (Join-Path $Portable 'models')
Copy-Item (Join-Path $PSScriptRoot 'officinapdf-portable.txt') (Join-Path $Portable 'portable.txt')
$Zip = Join-Path $OutDir "OfficinaPDF-$Version-portable.zip"
Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path $Portable -DestinationPath $Zip

Get-Item $Msi, $Zip | Format-Table Name, Length
