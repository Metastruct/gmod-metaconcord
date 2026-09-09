//! Running gserv verbs.
//!
//! The whitelist lives here rather than in Lua on purpose: Lua is shared with
//! every other addon on the box, so a check up there would be a typo guard, not
//! a boundary. Nothing reaches a shell either, the argv is passed to execvp as
//! it stands, so a verb can never grow an argument it was not given.

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::mpsc::Sender;

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
    let mut command = Command::new("gserv");
    command
        .args(&tokens)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    // srcds dying mid-rehash would otherwise take gserv with it and leave the
    // checkout half updated, so the child gets its own session
    unsafe {
        use std::os::unix::process::CommandExt;
        command.pre_exec(|| {
            libc::setsid();
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

    #[test]
    fn a_missing_binary_reports_failed_rather_than_hanging() {
        let (tx, rx) = std::sync::mpsc::channel();
        // gserv is not on PATH in CI or on a dev box
        if Command::new("gserv").arg("--help").stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok() {
            return;
        }
        run(vec!["status".to_owned()], tx);
        let events: Vec<Output> = rx.into_iter().collect();
        assert_eq!(events.len(), 1, "expected exactly one terminal event");
        assert!(matches!(events[0], Output::Failed(_)));
    }
}
