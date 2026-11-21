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
  # Per provare lo script: controlla che l'unione riesca, poi la butta via. Non tocca main, niente test né pacchetti.
  [switch] $Prova,
  # Su GitHub (officinapdf-aggiorna.yml): nessuna finestra, nessuna installazione; i pacchetti vanno
  # in .\dist e alla fine c'è SHA256SUMS.txt. Il workflow li pubblica.
  [switch] $Ci,
  # Salta i test (per una prova a mano su GitHub quando si sa già che i test sono a posto).
  [switch] $SaltaTest
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
# Per il workflow di GitHub: righe che passano ai passi successivi.
function Set-CiOutput([string] $Name, [string] $Value) {
  if ($Ci -and $env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value" }
}
$Clock = [Diagnostics.Stopwatch]::StartNew()

function Say([string] $Text, [string] $Color = 'Cyan') { Write-Host "`n==> $Text" -ForegroundColor $Color }
function Finish([int] $Code) {
  if (-not $SoloControllo -and $Clock.Elapsed.TotalMinutes -ge 1) { Write-Host "`nDurata: $([int]$Clock.Elapsed.TotalMinutes) minuti." }
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
# cargo writes its progress ("Compiling", "Running") to stderr. Turned into plain text, it
# shows in the normal colour and reaches the log, instead of looking like red errors.
function Plain { process { "$_" } }
# Runs cargo test again with these arguments, as the whole run did: --workspace, so cargo
# reuses what that run built instead of compiling for minutes with another set of features.
# True when it passed and ran at least one test (a filter that matches nothing passes empty).
# On screen only what matters; the many test programs that ran nothing stay out.
function Test-Again([string] $What, [string[]] $Extra) {
  Say $What
  & cargo test --workspace -j 4 --no-fail-fast @Extra 2>&1 | Plain | Tee-Object -Variable seen |
    Where-Object { $_ -cmatch '^test (?!result: ok\. 0 passed; 0 failed)|panicked|^---- |^\s*(left|right):|^error|Compiling|Finished' } | Out-Host
  $code = $LASTEXITCODE
  $ran = @($seen | Where-Object { $_ -match '^test result: ok\. [1-9]\d* passed' }).Count
  return ($code -eq 0 -and $ran -gt 0)
}
# PdfCraft's font archive in ..\craft-fonts, at the commit its CI names. $null (and a warning) when
# that commit can't be found or fetched: the tests then run without it.
function Get-CraftFonts {
  # OfficinaPDF keeps none of PdfCraft's workflows: the commit is read from PdfCraft's own.
  $ci = (& git.exe show upstream/main:.github/workflows/ci.yml 2>$null) -join "`n"
  $rev = [regex]::Match($ci, 'craft-fonts-ref:\s*([0-9a-f]{40})').Groups[1].Value
  if (-not $rev) { Write-Host 'Non trovo la versione di craft-fonts usata da PdfCraft: test senza i suoi font.' -ForegroundColor Yellow; return $null }
  $clone = Join-Path (Split-Path $Root) 'craft-fonts'
  if (-not (Test-Path (Join-Path $clone '.git'))) {
    Say 'Scarico i font per i test (storytold/craft-fonts, circa 50 MB, solo la prima volta)'
    & git.exe clone --quiet https://github.com/storytold/craft-fonts $clone | Out-Host
  }
  & git.exe -C $clone cat-file -e "$rev^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) { & git.exe -C $clone fetch --quiet origin | Out-Host }
  & git.exe -C $clone checkout --quiet --detach $rev 2>$null | Out-Host
  if ($LASTEXITCODE -ne 0) { Write-Host 'Non riesco a scaricare craft-fonts: test senza i suoi font.' -ForegroundColor Yellow; return $null }
  return $clone
}
# The groups of tests that failed in cargo's output, each with the tests it named:
# @{ Group = '-p crate --test it'; Tests = @('module::test', …) }.
function Get-FailedTests($Output) {
  $names = New-Object System.Collections.Generic.List[string]
  $inList = $false
  foreach ($item in $Output) {
    $line = "$item"
    if ($line -match '^failures:\s*$') { $inList = $true; continue }
    if ($line -match '^test result:') { $inList = $false; continue }
    if ($inList -and $line -match '^    ([A-Za-z_][\w:]*)\s*$') { if (-not $names.Contains($Matches[1])) { $names.Add($Matches[1]) }; continue }
    $group = [regex]::Match($line, 'to rerun pass `([^`]+)`').Groups[1].Value
    if ($group) {
      [pscustomobject]@{ Group = $group; Tests = @($names) }
      $names = New-Object System.Collections.Generic.List[string]
      $inList = $false
    }
  }
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

if (-not $SoloControllo -and -not $Ci) {
  New-Item -ItemType Directory -Force $Versions | Out-Null
  try { Start-Transcript -Path (Join-Path $Versions "aggiornamento-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log") | Out-Null } catch { }
  # One update at a time: a second one started meanwhile (from Aiuto > Verifica aggiornamenti,
  # say) would work on the same branch and folders. The file stays locked while this process
  # runs and is let go however it ends, even if the window is closed.
  $lockPath = Join-Path $Root 'target\aggiornamento-in-corso.lock'
  New-Item -ItemType Directory -Force (Split-Path $lockPath) | Out-Null
  try { $Lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
  catch {
    Write-Host "`nUn altro aggiornamento di OfficinaPDF è già in corso in un'altra finestra: aspetta che finisca." -ForegroundColor Yellow
    Finish 0
  }
}

# ---- 1. novità? --------------------------------------------------------------------------------
if (git status --porcelain) { Stop-Here 'ci sono modifiche non salvate (commit) nel progetto: salvale o annullale prima.' }
if ((git branch --show-current) -ne 'main') { Stop-Here 'il progetto non è sul ramo main.' }
Say 'Controllo le novità di PdfCraft'
GitOk fetch --quiet upstream main
$New = @(git log --oneline HEAD..upstream/main)
if ($New.Count -eq 0) {
  Say 'Nessuna novità: OfficinaPDF ha già tutti gli aggiornamenti di PdfCraft.' Green
  Set-CiOutput 'novita' 'false'
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
$Out = if ($Ci) { Join-Path $Root 'dist' } else { Join-Path $Versions "OfficinaPDF v$short" }
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
$env:CRAFT_I18N_DIR = & (Join-Path $Root 'packaging\windows\officinapdf-traduzioni.ps1')
$env:CRAFT_I18N_REQUIRED = '1'
& cargo fmt --all | Out-Null
if (-not $Prova -and -not $SaltaTest) {
  # The tests run as on PdfCraft's own machines: with the catalogs, in English (they look for
  # English labels, and this computer is Italian), and on a graphics driver that works. On this
  # computer the integrated Intel driver crashes the tests that draw, so they use the other
  # card through Vulkan. A WGPU_* variable set before the script is left as it is.
  $forTests = @{ LC_ALL = 'en_US.UTF-8' }
  # With the catalogs come the languages, and one test draws them all: it needs the fonts
  # PdfCraft keeps in storytold/craft-fonts, at the commit its own tests use. For the tests
  # only: the packages embed none of them, as before.
  $fonts = Get-CraftFonts
  if ($fonts -and -not $env:CRAFT_FONTS_DIR) { $forTests.CRAFT_FONTS_DIR = $fonts }
  if (-not $env:WGPU_BACKEND) { $forTests.WGPU_BACKEND = 'vulkan' }
  if (-not $env:WGPU_POWER_PREF) { $forTests.WGPU_POWER_PREF = 'high' }
  $before = @{}
  foreach ($name in $forTests.Keys) { $before[$name] = [Environment]::GetEnvironmentVariable($name); Set-Item "Env:$name" $forTests[$name] }
  Say 'Eseguo i test (può volerci più di mezz''ora)'
  Write-Host 'Durante i test possono comparire da sole finestre di Windows "Apri" o "Salva": sono dei test, si possono ignorare o chiudere.'
  & cargo test --workspace -j 4 --no-fail-fast 2>&1 | Plain | Tee-Object -Variable testOutput | Out-Host
  $ok = ($LASTEXITCODE -eq 0)
  $firstPassed = 0
  foreach ($line in $testOutput) {
    $m = [regex]::Match($line, '^test result: \w+\. (\d+) passed')
    if ($m.Success) { $firstPassed += [int]$m.Groups[1].Value }
  }
  $retried = New-Object System.Collections.Generic.List[string]
  if (-not $ok) {
    # A few of PdfCraft's tests wait a fixed time for a background job, or share state with
    # their neighbours, and fail only while every other test is running. Each test that failed
    # gets three more tries on its own; a group that failed without naming a test (it crashed)
    # gets one more try whole.
    $failed = @(Get-FailedTests $testOutput)
    if ($failed.Count -gt 0) {
      $ok = $true
      Write-Host "`nAl primo giro qualche test non è passato. Capita con alcuni test di PdfCraft: insieme a tutti gli altri a volte non finiscono in tempo, da soli passano. Li riprovo uno per uno: è un problema solo se alla fine compare *** FERMATO." -ForegroundColor Yellow
      foreach ($group in $failed) {
        if ($group.Tests.Count -eq 0) {
          # The group's targets without its package: --workspace keeps the build of the whole run.
          $tokens = @($group.Group -split ' ')
          $targets = for ($i = 0; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -eq '-p') { $i++; continue }; $tokens[$i] }
          if (Test-Again "Riprovo il gruppo di test: $($group.Group)" @($targets)) { $retried.Add($group.Group) } else { $ok = $false }
          continue
        }
        foreach ($test in $group.Tests) {
          $passed = $false
          foreach ($try in 1..3) {
            if (Test-Again "Riprovo da solo il test $test (tentativo $try di 3)" @('--', '--exact', $test, '--test-threads=1')) { $passed = $true; break }
          }
          if ($passed) { $retried.Add($test) } else { Write-Host "Il test $test non passa nemmeno da solo." -ForegroundColor Yellow; $ok = $false }
        }
      }
    }
  }
  $TestSummary = if (-not $ok) { $null }
    elseif ($retried.Count -eq 0) { "Test: tutti passati ($firstPassed)." }
    else { "Test: $firstPassed passati al primo giro, $($retried.Count) passati riprovando da soli ($($retried -join ', ')). Tutto a posto." }
  if ($TestSummary) { Say $TestSummary Green }
  # Put back, so the OfficinaPDF started at the end isn't told to speak English.
  foreach ($name in $forTests.Keys) { if ($null -eq $before[$name]) { Remove-Item "Env:$name" } else { Set-Item "Env:$name" $before[$name] } }
  if (-not $ok) { Park 'alcuni test non sono passati' }
}

# ---- 5. su main --------------------------------------------------------------------------------
if ($Prova) {
  # A trial run never reaches main: an untested merge there would be the next version's base.
  GitOk reset --quiet --hard
  GitOk switch --quiet main
  GitOk branch --quiet -D $Branch
  Say 'Prova finita: l''unione riesce. main non è stato toccato.' Green
  Finish 0
}
GitOk add -A
if (git status --porcelain) { GitOk commit --quiet -m "OfficinaPDF $Versione" }
GitOk switch --quiet main
GitOk merge --quiet --ff-only $Branch
GitOk branch --quiet -d $Branch
Say 'Aggiornamento portato su main.' Green

# ---- 6. pacchetti ------------------------------------------------------------------------------
Say "Creo installer e versione portatile in $Out (circa 15 minuti)"
try { & (Join-Path $Root 'packaging\windows\package-officinapdf.ps1') -OutDir $Out | Out-Host }
catch { Stop-Here "la creazione dei pacchetti non è riuscita: $_ (il ramo main contiene già l'aggiornamento, manca solo il pacchetto)." }
$leggimi = [IO.File]::ReadAllText((Join-Path $Root 'packaging\windows\officinapdf-leggimi.txt')).Replace('{VERSIONE}', $Versione)
[IO.File]::WriteAllText((Join-Path $Out 'LEGGIMI.txt'), $leggimi, $OfficinaUtf8)
GitOk tag "v$Versione"
Say "OfficinaPDF $Versione è pronta in $Out" Green
if ($Ci) {
  # The checksums the app checks the installer against (craft_update reads SHA256SUMS.txt).
  $sums = Get-ChildItem $Out -File | Where-Object { $_.Name -match '\.(msi|zip)$' } |
    ForEach-Object { "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)" }
  [IO.File]::WriteAllText((Join-Path $Out 'SHA256SUMS.txt'), (($sums -join "`n") + "`n"), $OfficinaUtf8)
  Set-CiOutput 'novita' 'true'
  Set-CiOutput 'versione' $Versione
  $notes = "Aggiornamento a PdfCraft $($Upstream): $quante.`n`n$TestSummary"
  [IO.File]::WriteAllText((Join-Path $Out 'note.md'), $notes, $OfficinaUtf8)
}

# ---- 7. installazione --------------------------------------------------------------------------
if ($Installa) {
  $msi = Join-Path $Out "OfficinaPDF-$Versione-x64.msi"
  Say 'Installo la nuova versione'
  $open = @(Get-Process officinapdf -ErrorAction SilentlyContinue)
  if ($open.Count -gt 0) {
    Write-Host 'Chiudo OfficinaPDF (se chiede di salvare un documento, rispondi nella sua finestra)…'
    $open | ForEach-Object { [void]$_.CloseMainWindow() }
    # Answering Annulla to its "save?" question keeps it open: say so now and then, and give up
    # after ten minutes instead of waiting for ever. The new version is ready either way.
    $waited = 0
    while (Get-Process officinapdf -ErrorAction SilentlyContinue) {
      Start-Sleep -Seconds 1
      $waited++
      if ($waited -ge 600) { Stop-Here "OfficinaPDF non si è chiuso in 10 minuti, quindi la nuova versione non è stata installata. Chiudi OfficinaPDF e installala a mano: $msi" }
      if ($waited % 30 -eq 0) { Write-Host 'Aspetto che OfficinaPDF si chiuda: se ti chiede di salvare un documento, rispondi nella sua finestra (o chiudilo tu).' -ForegroundColor Yellow }
    }
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
Write-Host "`nRiepilogo: OfficinaPDF $Versione, con $quante di PdfCraft $Upstream." -ForegroundColor Green
if ($TestSummary) { Write-Host $TestSummary -ForegroundColor Green }
Finish 0
