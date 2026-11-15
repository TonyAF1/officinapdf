<#
.SYNOPSIS
  Aggiorna OfficinaPDF con le ultime novità del codice open source di PdfCraft e crea la nuova versione.

.DESCRIPTION
  È lo stesso script che OfficinaPDF avvia da Aiuto > Verifica aggiornamenti.
  1. Controlla se PdfCraft (github.com/storytold/pdfcraft, remote "upstream") ha novità. Se non ne
     ha, si ferma.
  2. Le unisce in un ramo di prova, "aggiornamento-pdfcraft": il ramo main resta com'era finché
     tutto non è andato bene. Prima di unire dà a PdfCraft il nome OfficinaPDF, così le due
     versioni si scontrano solo dove OfficinaPDF ha davvero cambiato qualcosa.
  3. Numero di versione (da solo: 0.5.0 diventa 0.6.0) e voce in Aiuto > Novità.
  4. Traduzioni italiane, poi i controlli: formattazione e test.
  5. Se tutto è a posto porta le modifiche su main, crea l'installer e lo zip portatile in
     ..\Versioni\OfficinaPDF v0.6 e mette il tag.
  6. Con -Installa: chiude OfficinaPDF, installa la nuova versione e la riapre.

  Si ferma senza toccare main quando:
    - PdfCraft ha cambiato le stesse righe di OfficinaPDF (conflitti): l'unione viene annullata;
    - un controllo fallisce: il lavoro resta nel ramo "aggiornamento-pdfcraft".
  In questi casi passa a Claude il messaggio finale (è anche nel file di registro in ..\Versioni).

.EXAMPLE
  pwsh .\aggiorna-da-pdfcraft.ps1 -SoloControllo      # dice solo se ci sono novità
  pwsh .\aggiorna-da-pdfcraft.ps1                     # aggiorna e crea la nuova versione
  pwsh .\aggiorna-da-pdfcraft.ps1 -Installa           # … e la installa
  pwsh .\aggiorna-da-pdfcraft.ps1 -Versione 1.0.0     # sceglie il numero di versione
#>
param(
  [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Versione,
  [switch] $SoloControllo,
  # Installa la nuova versione e riapre OfficinaPDF.
  [switch] $Installa,
  # Avviato da OfficinaPDF: come -Installa, e alla fine aspetta Invio prima di chiudere la finestra.
  [switch] $Automatico,
  # Per chi risolve i conflitti a mano: lascia l'unione a metà nel ramo di prova invece di annullarla.
  [switch] $LasciaConflitti,
  # Per provare lo script: salta i test e i pacchetti, si ferma dopo aver portato l'unione su main.
  [switch] $Prova
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
# Accented letters in a console window that isn't UTF-8 yet.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Branch = 'aggiornamento-pdfcraft'
Set-Location $Root
. (Join-Path $Root 'packaging\windows\officinapdf-nome.ps1')
# WiX installed as a .NET tool, for package-officinapdf.ps1.
$env:PATH = "$env:PATH;$env:USERPROFILE\.dotnet\tools"
if ($Automatico) { $Installa = $true }
$Versions = Join-Path (Split-Path $Root) 'Versioni'

function Say([string] $Text, [string] $Color = 'Cyan') { Write-Host "`n==> $Text" -ForegroundColor $Color }
function Finish([int] $Code) {
  try { Stop-Transcript | Out-Null } catch { }
  if ($Automatico) { Write-Host ''; Read-Host 'Premi Invio per chiudere questa finestra' | Out-Null }
  exit $Code
}
function Stop-Here([string] $Text) {
  Write-Host "`n*** FERMATO: $Text" -ForegroundColor Yellow
  Write-Host 'La copia installata di OfficinaPDF non è stata toccata: continua a funzionare come prima.' -ForegroundColor Yellow
  Write-Host 'Passa questo messaggio a Claude.' -ForegroundColor Yellow
  Finish 1
}
function GitOk { & git.exe @args; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') non riuscito" } }
function GitText { $r = & git.exe @args; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') non riuscito" }; return ($r -join "`n").Trim() }
function Run([string] $What, [scriptblock] $Block) {
  Say $What
  & $Block | Out-Host
  return ($LASTEXITCODE -eq 0)
}
# Leaves the trial branch with the work so far and goes back to main.
function Park([string] $Why) {
  GitOk add -A
  if (git status --porcelain) { GitOk commit --quiet -m "Aggiornamento da PdfCraft ($Why)" }
  GitOk switch --quiet main
  Stop-Here "$Why. Il lavoro è nel ramo $Branch."
}

# Anything unexpected: say so and keep the window open, instead of vanishing.
trap {
  Write-Host "`n*** ERRORE: $_" -ForegroundColor Red
  Write-Host "Ramo attuale del progetto: $(git branch --show-current). Passa questo messaggio a Claude." -ForegroundColor Yellow
  Finish 1
}

if (-not $SoloControllo) {
  New-Item -ItemType Directory -Force $Versions | Out-Null
  try { Start-Transcript -Path (Join-Path $Versions "aggiornamento-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log") | Out-Null } catch { }
}

# ---- 1. novità? --------------------------------------------------------------------------------
if (git status --porcelain) { Stop-Here 'ci sono modifiche non salvate (commit) nel progetto: salvale o annullale prima.' }
if ((git branch --show-current) -ne 'main') { Stop-Here 'il progetto non è sul ramo main.' }
Say 'Controllo le novità di PdfCraft'
GitOk fetch --quiet upstream main
$New = @(git log --oneline HEAD..upstream/main)
if ($New.Count -eq 0) {
  Say 'Nessuna novità: OfficinaPDF ha già tutti gli aggiornamenti di PdfCraft.' Green
  Finish 0
}
$quante = if ($New.Count -eq 1) { 'una modifica' } else { "$($New.Count) modifiche" }
Write-Host "Novità di PdfCraft: $quante."
$New | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
if ($New.Count -gt 15) { Write-Host "  … e altre $($New.Count - 15)" }
if ($SoloControllo) { exit 0 }
if (git branch --list $Branch) { Stop-Here "esiste già il ramo $Branch di un aggiornamento precedente non concluso." }

$Old = Get-OfficinaVersion $Root
if (-not $Old) { Stop-Here 'non trovo la versione in Cargo.toml.' }
if (-not $Versione) {
  $p = $Old -split '\.'
  $Versione = "$($p[0]).$([int]$p[1] + 1).0"
}
$short = ($Versione -split '\.')[0..1] -join '.'
$Out = Join-Path $Versions "OfficinaPDF v$short"
if (Test-Path $Out) { Stop-Here "la cartella $Out esiste già: non la sovrascrivo." }
if (git tag --list "v$Versione") { Stop-Here "la versione $Versione esiste già." }
$Upstream = [regex]::Match((GitText show upstream/main:Cargo.toml), '(?m)^\[workspace\.package\]\s*\r?\nversion = "([^"]+)"').Groups[1].Value
Say "Preparo OfficinaPDF $Versione da PdfCraft $Upstream"

# ---- 2. unione in un ramo di prova -------------------------------------------------------------
# PdfCraft's two versions (the one OfficinaPDF already has, and the new one) get OfficinaPDF's
# name and version first, in a scratch checkout. Merged from there, the rename is the same on
# every side and only OfficinaPDF's real changes can collide with PdfCraft's.
Say 'Do a PdfCraft il nome OfficinaPDF'
$Base = GitText merge-base HEAD upstream/main
$Scratch = Join-Path $Root 'target\officinapdf-unione'
if (Test-Path $Scratch) { git worktree remove --force $Scratch 2>$null | Out-Null }
git worktree prune
GitOk worktree add --quiet --detach $Scratch $Base
$Me = @('-c', 'user.name=OfficinaPDF', '-c', 'user.email=officinapdf@localhost')
function Renamed([string] $Commit, [string[]] $Parents) {
  # --force: the checkout still holds the previous commit under OfficinaPDF's name.
  GitOk -C $Scratch checkout --quiet --force --detach $Commit
  [void](Convert-OfficinaTree $Scratch $Old)
  GitOk -C $Scratch add -A
  $tree = GitText -C $Scratch write-tree
  $p = $Parents | ForEach-Object { '-p'; $_ }
  return (GitText @Me commit-tree $tree @p -m "OfficinaPDF's name on $Commit")
}
$BaseR = Renamed $Base @($Base)
$NewR = Renamed 'upstream/main' @($BaseR)
$Ours = GitText @Me commit-tree 'main^{tree}' -p $BaseR -m 'OfficinaPDF'
GitOk worktree remove --force $Scratch

Say 'Unisco le novità'
GitOk switch --quiet -c $Branch $Ours
git merge --no-commit --no-ff $NewR | Out-Host
# What each side always keeps: PdfCraft's lock file (cargo brings it up to date), OfficinaPDF's
# own README (PdfCraft's is kept beside it), and no catalogs in the repository.
foreach ($f in @(git diff --name-only --diff-filter=U)) {
  if ($f -eq 'Cargo.lock') { GitOk checkout --theirs -- $f; GitOk add -- $f }
  elseif ($f -eq 'README.md') { GitOk checkout --ours -- $f; GitOk add -- $f }
}
$readme = GitText show upstream/main:README.md
[IO.File]::WriteAllText((Join-Path $Root 'docs\README-pdfcraft.md'), $readme + "`n", $OfficinaUtf8)
GitOk add -- docs/README-pdfcraft.md
$conflicts = @(git diff --name-only --diff-filter=U)
if ($conflicts.Count -gt 0) {
  if ($LasciaConflitti) {
    Write-Host "`nConflitti da risolvere nel ramo $($Branch): $($conflicts -join ', ')" -ForegroundColor Yellow
    Write-Host "Poi: git add -A; git commit-tree (git write-tree) -p main -p upstream/main; git merge --quit" -ForegroundColor Yellow
    Finish 1
  }
  git merge --abort
  GitOk switch --quiet main
  GitOk branch --quiet -D $Branch
  Stop-Here "PdfCraft ha cambiato le stesse righe di OfficinaPDF in: $($conflicts -join ', '). L'unione è stata annullata."
}
# The merge as history records it: OfficinaPDF's main plus PdfCraft's main.
$tree = GitText write-tree
$merge = GitText commit-tree $tree -p main -p upstream/main -m "Merge PdfCraft $Upstream into OfficinaPDF"
GitOk merge --quit
GitOk update-ref "refs/heads/$Branch" $merge
[void](Convert-OfficinaTree $Root $null)
# OfficinaPDF shows no link to PdfCraft's Discord: one that PdfCraft added since stops the update.
$discord = @(git grep -n -I -i -E 'discord\.(gg|com)' -- apps crates)
if ($discord.Count -gt 0) {
  $discord | ForEach-Object { Write-Host "  $_" }
  Park 'PdfCraft ha aggiunto un link a Discord nel programma (righe qui sopra): va tolto a mano'
}

# ---- 3. nuova versione -------------------------------------------------------------------------
Say "Imposto la versione $Versione"
$cargo = Join-Path $Root 'Cargo.toml'
[IO.File]::WriteAllText($cargo, (Convert-OfficinaVersion ([IO.File]::ReadAllText($cargo)) $Versione), $OfficinaUtf8)
$mesi = 'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
$data = "$($mesi[(Get-Date).Month - 1]) $((Get-Date).Year)"
$notes = Join-Path $Root 'crates\ui-egui\src\dialogs\whats_new.rs'
$text = [IO.File]::ReadAllText($notes)
if ($text -notmatch [regex]::Escape("version: `"$Versione`"")) {
  $entry = @"
    Release {
        version: "$Versione",
        date: "$data",
        notes: &["Aggiornamento a PdfCraft $($Upstream): $quante tra correzioni e novità."],
    },

"@
  $head = [regex]::Match($text, 'pub const RELEASES: &\[Release\] = &\[\r?\n')
  if (-not $head.Success) { Park 'non trovo l''elenco delle versioni in whats_new.rs' }
  $text = $text.Insert($head.Index + $head.Length, ($entry -replace "`r`n", "`n"))
  [IO.File]::WriteAllText($notes, $text, $OfficinaUtf8)
}

# ---- 4. traduzioni e controlli -----------------------------------------------------------------
Say 'Preparo le traduzioni italiane'
# Now, so a missing catalog stops the update before the long part; the packages embed them.
$i18n = & (Join-Path $Root 'packaging\windows\officinapdf-traduzioni.ps1')
& cargo fmt --all | Out-Null
# The tests run as PdfCraft's own do: in English (some look for English labels, and this computer
# is Italian), so without the catalogs. Vulkan, unless WGPU_BACKEND says otherwise: the tests that
# draw crash on this computer's Direct3D 12 driver.
Remove-Item Env:CRAFT_I18N_DIR, Env:CRAFT_I18N_REQUIRED -ErrorAction SilentlyContinue
if (-not $env:WGPU_BACKEND) { $env:WGPU_BACKEND = 'vulkan' }
if (-not $Prova -and -not (Run 'Eseguo i test (può volerci più di mezz''ora)' { cargo test --workspace -j 4 })) { Park 'alcuni test non sono passati' }
$env:CRAFT_I18N_DIR = $i18n
$env:CRAFT_I18N_REQUIRED = '1'

# ---- 5. su main --------------------------------------------------------------------------------
GitOk add -A
if (git status --porcelain) { GitOk commit --quiet -m "OfficinaPDF $Versione" }
GitOk switch --quiet main
GitOk merge --quiet --ff-only $Branch
GitOk branch --quiet -d $Branch
Say 'Aggiornamento portato su main.' Green

# ---- 6. pacchetti ------------------------------------------------------------------------------
if ($Prova) { Say 'Prova finita: niente test, pacchetti e installazione.' Green; Finish 0 }
Say "Creo installer e versione portatile in $Out (circa 15 minuti)"
try { & (Join-Path $Root 'packaging\windows\package-officinapdf.ps1') -OutDir $Out | Out-Host }
catch { Stop-Here "la creazione dei pacchetti non è riuscita: $_ (il ramo main contiene già l'aggiornamento, manca solo il pacchetto)." }
$leggimi = [IO.File]::ReadAllText((Join-Path $Root 'packaging\windows\officinapdf-leggimi.txt')).Replace('{VERSIONE}', $Versione)
[IO.File]::WriteAllText((Join-Path $Out 'LEGGIMI.txt'), $leggimi, $OfficinaUtf8)
GitOk tag "v$Versione"
Say "OfficinaPDF $Versione è pronta in $Out" Green

# ---- 7. installazione --------------------------------------------------------------------------
if ($Installa) {
  $msi = Join-Path $Out "OfficinaPDF-$Versione-x64.msi"
  Say 'Installo la nuova versione'
  $open = @(Get-Process officinapdf -ErrorAction SilentlyContinue)
  if ($open.Count -gt 0) {
    Write-Host 'Chiudo OfficinaPDF (se chiede di salvare un documento, rispondi nella sua finestra)…'
    $open | ForEach-Object { [void]$_.CloseMainWindow() }
    while (Get-Process officinapdf -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 1 }
  }
  # An update keeps the copy where it is: for all users when that is how it was installed.
  $all = [bool](Get-ItemProperty 'HKLM:\Software\OfficinaPDF' -Name InstallDir -ErrorAction SilentlyContinue)
  $arguments = @('/i', "`"$msi`"", '/passive', '/norestart')
  if ($all) { $arguments += 'ALLUSERS=1' }
  $code = (Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru).ExitCode
  if ($code -ne 0) { Stop-Here "l'installazione non è riuscita (codice $code). Puoi installarla a mano: $msi" }
  $key = if ($all) { 'HKLM:\Software\OfficinaPDF' } else { 'HKCU:\Software\OfficinaPDF' }
  $dir = (Get-ItemProperty $key -Name InstallDir -ErrorAction SilentlyContinue).InstallDir
  $exe = if ($dir) { Join-Path $dir 'officinapdf.exe' }
  if ($exe -and (Test-Path $exe)) { Start-Process $exe }
  Say "OfficinaPDF $Versione è installata." Green
}
Finish 0
