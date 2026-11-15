<#
.SYNOPSIS
  Prepara le traduzioni dell'interfaccia per compilare OfficinaPDF.

.DESCRIPTION
  PdfCraft tiene le traduzioni in un archivio a parte (storytold/craft-i18n), alla versione scritta
  in craft-i18n.rev. Questo script:
    1. lo scarica (o lo aggiorna) in ..\craft-i18n, accanto al progetto;
    2. ne copia i cataloghi in target\officinapdf-i18n, con il nome OfficinaPDF al posto di PdfCraft;
    3. aggiunge all'italiano le righe di packaging\windows\officinapdf-it.tsv.
  Scrive il percorso della cartella pronta: va passato a cargo in CRAFT_I18N_DIR.

.EXAMPLE
  $env:CRAFT_I18N_DIR = & .\packaging\windows\officinapdf-traduzioni.ps1
#>
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'officinapdf-nome.ps1')

$rev = ([IO.File]::ReadAllText((Join-Path $Root 'craft-i18n.rev'))).Trim()
if ($rev -notmatch '^[0-9a-f]{40}$') { throw "craft-i18n.rev non contiene un commit: $rev" }
$clone = Join-Path (Split-Path $Root) 'craft-i18n'
if (-not (Test-Path (Join-Path $clone '.git'))) {
  & git.exe clone --quiet https://github.com/storytold/craft-i18n $clone | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'non riesco a scaricare storytold/craft-i18n' }
}
& git.exe -C $clone cat-file -e "$rev^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
  & git.exe -C $clone fetch --quiet origin | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'non riesco ad aggiornare storytold/craft-i18n' }
}
& git.exe -C $clone checkout --quiet --detach $rev | Out-Host
if ($LASTEXITCODE -ne 0) { throw "craft-i18n non ha il commit $rev" }

$out = Join-Path $Root 'target\officinapdf-i18n'
$locales = Join-Path $out 'locales'
if (Test-Path $locales) { Remove-Item -Recurse -Force $locales }
foreach ($dir in Get-ChildItem -Directory (Join-Path $clone 'locales')) {
  $app = Join-Path $dir.FullName 'pdfcraft.tsv'
  if (-not (Test-Path $app)) { continue }
  $to = New-Item -ItemType Directory -Force (Join-Path $locales $dir.Name)
  foreach ($name in 'common.tsv', 'pdfcraft.tsv') {
    $from = Join-Path $dir.FullName $name
    if (-not (Test-Path $from)) { continue }
    $text = Convert-OfficinaText ([IO.File]::ReadAllText($from))
    if ($dir.Name -eq 'it' -and $name -eq 'pdfcraft.tsv') {
      # A repeated row is an error to craft-i18n (the first one is kept), so PdfCraft's row goes
      # when OfficinaPDF has its own.
      $own = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'officinapdf-it.tsv'))
      $keys = New-Object 'System.Collections.Generic.HashSet[string]'
      foreach ($line in ($own -split "`r?`n")) {
        $c = $line.Split("`t")
        if ($c.Count -ge 3 -and -not $line.StartsWith('#')) { [void]$keys.Add($c[0] + "`t" + $c[1]) }
      }
      $kept = foreach ($line in ($text -split "`r?`n")) {
        $c = $line.Split("`t")
        if ($c.Count -ge 3 -and -not $line.StartsWith('#') -and $keys.Contains($c[0] + "`t" + $c[1])) { continue }
        $line
      }
      $text = (($kept -join "`n").TrimEnd("`n")) + "`n`n" + $own
    }
    [IO.File]::WriteAllText((Join-Path $to.FullName $name), $text, $OfficinaUtf8)
  }
}
if (-not (Test-Path (Join-Path $locales 'it\pdfcraft.tsv'))) { throw 'craft-i18n non ha il catalogo italiano di PdfCraft' }
Write-Output $out
