# OfficinaPDF: the rename from PdfCraft, as functions. Dot-source this file:
#   . .\packaging\windows\officinapdf-nome.ps1
# aggiorna-da-pdfcraft.ps1 applies it to PdfCraft's source before merging it, and
# officinapdf-traduzioni.ps1 to PdfCraft's translation catalogs.

# Lines where "PdfCraft" stays: credits, the licence and test texts that name it on purpose, and
# `sRGB (PdfCraft)`, the name inside the colour profile that the shared craft-cms library builds:
# a test compares it byte for byte with the copy kept here.
$OfficinaKeep = 'Based on PdfCraft|Basato su PdfCraft|based on PdfCraft|PdfCraft contributors|PdfCraft patch:|PdfCraft rewraps|github\.com/storytold/pdfcraft|sRGB \(PdfCraft\)'
$OfficinaUtf8 = New-Object System.Text.UTF8Encoding($false)

# The text with OfficinaPDF's name in place of PdfCraft's, line by line.
function Convert-OfficinaText([string] $Text) {
  if ($Text -cnotmatch 'PdfCraft|pdfcraft') { return $Text }
  $out = foreach ($line in ($Text -split "(?<=`n)")) {
    if ($line -match $OfficinaKeep) { $line; continue }
    $l = $line -creplace '\bPdfCraftData\b', 'OfficinaPDFData'
    $l = $l -creplace '\bPdfCraft\b', 'OfficinaPDF'
    $l = $l -creplace 'CARGO_BIN_EXE_pdfcraft-cli', 'CARGO_BIN_EXE_officinapdf-cli'
    $l = $l -creplace 'CARGO_BIN_EXE_pdfcraft\b', 'CARGO_BIN_EXE_officinapdf'
    $l = $l -creplace '(?<!apps/)(?<!-p )(?<![\w/-])pdfcraft-cli\b', 'officinapdf-cli'
    # The desktop program's own name, where it prints or documents it: `officinapdf 0.5.0`,
    # `Usage: officinapdf …`, `officinapdf: <error>`. Not log targets or file names.
    $l = $l -creplace '"pdfcraft (?=[{"])', '"officinapdf '
    $l = $l -creplace 'Usage: (`?)pdfcraft \[', 'Usage: $1officinapdf ['
    $l = $l -creplace '"pdfcraft: \{report\}', '"officinapdf: {report}'
    $l
  }
  return (-join $out)
}

# Cargo.toml's text with OfficinaPDF's version: the workspace version and the pdfcraft-* path
# dependencies, never another crate's version.
function Convert-OfficinaVersion([string] $Text, [string] $Version) {
  $out = foreach ($line in ($Text -split "(?<=`n)")) {
    if ($line -match '^version = "' -or $line -match '^pdfcraft-[\w-]+ = \{ path') {
      $line -replace '(?<=version = ")[^"]+(?=")', $Version
    } else { $line }
  }
  return (-join $out)
}

# The version in a checkout's Cargo.toml.
function Get-OfficinaVersion([string] $Root) {
  $text = [IO.File]::ReadAllText((Join-Path $Root 'Cargo.toml'))
  return [regex]::Match($text, '(?m)^\[workspace\.package\]\s*\r?\nversion = "([^"]+)"').Groups[1].Value
}

# Renames the program's source in the checkout at $Root and, with $Version, stamps that version.
# Returns how many files changed.
function Convert-OfficinaTree([string] $Root, [string] $Version) {
  $changed = 0
  Push-Location $Root
  try {
    $files = @(git ls-files 'apps/*.rs' 'crates/*.rs') | Where-Object { $_ -notmatch 'dialogs/whats_new' }
    foreach ($f in $files) {
      $path = Join-Path $Root $f
      $text = [IO.File]::ReadAllText($path)
      $new = Convert-OfficinaText $text
      if ($new -cne $text) { [IO.File]::WriteAllText($path, $new, $OfficinaUtf8); $changed++ }
    }
    # PdfCraft's own GitHub automation (its checks, releases and bot) can't run on OfficinaPDF's
    # repository: it calls PdfCraft's organisation and secrets, and would fail at every push.
    # OfficinaPDF's own workflows are the files named officinapdf-*.yml.
    foreach ($f in @(git ls-files '.github')) {
      if ($f -match '^\.github/workflows/officinapdf-[\w-]+\.yml$') { continue }
      Remove-Item -LiteralPath (Join-Path $Root $f) -Force -ErrorAction SilentlyContinue
      $changed++
    }
    if ($Version) {
      $path = Join-Path $Root 'Cargo.toml'
      $text = [IO.File]::ReadAllText($path)
      $new = Convert-OfficinaVersion $text $Version
      if ($new -cne $text) { [IO.File]::WriteAllText($path, $new, $OfficinaUtf8); $changed++ }
    }
  } finally { Pop-Location }
  return $changed
}
