//! Mutating metadata diagnostics must never fall back to a personal profile.
use std::path::{Path, PathBuf};

pub(crate) fn validate_metadata_probe(
    arguments: &[String],
    explicit_state: Option<&Path>,
    protected_profiles: &[PathBuf],
) -> Result<(), String> {
    if !arguments.iter().any(|arg| {
        matches!(
            arg.as_str(),
            "--metadata-ui-probe" | "--metadata-restored-ui-probe"
        )
    }) {
        return Ok(());
    }
    let state = explicit_state.filter(|path| !path.as_os_str().is_empty()).ok_or(
        "Metadata UI probes require an explicit isolated --state-database or LUNCHPAIL_STATE_DATABASE; the personal profile must not be used.",
    )?;
    if state.is_dir() {
        return Err("The isolated probe state database must be a file, not a directory.".into());
    }
    for profile in protected_profiles {
        if resolved_path(state)? == resolved_path(profile)? || same_existing_file(state, profile) {
            return Err(format!(
                "Refusing metadata UI probe against personal profile {}. Choose a separate temporary --state-database.",
                profile.display()
            ));
        }
    }
    Ok(())
}

fn resolved_path(path: &Path) -> Result<PathBuf, String> {
    if let Ok(resolved) = path.canonicalize() {
        return Ok(resolved);
    }
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        std::env::current_dir()
            .map_err(|error| error.to_string())?
            .join(path)
    };
    // A new temporary database does not exist yet; still resolve its parent
    // so directory symlinks and dot components cannot hide a profile alias.
    if let (Some(parent), Some(name)) = (absolute.parent(), absolute.file_name()) {
        if let Ok(parent) = parent.canonicalize() {
            return Ok(parent.join(name));
        }
    }
    Ok(absolute)
}

fn same_existing_file(left: &Path, right: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if let (Ok(left), Ok(right)) = (left.metadata(), right.metadata()) {
            return left.dev() == right.dev() && left.ino() == right.ino();
        }
    }
    #[cfg(not(unix))]
    let _ = (left, right);
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let stamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "lunchpail-probe-safety-{}-{stamp}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            fs::write(path.join("personal.db"), b"personal data must not change").unwrap();
            Self(path)
        }
        fn profile(&self) -> PathBuf {
            self.0.join("personal.db")
        }
        fn check(&self, flag: &str, state: Option<&Path>) -> Result<(), String> {
            let result = validate_metadata_probe(&[flag.into()], state, &[self.profile()]);
            assert_eq!(
                fs::read(self.profile()).unwrap(),
                b"personal data must not change"
            );
            result
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn both_metadata_probes_require_an_explicit_database() {
        let fixture = Fixture::new();
        for flag in ["--metadata-ui-probe", "--metadata-restored-ui-probe"] {
            assert!(fixture.check(flag, None).is_err());
            assert!(fixture.check(flag, Some(Path::new(""))).is_err());
            assert!(fixture.check(flag, Some(&fixture.profile())).is_err());
        }
    }

    #[test]
    fn separate_new_and_existing_test_databases_are_allowed() {
        let fixture = Fixture::new();
        let test = fixture.0.join("isolated.db");
        assert!(fixture.check("--metadata-ui-probe", Some(&test)).is_ok());
        assert!(!test.exists()); // Validation itself does not create a store.
        fs::write(&test, b"isolated fixture").unwrap();
        assert!(
            fixture
                .check("--metadata-restored-ui-probe", Some(&test))
                .is_ok()
        );
        assert_eq!(fs::read(test).unwrap(), b"isolated fixture");
        assert!(
            fixture
                .check("--metadata-ui-probe", Some(&fixture.0))
                .is_err()
        );
    }

    #[test]
    fn ordinary_startup_and_read_only_diagnostics_are_unchanged() {
        let fixture = Fixture::new();
        assert!(fixture.check("lunchpail", None).is_ok());
        assert!(
            fixture
                .check("--local-command-ui-probe", Some(&fixture.profile()))
                .is_ok()
        );
    }

    #[test]
    fn dot_components_do_not_disguise_the_personal_profile() {
        let fixture = Fixture::new();
        fs::create_dir(fixture.0.join("nested")).unwrap();
        let alias = fixture.0.join("nested/../personal.db");
        assert!(fixture.check("--metadata-ui-probe", Some(&alias)).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_and_hardlinks_to_the_personal_profile_are_rejected() {
        let fixture = Fixture::new();
        let symlink = fixture.0.join("symlink.db");
        std::os::unix::fs::symlink(fixture.profile(), &symlink).unwrap();
        assert!(
            fixture
                .check("--metadata-ui-probe", Some(&symlink))
                .is_err()
        );
        let hardlink = fixture.0.join("hardlink.db");
        fs::hard_link(fixture.profile(), &hardlink).unwrap();
        assert!(
            fixture
                .check("--metadata-ui-probe", Some(&hardlink))
                .is_err()
        );
    }
}
