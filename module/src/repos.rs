//! The addon list, read straight off disk.
//!
//! Reproduces what the bridge used to run over ssh as a shell script, without
//! spawning git: branch and remote come out of .git/HEAD and .git/config. All
//! the resolution (github/gitlab/workshop lookups) stays on the bridge, this
//! only reports what is on the box.

use std::path::{Path, PathBuf};

pub struct Repo {
    /// directory name under the repos root
    pub repo: String,
    /// addon root inside the repo, "." when the repo itself is the addon
    pub sub: String,
    pub remote: String,
    pub wsid: String,
    pub branch: String,
}

/// What marks a directory as an addon root.
fn is_addon_root(dir: &Path) -> bool {
    dir.join("lua").is_dir() || dir.join("gamemodes").is_dir() || dir.join("addon.json").is_file()
}

fn first_line(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    let line = text.lines().next()?.trim();
    (!line.is_empty()).then(|| line.to_owned())
}

/// `.git` is a directory in a normal clone and a file holding `gitdir: <path>`
/// in a worktree or submodule.
fn git_dir(repo: &Path) -> Option<PathBuf> {
    let dot_git = repo.join(".git");
    if dot_git.is_dir() {
        return Some(dot_git);
    }
    let pointer = std::fs::read_to_string(&dot_git).ok()?;
    let target = pointer.lines().next()?.strip_prefix("gitdir:")?.trim();
    let path = Path::new(target);
    Some(if path.is_absolute() {
        path.to_path_buf()
    } else {
        repo.join(path)
    })
}

/// url of the origin remote out of .git/config.
pub fn parse_remote(config: &str) -> Option<String> {
    let mut in_origin = false;
    for line in config.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            // git normalises this heading, but tolerate stray whitespace
            in_origin = line.replace(char::is_whitespace, "") == "[remote\"origin\"]";
            continue;
        }
        if !in_origin {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            if key.trim() == "url" {
                return Some(value.trim().to_owned());
            }
        }
    }
    None
}

/// Branch name from .git/HEAD, or the short sha when it is detached.
pub fn parse_head(head: &str) -> Option<String> {
    let head = head.trim();
    if let Some(reference) = head.strip_prefix("ref:") {
        return reference
            .trim()
            .rsplit('/')
            .next()
            .filter(|name| !name.is_empty())
            .map(str::to_owned);
    }
    if head.is_empty() {
        return None;
    }
    Some(head.chars().take(7).collect())
}

/// Walks the repos root and returns one row per addon root.
pub fn enumerate(root: &Path) -> std::io::Result<Vec<Repo>> {
    let mut out = Vec::new();

    let mut entries: Vec<PathBuf> = std::fs::read_dir(root)?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect();
    // read_dir order is arbitrary, the bridge diffs these against a stored list
    entries.sort();

    for repo_path in entries {
        let Some(repo) = repo_path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };

        let git = git_dir(&repo_path);
        let remote = git
            .as_ref()
            .and_then(|g| std::fs::read_to_string(g.join("config")).ok())
            .as_deref()
            .and_then(parse_remote)
            .unwrap_or_default();
        let branch = git
            .as_ref()
            .and_then(|g| std::fs::read_to_string(g.join("HEAD")).ok())
            .as_deref()
            .and_then(parse_head)
            .unwrap_or_default();
        let repo_wsid = first_line(&repo_path.join(".workshopid")).unwrap_or_default();

        // a repo is one addon when its own root looks like one, otherwise every
        // first level directory that does is its own addon
        let mut subs: Vec<String> = Vec::new();
        if is_addon_root(&repo_path) {
            subs.push(".".to_owned());
        } else if let Ok(children) = std::fs::read_dir(&repo_path) {
            let mut found: Vec<String> = children
                .filter_map(|entry| entry.ok())
                .map(|entry| entry.path())
                .filter(|path| path.is_dir() && is_addon_root(path))
                .filter_map(|path| path.file_name()?.to_str().map(str::to_owned))
                .collect();
            found.sort();
            subs = found;
        }
        if subs.is_empty() {
            subs.push(".".to_owned());
        }

        for sub in subs {
            let sub_path = if sub == "." {
                repo_path.clone()
            } else {
                repo_path.join(&sub)
            };
            let wsid = first_line(&sub_path.join(".workshopid")).unwrap_or_else(|| repo_wsid.clone());

            out.push(Repo {
                repo: repo.to_owned(),
                sub: sub.clone(),
                remote: remote.clone(),
                wsid,
                branch: branch.clone(),
            });
        }
    }

    Ok(out)
}

/// `$HOME/gserv/repos`, the layout gserv creates.
pub fn default_root() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| PathBuf::from(home).join("gserv").join("repos"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// Builds a repos root covering every shape the real one has. Tests run in
    /// parallel, so each call gets its own tree.
    fn fixture() -> PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static NEXT: AtomicU32 = AtomicU32::new(0);
        let root = std::env::temp_dir().join(format!(
            "mc-repos-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&root);

        // a repo that is itself one addon, on a branch, with a workshop id
        let simple = root.join("simple-addon");
        fs::create_dir_all(simple.join("lua")).unwrap();
        fs::create_dir_all(simple.join(".git")).unwrap();
        fs::write(simple.join(".git/HEAD"), "ref: refs/heads/master\n").unwrap();
        fs::write(
            simple.join(".git/config"),
            "[core]\n\trepositoryformatversion = 0\n[remote \"origin\"]\n\turl = https://github.com/Metastruct/simple.git\n\tfetch = +refs/heads/*\n",
        )
        .unwrap();
        fs::write(simple.join(".workshopid"), "123456\n").unwrap();

        // a repo holding several addons in subfolders, each with its own id
        let multi = root.join("multi-addon");
        fs::create_dir_all(multi.join("first/lua")).unwrap();
        fs::create_dir_all(multi.join("second/gamemodes")).unwrap();
        fs::create_dir_all(multi.join("docs")).unwrap();
        fs::create_dir_all(multi.join(".git")).unwrap();
        fs::write(multi.join(".git/HEAD"), "ref: refs/heads/feature/new-thing\n").unwrap();
        fs::write(multi.join(".git/config"), "[remote \"origin\"]\n\turl = git@github.com:Metastruct/multi.git\n").unwrap();
        fs::write(multi.join(".workshopid"), "999\n").unwrap();
        fs::write(multi.join("first/.workshopid"), "111\n").unwrap();

        // detached head, no remote, addon.json as the only marker
        let detached = root.join("detached-addon");
        fs::create_dir_all(detached.join(".git")).unwrap();
        fs::write(detached.join("addon.json"), "{}").unwrap();
        fs::write(detached.join(".git/HEAD"), "9f8e7d6c5b4a39281706f5e4d3c2b1a098765432\n").unwrap();
        fs::write(detached.join(".git/config"), "[core]\n").unwrap();

        // .git as a pointer file, the worktree/submodule shape
        let worktree = root.join("worktree-addon");
        fs::create_dir_all(worktree.join("lua")).unwrap();
        let real_git = root.join("real-git");
        fs::create_dir_all(&real_git).unwrap();
        fs::write(worktree.join(".git"), "gitdir: ../real-git\n").unwrap();
        fs::write(real_git.join("HEAD"), "ref: refs/heads/dev\n").unwrap();
        fs::write(real_git.join("config"), "[remote \"origin\"]\n\turl = https://git.example/wt.git\n").unwrap();

        // not an addon at all: no lua/, no gamemodes/, no addon.json
        fs::create_dir_all(root.join("just-data/assets")).unwrap();

        root
    }

    fn rows() -> Vec<Repo> {
        enumerate(&fixture()).unwrap()
    }

    fn find<'a>(rows: &'a [Repo], repo: &str, sub: &str) -> &'a Repo {
        rows.iter()
            .find(|r| r.repo == repo && r.sub == sub)
            .unwrap_or_else(|| panic!("no row for {repo}/{sub}"))
    }

    #[test]
    fn a_repo_that_is_one_addon_reports_a_single_dot_row() {
        let rows = rows();
        let r = find(&rows, "simple-addon", ".");
        assert_eq!(r.branch, "master");
        assert_eq!(r.remote, "https://github.com/Metastruct/simple.git");
        assert_eq!(r.wsid, "123456");
        assert_eq!(rows.iter().filter(|r| r.repo == "simple-addon").count(), 1);
    }

    #[test]
    fn subfolder_addons_each_get_a_row_and_non_addon_folders_do_not() {
        let rows = rows();
        let subs: Vec<&str> = rows
            .iter()
            .filter(|r| r.repo == "multi-addon")
            .map(|r| r.sub.as_str())
            .collect();
        assert_eq!(subs, vec!["first", "second"], "docs/ is not an addon root");
    }

    /// A sub with its own id wins; one without inherits the repo's.
    #[test]
    fn workshop_ids_fall_back_from_sub_to_repo() {
        let rows = rows();
        assert_eq!(find(&rows, "multi-addon", "first").wsid, "111");
        assert_eq!(find(&rows, "multi-addon", "second").wsid, "999");
    }

    #[test]
    fn a_branch_containing_slashes_keeps_only_its_last_segment() {
        assert_eq!(parse_head("ref: refs/heads/feature/new-thing\n").as_deref(), Some("new-thing"));
    }

    #[test]
    fn a_detached_head_reports_a_short_sha() {
        let rows = rows();
        let r = find(&rows, "detached-addon", ".");
        assert_eq!(r.branch, "9f8e7d6");
        assert_eq!(r.remote, "", "no origin remote configured");
    }

    #[test]
    fn a_git_pointer_file_is_followed() {
        let rows = rows();
        let r = find(&rows, "worktree-addon", ".");
        assert_eq!(r.branch, "dev");
        assert_eq!(r.remote, "https://git.example/wt.git");
    }

    /// The shell script it replaces emitted "." for a repo with no addon root,
    /// and the bridge's resolver relies on that.
    #[test]
    fn a_repo_with_no_addon_root_still_reports_one_row() {
        let rows = rows();
        assert_eq!(find(&rows, "just-data", ".").sub, ".");
    }

    #[test]
    fn only_the_origin_remote_is_taken() {
        let config = "[remote \"upstream\"]\n\turl = https://wrong/one.git\n[remote \"origin\"]\n\turl = https://right/one.git\n";
        assert_eq!(parse_remote(config).as_deref(), Some("https://right/one.git"));
    }
}
