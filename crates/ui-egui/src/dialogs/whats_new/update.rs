//! OfficinaPDF: updates from its own releases on GitHub (`github.com/TonyAF1/officinapdf`).
//!
//! GitHub makes a new version by itself, every week: it takes PdfCraft's latest open-source code,
//! gives it OfficinaPDF's name, runs the tests and publishes the installer
//! (`.github/workflows/officinapdf-aggiorna.yml`). This module asks GitHub whether a release newer
//! than this program exists, downloads its installer (checked against the published SHA-256) and,
//! when the program closes, runs it and opens the new version. Nothing needs to be installed on
//! the computer, and nothing here depends on where the program was built.
//!
//! The releases aren't signed, so `craft_update`'s own installer (which only installs what the
//! same publisher signed) isn't used; its release reading and its checked download are.
//!
//! The state is one static, so no other module carries a field for it. Texts are Italian only,
//! like the notes beside them.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

use craft_update::http::Transfer;
use craft_update::release::{Asset, Release};
use craft_update::{Http, Stop};

/// The repository that publishes OfficinaPDF's releases.
const REPO: &str = "TonyAF1/officinapdf";
/// The Windows installer in a release: `OfficinaPDF-<version>-x64.msi`.
const INSTALLER_SUFFIX: &str = "-x64.msi";
/// How long the check at start stays quiet after it has offered an update.
const QUIET_SECONDS: i64 = 2 * 24 * 60 * 60;
/// The file, in the settings folder, with the time (Unix seconds) the check at start last offered
/// an update.
const OFFERED_FILE: &str = "aggiornamento-proposto.txt";
/// The folder, in the temporary folder, that holds the installer being downloaded.
const DOWNLOAD_DIR: &str = "OfficinaPDF-aggiornamento";

/// Where the update is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Status {
    /// Nothing asked yet.
    Idle,
    /// GitHub is being asked.
    Checking,
    /// This is the newest version.
    UpToDate,
    /// A newer version exists; the text is its number.
    Available(String),
    /// The installer is coming down.
    Downloading { done: u64, total: u64 },
    /// The installer is on this computer and waits for the program to close.
    Ready(String),
    /// The program is closing to install it.
    Installing,
    /// The check or the download failed; the text says why.
    Failed(String),
}

struct State {
    status: Status,
    /// The desktop app turned these updates on. Tests never do, so they never reach the network, and
    /// Help ▸ Check for updates stays the dormant check they drive with a stand-in source.
    enabled: bool,
    /// The check at start hasn't run yet.
    at_start: bool,
    /// The check now running was the one at start: an update it finds opens the window.
    from_start: bool,
    /// The window was opened for the check at start's answer.
    offered: bool,
    /// The newer release the check found.
    release: Option<Release>,
    /// The downloaded installer, once it is complete and checked.
    installer: Option<PathBuf>,
    /// The program was asked to close and install: the next exit runs the installer.
    install_on_exit: bool,
    /// The window asked the program to close.
    quit_requested: bool,
}

static STATE: Mutex<State> = Mutex::new(State {
    status: Status::Idle,
    enabled: false,
    at_start: false,
    from_start: false,
    offered: false,
    release: None,
    installer: None,
    install_on_exit: false,
    quit_requested: false,
});

/// The state; a panic elsewhere while it was held leaves it usable.
fn state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(PoisonError::into_inner)
}

pub(super) fn status() -> Status {
    state().status.clone()
}

/// The desktop app turns these updates, and their check at start, on.
pub(super) fn enable() {
    {
        let mut s = state();
        s.enabled = true;
        s.at_start = true;
    }
    clean_leftovers(&std::env::temp_dir().join(DOWNLOAD_DIR), env!("CARGO_PKG_VERSION"));
}

/// Removes the download folder once its installer is no newer than this program: it was
/// installed (or is older), so it is only taking space. A newer one stays, as does a folder with
/// no installer (a download still coming down in another copy of the program).
fn clean_leftovers(dir: &Path, current: &str) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut installers = 0;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        let Some(version) = name.strip_prefix("OfficinaPDF-").and_then(|n| n.strip_suffix(INSTALLER_SUFFIX)) else { continue };
        installers += 1;
        if version_key(version) > version_key(current) {
            return;
        }
    }
    if installers > 0 {
        let _ = std::fs::remove_dir_all(dir);
    }
}

/// A version's numbers, for ordering ("0.10.1" after "0.9.0"); what isn't a number counts as 0.
fn version_key(version: &str) -> Vec<u64> {
    version.split('.').map(|part| part.parse().unwrap_or(0)).collect()
}

pub(super) fn enabled() -> bool {
    state().enabled
}

/// Help ▸ Check for updates: ask now, whatever was known.
pub(super) fn check_now() {
    start_check(false);
}

/// Each frame: runs the check at start once, when `wanted` (the preference) and the last offer is
/// more than [`QUIET_SECONDS`] old. Returns true once, when that check found an update: the
/// caller opens the window.
pub(super) fn poll(wanted: bool, settings: Option<&Path>) -> bool {
    let mut s = state();
    if std::mem::take(&mut s.at_start) {
        drop(s);
        if wanted && !offered_recently(settings, now()) {
            start_check(true);
        }
        return false;
    }
    if s.from_start && !s.offered && matches!(s.status, Status::Available(_)) {
        s.offered = true;
        drop(s);
        remember_offer(settings, now());
        return true;
    }
    false
}

/// True once after the window asked the program to close for the installation.
pub(super) fn take_quit_request() -> bool {
    std::mem::take(&mut state().quit_requested)
}

fn now() -> i64 {
    chrono::Utc::now().timestamp()
}

/// The check at start offered an update less than [`QUIET_SECONDS`] before `now`.
fn offered_recently(settings: Option<&Path>, now: i64) -> bool {
    let Some(text) = settings.and_then(|d| std::fs::read_to_string(d.join(OFFERED_FILE)).ok()) else { return false };
    let Ok(then) = text.trim().parse::<i64>() else { return false };
    // A time in the future (the clock was set back) doesn't silence the check for ever.
    (0..QUIET_SECONDS).contains(&now.saturating_sub(then))
}

fn remember_offer(settings: Option<&Path>, now: i64) {
    if let Some(dir) = settings
        && let Err(e) = std::fs::write(dir.join(OFFERED_FILE), now.to_string())
    {
        log::warn!("update check: writing {OFFERED_FILE}: {e}");
    }
}

/// OfficinaPDF's releases, as `craft_update` reads them.
const fn app() -> craft_update::app::App {
    craft_update::app::App { id: "officinapdf", repo: REPO, ..crate::UPDATE_APP }
}

fn http() -> Result<Http, String> {
    Http::new(&format!("OfficinaPDF/{}", env!("CARGO_PKG_VERSION")))
}

/// Asks GitHub on a thread of its own; the answer lands in [`STATE`].
fn start_check(from_start: bool) {
    {
        let mut s = state();
        if matches!(s.status, Status::Checking | Status::Downloading { .. } | Status::Installing) {
            return;
        }
        s.status = Status::Checking;
        s.from_start = from_start;
        s.offered = false;
    }
    let spawned = std::thread::Builder::new().name("officinapdf-update-check".into()).spawn(|| {
        let result = check();
        let mut s = state();
        match result {
            Ok(Some(release)) => {
                s.status = Status::Available(release.version_label());
                s.release = Some(release);
            }
            Ok(None) => s.status = Status::UpToDate,
            Err(e) => s.status = Status::Failed(e),
        }
    });
    if let Err(e) = spawned {
        state().status = Status::Failed(e.to_string());
    }
}

/// The newest release this program doesn't have yet, with the checksum of its installer.
fn check() -> Result<Option<Release>, String> {
    let http = http()?;
    let Some(mut release) = craft_update::check_for_update(&app(), &http, env!("CARGO_PKG_VERSION"))? else { return Ok(None) };
    // The checksum comes with the release; when GitHub didn't send one, SHA256SUMS.txt has it.
    if let Some(sums) = release.sums_asset().map(|a| a.url.clone())
        && let Some(text) = http.get_text(&sums)?
    {
        release.apply_sums(&craft_update::release::parse_sha256sums(&text));
    }
    installer(&release)?;
    Ok(Some(release))
}

/// The Windows installer among a release's files.
fn installer(release: &Release) -> Result<&Asset, String> {
    release
        .assets
        .iter()
        .find(|a| a.name.starts_with("OfficinaPDF-") && a.name.ends_with(INSTALLER_SUFFIX))
        .ok_or_else(|| format!("la versione {} non ha ancora l'installer per Windows", release.version_label()))
}

/// "Aggiorna ora": downloads the installer on a thread of its own, with the progress in
/// [`Status::Downloading`].
pub(super) fn start() {
    let release = {
        let mut s = state();
        let Status::Available(_) = s.status else { return };
        let Some(release) = s.release.clone() else { return };
        s.status = Status::Downloading { done: 0, total: 0 };
        release
    };
    let spawned = std::thread::Builder::new().name("officinapdf-update-download".into()).spawn(move || {
        let result = download(&release);
        let mut s = state();
        match result {
            Ok(path) => {
                s.installer = Some(path);
                s.status = Status::Ready(release.version_label());
            }
            Err(e) => s.status = Status::Failed(e),
        }
    });
    if let Err(e) = spawned {
        state().status = Status::Failed(e.to_string());
    }
}

/// Downloads the release's installer to the temporary folder and checks it against its checksum.
fn download(release: &Release) -> Result<PathBuf, String> {
    let asset = installer(release)?;
    let sha256 = asset.sha256.as_deref().ok_or("la versione non pubblica il codice di controllo dell'installer, quindi non lo scarico")?;
    let dir = std::env::temp_dir().join(DOWNLOAD_DIR);
    // Whatever an earlier update left there goes: only this one is wanted.
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(|e| format!("non riesco a preparare la cartella per il download ({e})"))?;
    let path = dir.join(&asset.name);
    let mut progress = |t: Transfer| {
        let (Transfer::Bytes { done, total } | Transfer::Reconnecting { done, total }) = t;
        state().status = Status::Downloading { done, total };
    };
    http()?.download(&asset.url, &path, asset.size, sha256, &Stop::default(), &mut progress)?;
    Ok(path)
}

/// "Riavvia e installa": the window asks the program to close; the installation runs at exit.
pub(super) fn install_now() {
    let mut s = state();
    if matches!(s.status, Status::Ready(_)) {
        s.install_on_exit = true;
        s.quit_requested = true;
    }
}

/// The program is exiting. When it was asked to install, starts the installer, which waits for
/// this program to be gone, installs the new version and opens it.
pub(super) fn on_exit() {
    let installer = {
        let mut s = state();
        if !s.install_on_exit {
            return;
        }
        s.install_on_exit = false;
        s.status = Status::Installing;
        s.installer.clone()
    };
    if let Some(msi) = installer
        && let Err(e) = spawn_installer(&msi)
    {
        log::error!("update: starting the installer: {e}");
    }
}

/// The PowerShell script that waits for the program to exit, runs the installer with its own
/// progress bar and opens the new version. An update keeps the copy where it is: for everyone
/// when that is how it was installed.
#[cfg(any(windows, test))]
fn installer_script(pid: u32, msi: &Path) -> String {
    let dir = msi.parent().unwrap_or(msi).display().to_string().replace('\'', "''");
    let msi = msi.display().to_string().replace('\'', "''");
    format!(
        "$ErrorActionPreference = 'Continue'\n\
         Wait-Process -Id {pid} -Timeout 120 -ErrorAction SilentlyContinue\n\
         $all = [bool](Get-ItemProperty 'HKLM:\\Software\\OfficinaPDF' -Name InstallDir -ErrorAction SilentlyContinue)\n\
         $arguments = @('/i', '\"{msi}\"', '/passive', '/norestart')\n\
         if ($all) {{ $arguments += 'ALLUSERS=1' }}\n\
         $code = (Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru).ExitCode\n\
         if ($code -eq 0 -or $code -eq 3010) {{ Remove-Item -LiteralPath '{dir}' -Recurse -Force -ErrorAction SilentlyContinue }}\n\
         $key = if ($all) {{ 'HKLM:\\Software\\OfficinaPDF' }} else {{ 'HKCU:\\Software\\OfficinaPDF' }}\n\
         $dir = (Get-ItemProperty $key -Name InstallDir -ErrorAction SilentlyContinue).InstallDir\n\
         $exe = if ($dir) {{ Join-Path $dir 'officinapdf.exe' }}\n\
         if ($exe -and (Test-Path $exe)) {{ Start-Process $exe }}\n"
    )
}

#[cfg(windows)]
fn spawn_installer(msi: &Path) -> Result<(), String> {
    let script = msi.with_file_name("installa.ps1");
    std::fs::write(&script, installer_script(std::process::id(), msi)).map_err(|e| format!("non riesco a scrivere {} ({e})", script.display()))?;
    let mut command = std::process::Command::new("powershell.exe");
    command.args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"]).arg(&script);
    // CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP: hidden, and it outlives this program. Not
    // DETACHED_PROCESS: Windows PowerShell without a console quits before running the script
    // (0.9.0 and 0.10.0 never installed their update because of it).
    std::os::windows::process::CommandExt::creation_flags(&mut command, 0x0800_0000 | 0x0000_0200);
    command.spawn().map(|_| ()).map_err(|e| format!("PowerShell non è disponibile ({e})"))
}

#[cfg(not(windows))]
fn spawn_installer(_msi: &Path) -> Result<(), String> {
    Err("l'aggiornamento automatico c'è solo per Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_offer_keeps_the_check_at_start_quiet_for_a_while() {
        let dir = std::env::temp_dir().join(format!("officinapdf-update-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(!offered_recently(Some(&dir), 1_000_000), "nothing was offered yet");
        remember_offer(Some(&dir), 1_000_000);
        assert!(offered_recently(Some(&dir), 1_000_000 + QUIET_SECONDS - 1));
        assert!(!offered_recently(Some(&dir), 1_000_000 + QUIET_SECONDS), "later it asks again");
        assert!(!offered_recently(Some(&dir), 999_999), "a clock set back doesn't silence it");
        assert!(!offered_recently(None, 1_000_000), "without a settings folder it always asks");
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn release(assets: &[&str]) -> Release {
        Release {
            tag: "v0.9.0".into(),
            assets: assets.iter().map(|n| Asset { name: (*n).into(), size: 1, url: String::new(), sha256: None }).collect(),
            ..Release::default()
        }
    }

    #[test]
    fn the_installer_is_the_x64_msi_of_the_release() {
        let r = release(&["SHA256SUMS.txt", "OfficinaPDF-0.9.0-portable.zip", "OfficinaPDF-0.9.0-x64.msi"]);
        assert_eq!(installer(&r).map(|a| a.name.as_str()), Ok("OfficinaPDF-0.9.0-x64.msi"));
        let without = release(&["OfficinaPDF-0.9.0-portable.zip"]);
        assert!(installer(&without).unwrap_err().contains("installer"));
    }

    #[test]
    fn the_releases_come_from_officinapdf_s_own_repository() {
        let app = app();
        assert_eq!(app.repo, "TonyAF1/officinapdf");
        assert_eq!(app.releases_url(), "https://github.com/TonyAF1/officinapdf/releases");
    }

    #[test]
    fn the_installer_script_waits_installs_and_reopens() {
        let script = installer_script(4242, Path::new(r"C:\Temp\it's\OfficinaPDF-0.9.0-x64.msi"));
        assert!(script.contains("Wait-Process -Id 4242"));
        assert!(script.contains(r#"'"C:\Temp\it''s\OfficinaPDF-0.9.0-x64.msi"'"#), "a quote in the path is doubled: {script}");
        assert!(script.contains("/passive"));
        assert!(script.contains("Start-Process $exe"));
        let install = script.find("msiexec").unwrap_or(usize::MAX);
        let clean = script.find(r"Remove-Item -LiteralPath 'C:\Temp\it''s'").unwrap_or(0);
        assert!(clean > install, "the downloaded folder goes after the installation: {script}");
    }

    #[test]
    fn an_installed_download_is_cleaned_up_and_a_newer_one_kept() {
        let root = std::env::temp_dir().join(format!("officinapdf-pulizia-{}", std::process::id()));
        let old = root.join("installata");
        let new = root.join("nuova");
        let empty = root.join("in-corso");
        for (dir, file) in [(&old, "OfficinaPDF-0.9.0-x64.msi"), (&new, "OfficinaPDF-0.11.0-x64.msi")] {
            std::fs::create_dir_all(dir).unwrap();
            std::fs::write(dir.join(file), b"msi").unwrap();
        }
        std::fs::create_dir_all(&empty).unwrap();
        for dir in [&old, &new, &empty] {
            clean_leftovers(dir, "0.10.1");
        }
        assert!(!old.exists(), "an installer no newer than this program goes");
        assert!(new.exists(), "a newer installer stays");
        assert!(empty.exists(), "a folder without an installer stays");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_update_only_installs_after_the_window_asked_for_it() {
        // Not enabled by the desktop app, and nothing downloaded: asking does nothing, and exiting
        // starts nothing.
        install_now();
        assert!(!take_quit_request());
        on_exit();
        assert_ne!(status(), Status::Installing);
    }
}
