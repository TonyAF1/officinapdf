<#
.SYNOPSIS
  Porta in OfficinaPDF gli aggiornamenti di PdfCraft e, se richiesto, crea la nuova versione.

.DESCRIPTION
  1. Controlla se PdfCraft (remote "upstream") ha novità. Se non ne ha, si ferma.
  2. Le unisce in un ramo di prova, "aggiornamento-pdfcraft": il ramo main resta com'era finché
     tutto non è andato bene.
  3. Riapplica il nome OfficinaPDF ai file del programma, lasciando "PdfCraft" nelle righe dove
     deve restare (crediti, licenza, testi di prova).
  4. Controlli: formattazione, clippy, test, traduzioni italiane mancanti.
  5. Se tutto è a posto, porta le modifiche su main.
  6. Con -Versione 0.5.0: aggiorna il numero di versione, aggiunge la voce in Aiuto > Novità,
     crea l'installer e lo zip portatile in ..\Versioni\OfficinaPDF v0.5, poi commit e tag.

  Si ferma senza toccare main quando:
    - ci sono conflitti (PdfCraft ha cambiato le stesse righe di OfficinaPDF): l'unione viene annullata;
    - un controllo fallisce o mancano traduzioni: il lavoro resta nel ramo "aggiornamento-pdfcraft".
  In questi casi passa a Claude il messaggio finale.

.EXAMPLE
  pwsh .\aggiorna-da-pdfcraft.ps1                     # solo aggiornamento, nessuna nuova versione
  pwsh .\aggiorna-da-pdfcraft.ps1 -Versione 0.5.0     # aggiornamento e nuova versione
  pwsh .\aggiorna-da-pdfcraft.ps1 -SoloControllo      # dice solo se ci sono novità
#>
param(
  [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Versione,
  [switch] $SoloControllo
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Branch = 'aggiornamento-pdfcraft'
Set-Location $Root
# WiX installed as a .NET tool, for package-officinapdf.ps1.
$env:PATH = "$env:PATH;$env:USERPROFILE\.dotnet\tools"

function Say([string] $Text, [string] $Color = 'Cyan') { Write-Host "`n==> $Text" -ForegroundColor $Color }
function Stop-Here([string] $Text) {
  Write-Host "`n*** FERMATO: $Text" -ForegroundColor Yellow
  Write-Host 'Il ramo main non è stato modificato. Passa questo messaggio a Claude.' -ForegroundColor Yellow
  exit 1
}
function GitOk { & git.exe @args; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') non riuscito" } }
function Run([string] $What, [scriptblock] $Block) {
  Say $What
  & $Block | Out-Host
  return ($LASTEXITCODE -eq 0)
}

# ---- 1. novità? --------------------------------------------------------------------------------
if (git status --porcelain) { Stop-Here 'ci sono modifiche non salvate (commit) nel progetto: salvale o annullale prima.' }
if ((git branch --show-current) -ne 'main') { Stop-Here 'il progetto non è sul ramo main.' }
Say 'Controllo le novità di PdfCraft'
GitOk fetch --quiet upstream main
$New = @(git log --oneline HEAD..upstream/main)
if ($New.Count -eq 0 -and -not $Versione) {
  Say 'Nessuna novità: OfficinaPDF ha già tutti gli aggiornamenti di PdfCraft.' Green
  exit 0
}
Write-Host "$($New.Count) modifiche nuove di PdfCraft:"
$New | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
if ($New.Count -gt 15) { Write-Host "  … e altre $($New.Count - 15)" }
if ($SoloControllo) { exit 0 }

# ---- 2. unione in un ramo di prova -------------------------------------------------------------
if (git branch --list $Branch) { Stop-Here "esiste già il ramo $Branch di un aggiornamento precedente non concluso." }
GitOk switch --quiet -c $Branch
if ($New.Count -gt 0) {
  Say 'Unisco le novità'
  git merge --no-edit upstream/main | Out-Host
  if ($LASTEXITCODE -ne 0) {
    $conflicts = @(git diff --name-only --diff-filter=U)
    git merge --abort
    GitOk switch --quiet main
    GitOk branch --quiet -D $Branch
    Stop-Here "conflitti nei file: $($conflicts -join ', '). L'unione è stata annullata."
  }
}

# ---- 3. nome OfficinaPDF -----------------------------------------------------------------------
Say 'Riapplico il nome OfficinaPDF'
# Righe dove "PdfCraft" deve restare: crediti, licenza e testi di prova che lo citano apposta.
$Keep = 'Based on PdfCraft|Basato su PdfCraft|based on PdfCraft|PdfCraft contributors|PdfCraft patch:|PdfCraft rewraps|github\.com/storytold/pdfcraft'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$files = @(git ls-files 'apps/*.rs' 'crates/*.rs' 'crates/ui-egui/src/i18n/*.tsv') |
  Where-Object { $_ -notmatch 'whats_new\.rs$' }
$changed = 0
foreach ($f in $files) {
  $path = Join-Path $Root $f
  $text = [IO.File]::ReadAllText($path)
  $lines = $text -split "(?<=`n)"
  $out = foreach ($line in $lines) {
    if ($line -match $Keep) { $line; continue }
    $l = $line -creplace '\bPdfCraftData\b', 'OfficinaPDFData'
    $l = $l -creplace '\bPdfCraft\b', 'OfficinaPDF'
    $l = $l -creplace 'CARGO_BIN_EXE_pdfcraft-cli', 'CARGO_BIN_EXE_officinapdf-cli'
    $l = $l -creplace 'CARGO_BIN_EXE_pdfcraft\b', 'CARGO_BIN_EXE_officinapdf'
    $l = $l -creplace '(?<!apps/)(?<!-p )(?<![\w/-])pdfcraft-cli\b', 'officinapdf-cli'
    $l
  }
  $new = -join $out
  if ($new -cne $text) { [IO.File]::WriteAllText($path, $new, $Utf8); $changed++; Write-Host "  $f" }
}
Write-Host "$changed file aggiornati."

# ---- 4. nuova versione (facoltativa) -----------------------------------------------------------
if ($Versione) {
  Say "Imposto la versione $Versione"
  $cargo = Join-Path $Root 'Cargo.toml'
  $text = [IO.File]::ReadAllText($cargo)
  $old = [regex]::Match($text, '(?m)^\[workspace\.package\]\s*\r?\nversion = "([^"]+)"').Groups[1].Value
  if (-not $old) { Stop-Here 'non trovo la versione in Cargo.toml.' }
  # Only the workspace version and the pdfcraft-* path dependencies, never another crate's version.
  $lines = $text -split "(?<=`n)" | ForEach-Object {
    if ($_ -match '^version = "' -or $_ -match '^pdfcraft-[\w-]+ = \{ path') { $_.Replace("`"$old`"", "`"$Versione`"") } else { $_ }
  }
  [IO.File]::WriteAllText($cargo, (-join $lines), $Utf8)

  $mesi = 'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
  $data = "$($mesi[(Get-Date).Month - 1]) $((Get-Date).Year)"
  $notes = Join-Path $Root 'crates\ui-egui\src\dialogs\whats_new.rs'
  $text = [IO.File]::ReadAllText($notes)
  $entry = @"
pub const RELEASES: &[Release] = &[
    Release {
        version: "$Versione",
        date: "$data",
        notes: &["Ultime correzioni e novità di PdfCraft ($($New.Count) modifiche)."],
    },
"@
  $text = $text.Replace("pub const RELEASES: &[Release] = &[`n", ($entry -replace "`r`n", "`n"))
  [IO.File]::WriteAllText($notes, $text, $Utf8)
}

# ---- 5. controlli ------------------------------------------------------------------------------
& cargo fmt --all | Out-Null
if (-not (Run 'Controllo clippy (qualche minuto)' { cargo clippy --workspace --all-targets -j 6 -- -D warnings })) {
  GitOk add -A; GitOk commit --quiet -m 'Aggiornamento da PdfCraft (clippy non superato)'
  GitOk switch --quiet main
  Stop-Here "clippy ha trovato errori. Il lavoro è nel ramo $Branch."
}
if (-not (Run 'Eseguo i test (può volerci più di mezz''ora)' { cargo test --workspace -j 4 })) {
  GitOk add -A; GitOk commit --quiet -m 'Aggiornamento da PdfCraft (test non superati)'
  GitOk switch --quiet main
  Stop-Here "alcuni test non sono passati. Il lavoro è nel ramo $Branch."
}
Say 'Controllo le traduzioni italiane'
$report = & cargo xtask i18n-report 2>$null
$it = $report | Where-Object { $_ -match '^\s*it\s+(\d+) missing' } | Select-Object -First 1
if ($it -and [int]([regex]::Match($it, '\d+').Value) -gt 0) {
  Write-Host $it
  GitOk add -A; GitOk commit --quiet -m 'Aggiornamento da PdfCraft (traduzioni italiane mancanti)'
  GitOk switch --quiet main
  Stop-Here "mancano traduzioni italiane: $($it.Trim()). Il lavoro è nel ramo $Branch."
}

# ---- 6. su main --------------------------------------------------------------------------------
GitOk add -A
$message = if ($Versione) { "OfficinaPDF $Versione" } else { 'Aggiornamento da PdfCraft' }
if (git status --porcelain) { GitOk commit --quiet -m "$($message): rename after merging PdfCraft" }
GitOk switch --quiet main
GitOk merge --quiet --ff-only $Branch
GitOk branch --quiet -d $Branch
Say 'Aggiornamento portato su main.' Green

# ---- 7. pacchetti ------------------------------------------------------------------------------
if ($Versione) {
  $short = ($Versione -split '\.')[0..1] -join '.'
  $out = Join-Path (Split-Path $Root) "Versioni\OfficinaPDF v$short"
  if (Test-Path $out) { Stop-Here "la cartella $out esiste già: non la sovrascrivo." }
  Say "Creo installer e versione portatile in $out (circa 10 minuti)"
  & (Join-Path $Root 'packaging\windows\package-officinapdf.ps1') -OutDir $out
  if ($LASTEXITCODE -ne 0) { Stop-Here 'la creazione dei pacchetti non è riuscita (main contiene già l''aggiornamento).' }
  $leggimi = [IO.File]::ReadAllText((Join-Path $Root 'packaging\windows\officinapdf-leggimi.txt')).Replace('{VERSIONE}', $Versione)
  [IO.File]::WriteAllText((Join-Path $out 'LEGGIMI.txt'), $leggimi, $Utf8)
  GitOk tag "v$Versione"
  Say "OfficinaPDF $Versione è pronta in $out" Green
}
