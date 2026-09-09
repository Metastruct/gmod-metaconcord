//! Running gserv verbs.
//!
//! The whitelist lives here rather than in Lua on purpose: Lua is shared with
//! every other addon on the box, so a check up there would be a typo guard, not
//! a boundary. Nothing reaches a shell either, the argv is passed to execvp as
//! it stands, so a verb can never grow an argument it was not given.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;

/// One gserv at a time, whoever asked for it.
///
/// Discord and an in-game command both reach this, and two `qu` runs pulling
/// the same repos at once would fight. The guard lives here rather than in any
/// one caller so it holds no matter how many entry points there are.
static RUNNING: AtomicBool = AtomicBool::new(false);

pub struct RunGuard;

impl RunGuard {
    /// None when a run is already in flight.
    pub fn acquire() -> Option<RunGuard> {
        RUNNING
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .ok()
            .map(|_| RunGuard)
    }
}

impl Drop for RunGuard {
    fn drop(&mut self) {
        RUNNING.store(false, Ordering::Release);
    }
}


/// Everything the bridge is allowed to ask for. `Gserv.ts` offers the same set,
/// minus anything that would restart the server out from under us.
const ALLOWED: &[&str] = &[
    "qu",
    "rehash",
    "merge_repos",
    "rehashskeleton",
    "update_repos",
    "status",
];

fn is_executable(path: &std::path::Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// An absolute path to gserv.
///
/// srcds's PATH is not something we control and is not visible from outside the
/// process, so leaving the lookup to execvp makes a failure both likely and
/// invisible: std cannot report a failed exec here, it panics trying to reap
/// the child that srcds already auto-reaped. gserv lives beside the repos it
/// manages, so look there first and treat PATH as the fallback.
pub fn resolve() -> Result<PathBuf, String> {
    resolve_in(std::env::var_os("HOME"), std::env::var_os("PATH"))
}

/// The lookup itself, so it can be tested without touching the environment.
fn resolve_in(
    home: Option<std::ffi::OsString>,
    path: Option<std::ffi::OsString>,
) -> Result<PathBuf, String> {
    let mut tried: Vec<String> = Vec::new();

    if let Some(home) = home {
        let candidate = PathBuf::from(home).join("gserv").join("gserv");
        if is_executable(&candidate) {
            return Ok(candidate);
        }
        tried.push(candidate.display().to_string());
    } else {
        tried.push("$HOME unset".to_owned());
    }

    match path {
        Some(path) => {
            for dir in std::env::split_paths(&path) {
                let candidate = dir.join("gserv");
                if is_executable(&candidate) {
                    return Ok(candidate);
                }
            }
            tried.push(format!("PATH={}", path.to_string_lossy()));
        }
        None => tried.push("$PATH unset".to_owned()),
    }

    Err(format!("gserv not found (tried {})", tried.join(", ")))
}

pub enum Output {
    Stdout(String),
    Stderr(String),
    /// None when the status was auto-reaped before we could read it; the run
    /// still finished, we just cannot say with what code.
    Exit(Option<i32>),
    Failed(String),
}

/// What to report once the pipes have closed.
///
/// srcds ignores SIGCHLD, so the kernel reaps our child for us and wait comes
/// back ECHILD. That is not a failure: the process ran and we read all of its
/// output, only the status is gone. Every other wait error is a real one.
fn wait_outcome(result: std::io::Result<std::process::ExitStatus>) -> Output {
    match result {
        Ok(status) => Output::Exit(Some(status.code().unwrap_or(-1))),
        Err(err) if err.raw_os_error() == Some(libc::ECHILD) => Output::Exit(None),
        Err(err) => Output::Failed(format!("could not wait on gserv: {err}")),
    }
}

/// Splits a verb like "qu rehash" and rejects it unless every token is allowed.
pub fn validate(verb: &str) -> Result<Vec<String>, String> {
    let tokens: Vec<String> = verb.split_whitespace().map(str::to_owned).collect();
    if tokens.is_empty() {
        return Err("empty gserv verb".to_owned());
    }
    if let Some(bad) = tokens.iter().find(|t| !ALLOWED.contains(&t.as_str())) {
        return Err(format!("gserv verb not allowed: {bad}"));
    }
    Ok(tokens)
}

/// Spawns gserv and streams its output down the channel, ending with exactly
/// one Exit or Failed. Runs on a worker thread and never touches Lua.
pub fn run(tokens: Vec<String>, tx: Sender<Output>) {
    // no shell: the verb is argv, so nothing in it is ever interpreted
    let program = match resolve() {
        Ok(program) => program,
        Err(message) => {
            let _ = tx.send(Output::Failed(message));
            return;
        }
    };

    let mut command = Command::new(program);
    command
        .args(&tokens)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    unsafe {
        use std::os::unix::process::CommandExt;
        command.pre_exec(|| {
            // srcds dying mid-rehash would otherwise take gserv with it and
            // leave the checkout half updated, so it gets its own session
            libc::setsid();

            // srcds leaves SIGCHLD ignored, and unlike a handler SIG_IGN
            // survives execve: every git gserv runs would inherit auto-reaping
            // and fail its own waitpid with ECHILD
            libc::signal(libc::SIGCHLD, libc::SIG_DFL);
            libc::signal(libc::SIGPIPE, libc::SIG_DFL);

            // a blocked set is inherited too, and gserv waits on children
            let mut mask: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut mask);
            libc::sigprocmask(libc::SIG_SETMASK, &mask, std::ptr::null_mut());

            Ok(())
        });
    }

    // srcds auto-reaps, so std cannot reap a child whose exec failed and
    // asserts instead of returning the error. Catching that keeps a bad spawn
    // from taking the worker thread down and leaving the run with no answer.
    let spawned = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| command.spawn()));
    let mut child = match spawned {
        Ok(Ok(child)) => child,
        Ok(Err(err)) => {
            let _ = tx.send(Output::Failed(format!("could not run gserv: {err}")));
            return;
        }
        Err(_) => {
            let _ = tx.send(Output::Failed(
                "could not run gserv: spawning it failed and srcds's auto-reap hid the reason"
                    .to_owned(),
            ));
            return;
        }
    };

    // both pipes have to be drained at once or a chatty verb fills one and
    // blocks forever waiting for the other to be read
    let stderr = child.stderr.take();
    let stderr_tx = tx.clone();
    let pump_stderr = std::thread::spawn(move || {
        if let Some(stderr) = stderr {
            for line in BufReader::new(stderr).split(b'\n').map_while(Result::ok) {
                let text = String::from_utf8_lossy(&line).into_owned();
                if stderr_tx.send(Output::Stderr(text)).is_err() {
                    return;
                }
            }
        }
    });

    if let Some(stdout) = child.stdout.take() {
        for line in BufReader::new(stdout).split(b'\n').map_while(Result::ok) {
            let text = String::from_utf8_lossy(&line).into_owned();
            if tx.send(Output::Stdout(text)).is_err() {
                break;
            }
        }
    }

    let _ = pump_stderr.join();

    // both pipes are drained by now, so the run is over either way
    let _ = tx.send(wait_outcome(child.wait()));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allowed_verbs_split_into_argv() {
        assert_eq!(validate("qu rehash").unwrap(), vec!["qu", "rehash"]);
        assert_eq!(validate("  status  ").unwrap(), vec!["status"]);
    }

    #[test]
    fn unknown_verbs_are_rejected() {
        assert!(validate("restart").is_err());
        assert!(validate("rehash restart").is_err(), "one bad token poisons the whole verb");
        assert!(validate("").is_err());
    }

    /// There is no shell, but a verb that tried to smuggle one must still fail
    /// the whitelist rather than reach execvp as an argument.
    #[test]
    fn shell_metacharacters_cannot_ride_along() {
        for verb in ["rehash; rm -rf /", "rehash && curl evil", "rehash|sh", "$(id)", "../../bin/sh"] {
            assert!(validate(verb).is_err(), "should have rejected {verb:?}");
        }
    }

    /// g3's srcds runs with PATH=/usr/bin:/bin, which does not contain gserv,
    /// so leaving the lookup to execvp fails there while working on g2. HOME is
    /// the same on both, so it is what the lookup leans on.
    #[test]
    fn gserv_is_found_through_home_even_when_path_lacks_it() {
        use std::ffi::OsString;
        let root = std::env::temp_dir().join(format!("mc-gserv-{}", std::process::id()));
        let bin = root.join("gserv");
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&bin.parent().unwrap().join("gserv")).unwrap();
        let exe = root.join("gserv").join("gserv");
        std::fs::write(&exe, "#!/bin/sh\ntrue\n").unwrap();
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).unwrap();
        }

        // g3: PATH cannot help, HOME must
        let found = resolve_in(Some(OsString::from(&root)), Some(OsString::from("/usr/bin:/bin")));
        assert_eq!(found.unwrap(), exe);

        // and with no PATH at all
        let found = resolve_in(Some(OsString::from(&root)), None);
        assert_eq!(found.unwrap(), exe);

        let _ = std::fs::remove_dir_all(&root);
    }

    /// Falls back to PATH when it is not beside HOME, and says what it tried
    /// rather than letting execvp fail somewhere std cannot report it.
    #[test]
    fn resolution_falls_back_to_path_then_reports_what_it_tried() {
        use std::ffi::OsString;
        let dir = std::env::temp_dir().join(format!("mc-path-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let exe = dir.join("gserv");
        std::fs::write(&exe, "#!/bin/sh\ntrue\n").unwrap();
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).unwrap();
        }

        let found = resolve_in(Some(OsString::from("/nonexistent")), Some(OsString::from(&dir)));
        assert_eq!(found.unwrap(), exe);

        let err = resolve_in(Some(OsString::from("/nonexistent")), Some(OsString::from("/usr/bin")))
            .unwrap_err();
        assert!(err.contains("/nonexistent/gserv/gserv"), "should name the home path: {err}");
        assert!(err.contains("PATH="), "should name the path it searched: {err}");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A non-executable file must not be mistaken for gserv.
    #[test]
    fn a_non_executable_candidate_is_skipped() {
        use std::ffi::OsString;
        let root = std::env::temp_dir().join(format!("mc-noexec-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("gserv")).unwrap();
        std::fs::write(root.join("gserv").join("gserv"), "not executable").unwrap();

        assert!(resolve_in(Some(OsString::from(&root)), None).is_err());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// Discord and an in-game command are separate callers, so the guard has to
    /// refuse the second one rather than let two runs touch the same repos.
    #[test]
    fn only_one_run_is_allowed_at_a_time() {
        let first = RunGuard::acquire().expect("nothing should be running");
        assert!(RunGuard::acquire().is_none(), "a second run should be refused");

        drop(first);
        let again = RunGuard::acquire().expect("the guard should free up");
        drop(again);
    }

    /// A host with no gserv must terminate the run exactly once and never look
    /// like a clean one.
    #[test]
    fn a_missing_gserv_terminates_the_run_without_hanging() {
        // skip where gserv actually exists, this is about the failure path
        if Command::new("gserv").arg("status").stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok() {
            return;
        }

        let (tx, rx) = std::sync::mpsc::channel();
        run(vec!["status".to_owned()], tx);
        let events: Vec<Output> = rx.into_iter().collect();

        let terminal: Vec<&Output> = events
            .iter()
            .filter(|e| matches!(e, Output::Exit(_) | Output::Failed(_)))
            .collect();
        assert_eq!(terminal.len(), 1, "expected exactly one terminal event");
        assert!(
            !matches!(terminal[0], Output::Exit(Some(0))),
            "a missing gserv must not look like a clean run"
        );
    }
}

#[cfg(test)]
mod exec_tests {
    use super::*;
    use std::io::{Error, ErrorKind};

    /// srcds auto-reaps our child, so wait fails with ECHILD after a run that
    /// went perfectly. That has to read as "finished, status unknown", not as
    /// a failure, or every gserv verb reports as broken.
    #[test]
    fn an_auto_reaped_child_counts_as_a_finished_run() {
        let echild = Error::from_raw_os_error(libc::ECHILD);
        assert!(matches!(wait_outcome(Err(echild)), Output::Exit(None)));
    }

    /// Any other wait error is still a real failure.
    #[test]
    fn other_wait_errors_are_still_failures() {
        let denied = Error::new(ErrorKind::PermissionDenied, "nope");
        assert!(matches!(wait_outcome(Err(denied)), Output::Failed(_)));
    }

    #[test]
    fn a_normal_exit_keeps_its_code() {
        let status = Command::new("bash").arg("-c").arg("exit 3").status().unwrap();
        assert!(matches!(wait_outcome(Ok(status)), Output::Exit(Some(3))));
    }

    /// The whole path against a real gserv, with SIGCHLD ignored the way srcds
    /// leaves it. Only meaningful on a game host:
    /// `cargo test --release -- --ignored real_gserv`
    #[test]
    #[ignore = "needs a real gserv"]
    fn real_gserv_status_survives_an_ignored_sigchld() {
        // exactly what /proc/<srcds>/status reports on a live server
        unsafe { libc::signal(libc::SIGCHLD, libc::SIG_IGN) };

        let (tx, rx) = std::sync::mpsc::channel();
        run(vec!["status".to_owned()], tx);
        let events: Vec<Output> = rx.into_iter().collect();

        let lines: Vec<&String> = events
            .iter()
            .filter_map(|e| match e {
                Output::Stdout(t) | Output::Stderr(t) => Some(t),
                _ => None,
            })
            .collect();
        let terminal: Vec<&Output> = events
            .iter()
            .filter(|e| matches!(e, Output::Exit(_) | Output::Failed(_)))
            .collect();

        for line in &lines {
            println!("  gserv: {line}");
        }
        println!("  terminal: {:?}", terminal.len());

        assert!(!lines.is_empty(), "gserv produced no output at all");
        assert_eq!(terminal.len(), 1, "expected exactly one terminal event");
        assert!(
            !matches!(terminal[0], Output::Failed(_)),
            "an auto-reaped run must not be reported as a failure"
        );
    }

    /// srcds ignores SIGCHLD, and unlike a handler SIG_IGN survives execve, so
    /// git ends up unable to reap what it spawns and fails with ECHILD. bash
    /// installs its own handler and hides this, so the disposition the child
    /// actually inherits is read out of /proc instead.
    #[test]
    fn pre_exec_clears_an_inherited_sigchld_ignore() {
        use std::os::unix::process::CommandExt;

        // cat touches no signal state, so what it reports is what it inherited
        let ignored_mask = |reset: bool| {
            let mut c = Command::new("cat");
            c.arg("/proc/self/status").stdout(Stdio::piped());
            unsafe {
                c.pre_exec(move || {
                    // stand in for what srcds leaves us
                    libc::signal(libc::SIGCHLD, libc::SIG_IGN);
                    if reset {
                        libc::signal(libc::SIGCHLD, libc::SIG_DFL);
                    }
                    Ok(())
                });
            }
            let out = c.output().unwrap();
            let text = String::from_utf8_lossy(&out.stdout).into_owned();
            let line = text.lines().find(|l| l.starts_with("SigIgn:")).unwrap().to_owned();
            u64::from_str_radix(line.split_whitespace().nth(1).unwrap(), 16).unwrap()
        };

        // SIGCHLD is 17, so it is bit 16 of the mask
        let sigchld = 1u64 << (libc::SIGCHLD - 1);

        assert_ne!(ignored_mask(false) & sigchld, 0, "the ignore should be inherited");
        assert_eq!(ignored_mask(true) & sigchld, 0, "pre_exec should have cleared it");
    }
}
