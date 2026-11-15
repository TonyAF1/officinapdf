//! OfficinaPDF: updates from PdfCraft's open-source code. OfficinaPDF has no releases to download:
//! a new version is made on this computer by `aggiorna-da-pdfcraft.ps1`, in the folder the program
//! was compiled from ([`source_dir`]). This module asks git whether PdfCraft's `main` has commits
//! that folder lacks, and starts the script in a console window of its own. A copy running
//! where that folder isn't (a portable copy on another computer) says so and offers nothing.
//!
//! The state is one static, so no other module carries a field for it. Texts are Italian only,
//! like the notes beside them.

use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, PoisonError};

/// The folder this program was compiled from: the workspace root.
const SOURCE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
/// The script that makes and installs a new version, in [`SOURCE`].
const SCRIPT: &str = "aggiorna-da-pdfcraft.ps1";
/// The remote of PdfCraft's repository in [`SOURCE`], and its branch.
const REMOTE: &str = "upstream";
const BRANCH: &str = "refs/heads/main";
/// How long the check at start stays quiet after it has offered an update: PdfCraft changes every
/// day, and a new version takes about an hour to make.
const QUIET_SECONDS: i64 = 7 * 24 * 60 * 60;
/// The file, in the settings folder, with the time (Unix seconds) the check at start last offered
/// an update.
const OFFERED_FILE: &str = "aggiornamento-proposto.txt";

/// Where the check is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Status {
    /// Nothing asked yet.
    Idle,
    /// git is asking PdfCraft's repository.
    Checking,
    /// The source folder has everything PdfCraft has.
    UpToDate,
    /// PdfCraft has commits the source folder lacks.
    Available,
    /// The script is running in its own window.
    Started,
    /// The source folder or its script isn't on this computer.
    NoSource,
    /// The check or the start failed; the text says why.
    Failed(String),
}

struct State {
    status: Status,
    /// The desktop app turned these updates on. Tests never do, so they never run git, and Help ▸
    /// Check for updates stays the dormant check they drive with a stand-in source.
    enabled: bool,
    /// The check at start hasn't run yet.
    at_start: bool,
    /// The check now running was the one at start: an update it finds opens the window.
    from_start: bool,
    /// The window was opened for the check at start's answer.
    offered: bool,
}

static STATE: Mutex<State> = Mutex::new(State { status: Status::Idle, enabled: false, at_start: false, from_start: false, offered: false });

/// The state; a panic elsewhere while it was held leaves it usable.
fn state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(PoisonError::into_inner)
}

pub(super) fn status() -> Status {
    state().status.clone()
}

/// The source folder, when it and the script are on this computer.
fn source_dir() -> Option<PathBuf> {
    let dir = PathBuf::from(SOURCE);
    dir.join(SCRIPT).is_file().then_some(dir)
}

/// The desktop app turns these updates, and their check at start, on.
pub(super) fn enable() {
    let mut s = state();
    s.enabled = true;
    s.at_start = true;
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
        if wanted && source_dir().is_some() && !offered_recently(settings, now()) {
            start_check(true);
        }
        return false;
    }
    if s.from_start && !s.offered && s.status == Status::Available {
        s.offered = true;
        drop(s);
        remember_offer(settings, now());
        return true;
    }
    false
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

/// Asks git on a thread of its own; the answer lands in [`STATE`].
fn start_check(from_start: bool) {
    let Some(dir) = source_dir() else {
        state().status = Status::NoSource;
        return;
    };
    {
        let mut s = state();
        if s.status == Status::Checking || s.status == Status::Started {
            return;
        }
        s.status = Status::Checking;
        s.from_start = from_start;
        s.offered = false;
    }
    let spawned = std::thread::Builder::new().name("officinapdf-update-check".into()).spawn(move || {
        let status = match check(&dir) {
            Ok(true) => Status::Available,
            Ok(false) => Status::UpToDate,
            Err(e) => Status::Failed(e),
        };
        state().status = status;
    });
    if let Err(e) = spawned {
        state().status = Status::Failed(e.to_string());
    }
}

/// Whether PdfCraft's `main` has a commit that `dir`'s `main` lacks.
fn check(dir: &Path) -> Result<bool, String> {
    let listed = git(dir, &["ls-remote", REMOTE, BRANCH])?;
    if !listed.status.success() {
        return Err(format!("non riesco a raggiungere PdfCraft ({})", String::from_utf8_lossy(&listed.stderr).trim()));
    }
    let Some(commit) = remote_commit(&String::from_utf8_lossy(&listed.stdout)) else {
        return Err("PdfCraft non ha risposto con il suo ultimo aggiornamento".into());
    };
    // Exit 0: OfficinaPDF's main already contains it. Anything else (not an ancestor, or a commit
    // this folder has never fetched): there is something new.
    Ok(!git(dir, &["merge-base", "--is-ancestor", &commit, "main"])?.status.success())
}

/// The commit in `git ls-remote`'s answer: the 40 hexadecimal digits that start its first line.
fn remote_commit(output: &str) -> Option<String> {
    let commit = output.lines().next()?.split_whitespace().next()?;
    (commit.len() == 40 && commit.bytes().all(|b| b.is_ascii_hexdigit())).then(|| commit.to_owned())
}

fn git(dir: &Path, args: &[&str]) -> Result<std::process::Output, String> {
    let mut command = std::process::Command::new("git");
    command.arg("-C").arg(dir).args(args).stdin(std::process::Stdio::null());
    #[cfg(windows)]
    {
        // CREATE_NO_WINDOW: git is a console program and the app is not.
        std::os::windows::process::CommandExt::creation_flags(&mut command, 0x0800_0000);
    }
    command.output().map_err(|e| format!("git non è disponibile ({e})"))
}

/// Starts the script in a console window of its own. It makes the new version, closes this
/// program, installs it and opens it again.
pub(super) fn start() {
    let Some(dir) = source_dir() else {
        state().status = Status::NoSource;
        return;
    };
    let status = match spawn_script(&dir) {
        Ok(()) => Status::Started,
        Err(e) => Status::Failed(e),
    };
    state().status = status;
}

#[cfg(windows)]
fn spawn_script(dir: &Path) -> Result<(), String> {
    let mut command = std::process::Command::new("pwsh");
    command.args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]).arg(dir.join(SCRIPT)).arg("-Automatico").current_dir(dir);
    // CREATE_NEW_CONSOLE: the script shows its progress, and outlives this program.
    std::os::windows::process::CommandExt::creation_flags(&mut command, 0x0000_0010);
    command.spawn().map(|_| ()).map_err(|e| format!("PowerShell 7 (pwsh) non è disponibile ({e})"))
}

#[cfg(not(windows))]
fn spawn_script(_dir: &Path) -> Result<(), String> {
    Err("l'aggiornamento automatico c'è solo per Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_remote_commit_is_the_first_field_of_the_first_line() {
        let commit = "27287c2970000000000000000000000000000abc";
        assert_eq!(remote_commit(&format!("{commit}\trefs/heads/main\n")).as_deref(), Some(commit));
        assert_eq!(remote_commit(""), None);
        assert_eq!(remote_commit("fatal: not a repository\n"), None);
        assert_eq!(remote_commit("27287c297\trefs/heads/main\n"), None, "a short id is not an answer");
    }

    #[test]
    fn an_offer_keeps_the_check_at_start_quiet_for_a_week() {
        let dir = std::env::temp_dir().join(format!("officinapdf-update-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        assert!(!offered_recently(Some(&dir), 1_000_000), "nothing was offered yet");
        remember_offer(Some(&dir), 1_000_000);
        assert!(offered_recently(Some(&dir), 1_000_000 + QUIET_SECONDS - 1));
        assert!(!offered_recently(Some(&dir), 1_000_000 + QUIET_SECONDS), "a week later it asks again");
        assert!(!offered_recently(Some(&dir), 999_999), "a clock set back doesn't silence it");
        assert!(!offered_recently(None, 1_000_000), "without a settings folder it always asks");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
