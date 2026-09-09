//! Running gserv verbs.
//!
//! The whitelist lives here rather than in Lua on purpose: Lua is shared with
//! every other addon on the box, so a check up there would be a typo guard, not
//! a boundary. Nothing reaches a shell either, the argv is passed to execvp as
//! it stands, so a verb can never grow an argument it was not given.

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::mpsc::Sender;

/// gserv shells out to git, npm and friends, which need the environment a
/// login shell sets up. srcds is started with a narrower one, so the verb runs
/// through `bash -lc` the way it did over ssh. The script is a fixed literal
/// and the verb arrives in argv, so nothing in it can be interpreted.
const LOGIN_SHELL: &str = "bash";
const RUN_GSERV: &str = r#"exec gserv "$@""#;

/// argv for running `gserv <tokens>` under a login shell.
pub fn shell_argv(script: &str, tokens: &[String]) -> Vec<String> {
    let mut argv = vec!["-lc".to_owned(), script.to_owned(), "gserv".to_owned()];
    argv.extend(tokens.iter().cloned());
    argv
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

pub enum Output {
    Stdout(String),
    Stderr(String),
    Exit(i32),
    Failed(String),
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
    let mut command = Command::new(LOGIN_SHELL);
    command
        .args(shell_argv(RUN_GSERV, &tokens))
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

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(err) => {
            let _ = tx.send(Output::Failed(format!("could not run gserv: {err}")));
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

    // waitpid on our own child: a broad reaper elsewhere in the process would
    // steal the status, in which case the pipes closing is what ends the run
    match child.wait() {
        Ok(status) => {
            let _ = tx.send(Output::Exit(status.code().unwrap_or(-1)));
        }
        Err(err) => {
            let _ = tx.send(Output::Failed(format!("could not wait on gserv: {err}")));
        }
    }
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

    /// gserv runs under a login shell now, so a host without it reports the
    /// shell's 127 rather than a spawn failure. Either way the run terminates
    /// exactly once and is not reported as a success.
    #[test]
    fn a_missing_gserv_terminates_the_run_without_hanging() {
        // skip where gserv actually exists, this is about the failure path
        if Command::new(LOGIN_SHELL)
            .args(shell_argv(r#"command -v gserv"#, &[]))
            .stdout(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
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
            !matches!(terminal[0], Output::Exit(0)),
            "a missing gserv must not look like a clean run"
        );
    }
}

#[cfg(test)]
mod exec_tests {
    use super::*;

    /// The verb reaches gserv as argv, so nothing in it is ever interpreted by
    /// the shell even though one is in the way.
    #[test]
    fn the_verb_is_passed_as_arguments_not_interpolated() {
        let argv = shell_argv(r#"exec printf '[%s]' "$@""#, &["qu".into(), "rehash".into()]);
        let out = Command::new("bash").args(&argv).output().unwrap();
        assert_eq!(String::from_utf8_lossy(&out.stdout), "[qu][rehash]");
    }

    /// A token that would be dangerous in a command string stays one argument.
    /// The whitelist rejects these first; this is the layer under it.
    #[test]
    fn metacharacters_in_a_token_are_not_evaluated() {
        let argv = shell_argv(r#"exec printf '[%s]' "$@""#, &["a; touch /tmp/pwned".into()]);
        let out = Command::new("bash").args(&argv).output().unwrap();
        assert_eq!(String::from_utf8_lossy(&out.stdout), "[a; touch /tmp/pwned]");
        assert!(!std::path::Path::new("/tmp/pwned").exists());
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
