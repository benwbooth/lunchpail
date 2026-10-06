//! Dedicated HyperSpin Main Menu wheels, never game-logo archives.
use anyhow::{Context, Result, ensure};
use std::io::Read;
use std::path::{Path, PathBuf};

pub(crate) const REMOTE: &str = "/Official/Ninja2bseen's Dojo/HyperSpin/Media/Main Menu/Images.7z";

pub(crate) fn archive_path(media: &Path) -> PathBuf {
    media.join("emumovies-archives/hyperspin-main-menu-images.7z")
}

fn directory(media: &Path) -> PathBuf {
    media.join("emumovies-system-wheels/v1")
}

pub(crate) fn ready(media: &Path) -> bool {
    directory(media).join("complete").is_file()
}

pub(crate) fn key(name: &str) -> String {
    name.chars()
        .filter(char::is_ascii_alphanumeric)
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

pub(crate) fn find(media: &Path, candidates: &[String]) -> Option<PathBuf> {
    if !ready(media) {
        return None;
    }
    candidates.iter().find_map(|name| {
        ["png", "webp", "jpg"]
            .into_iter()
            .map(|ext| directory(media).join(format!("{}.{ext}", key(name))))
            .find(|path| path.metadata().is_ok_and(|m| m.is_file() && m.len() > 0))
    })
}

fn wheel_member(name: &str) -> Option<String> {
    let normalized = name.replace('\\', "/");
    let parts: Vec<_> = normalized.split('/').collect();
    if parts
        .iter()
        .any(|p| p.is_empty() || *p == "." || *p == "..")
        || parts.len() < 2
        || !parts[parts.len() - 2].eq_ignore_ascii_case("Wheel")
    {
        return None;
    }
    let (stem, ext) = parts.last()?.rsplit_once('.')?;
    let ext = ext.to_ascii_lowercase();
    let key = key(stem);
    if key.is_empty() || !matches!(ext.as_str(), "png" | "webp" | "jpg") {
        return None;
    }
    Some(format!("{key}.{ext}"))
}

pub(crate) fn extract(media: &Path) -> Result<usize> {
    let mut archive =
        sevenz_rust2::ArchiveReader::open(archive_path(media), sevenz_rust2::Password::empty())?;
    ensure!(
        archive.archive().files.len() <= 20_000,
        "Too many system artwork members"
    );
    let size = archive.archive().files.iter().try_fold(0u64, |n, e| {
        n.checked_add(e.size())
            .context("System artwork size overflow")
    })?;
    ensure!(
        size <= 512 * 1024 * 1024,
        "System artwork exceeds 512 MiB expanded"
    );
    let output = directory(media);
    std::fs::create_dir_all(&output)?;
    let mut count = 0;
    archive.for_each_entries(|entry, reader| {
        let Some(name) = wheel_member(entry.name()).filter(|_| !entry.is_directory()) else {
            std::io::copy(reader, &mut std::io::sink())?;
            return Ok(true);
        };
        if entry.size() > 16 * 1024 * 1024 {
            return Err(std::io::Error::other("System wheel exceeds 16 MiB").into());
        }
        let mut bytes = Vec::new();
        reader.take(16 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 != entry.size() || bytes.is_empty() {
            return Err(std::io::Error::other("Invalid system wheel size").into());
        }
        let path = output.join(name);
        let temporary = path.with_extension("tmp");
        std::fs::write(&temporary, bytes)?;
        std::fs::rename(temporary, path)?;
        count += 1;
        Ok(true)
    })?;
    ensure!(count > 0, "HyperSpin pack contains no system wheels");
    std::fs::write(output.join("complete"), count.to_string())?;
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_exact_wheel_directory_images_are_selected() {
        assert_eq!(
            wheel_member("Images/Wheel/Atari 8-Bit.png").as_deref(),
            Some("atari8bit.png")
        );
        assert_eq!(
            wheel_member("Images\\Wheel\\Sony PlayStation.PNG").as_deref(),
            Some("sonyplaystation.png")
        );
        for name in [
            "Images/Artwork1/Atari.png",
            "Images/Wheel - Carbon/Atari.png",
            "../Wheel/Atari.png",
            "/Wheel/Atari.png",
            "Wheel/Atari.swf",
        ] {
            assert!(wheel_member(name).is_none(), "{name}");
        }
    }

    #[test]
    fn extracts_once_and_matches_exact_system_identity() {
        let media = tempfile::tempdir().unwrap();
        let path = archive_path(media.path());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let mut writer = sevenz_rust2::ArchiveWriter::create(path).unwrap();
        for name in [
            "Images/Artwork1/Nintendo DS.png",
            "Images/Wheel/Nintendo DS.png",
            "Images/Wheel/Nintendo 3DS.png",
        ] {
            writer
                .push_archive_entry(
                    sevenz_rust2::ArchiveEntry::new_file(name),
                    Some(&b"image"[..]),
                )
                .unwrap();
        }
        writer.finish().unwrap();
        assert!(!ready(media.path()));
        assert_eq!(extract(media.path()).unwrap(), 2);
        assert!(ready(media.path()));
        assert!(
            find(media.path(), &["Nintendo DS".into()])
                .unwrap()
                .ends_with("nintendods.png")
        );
        assert!(find(media.path(), &["Nintendo".into()]).is_none());
    }
}
