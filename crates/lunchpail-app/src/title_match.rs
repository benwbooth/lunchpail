//! Conservative spelling/pronunciation similarity for catalog title recovery.
//! This proposes candidates, never IDs or actions. Exact matching, catalog
//! visibility, platform constraints, confidence and ambiguity live in the caller.

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Similarity {
    pub spelling: f64,
    pub phonetic: f64,
    pub score: f64,
}

pub(crate) fn key(text: &str) -> String {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .map(|word| if word == "brothers" { "bros" } else { word })
        .collect()
}

pub(crate) fn compatible_initial(left: &str, right: &str) -> bool {
    fn initial(text: &str) -> u8 {
        let mut chars = text.bytes().filter(u8::is_ascii_alphanumeric).map(|c| c.to_ascii_lowercase());
        match (chars.next().unwrap_or(0), chars.next().unwrap_or(0)) {
            (b'p', b'h') | (b'v', _) => b'f',
            (b'c', b'e' | b'i' | b'y') | (b'z', _) => b's',
            (b'c' | b'q' | b'x', _) => b'k',
            (b'a' | b'e' | b'i' | b'o' | b'u' | b'y', _) => b'a',
            (c, _) => c,
        }
    }
    initial(left) == initial(right)
}

fn identity_terms(text: &str) -> Vec<String> {
    text.to_lowercase().split(|c: char| !c.is_alphanumeric())
        .filter_map(|word| {
            let term = match word {
                "one" | "i" => "1", "two" | "ii" => "2", "three" | "iii" => "3",
                "four" | "iv" => "4", "five" | "v" => "5", "six" | "vi" => "6",
                "seven" | "vii" => "7", "eight" | "viii" => "8", "nine" | "ix" => "9",
                "ten" | "x" => "10", "brothers" => "bros", other => other,
            };
            (term.chars().any(|c| c.is_ascii_digit()) || matches!(term,
                "super" | "new" | "bros" | "deluxe" | "remastered" | "remake"
                | "collection" | "trilogy" | "bundle" | "plus" | "advance"))
                .then(|| term.to_owned())
        }).collect()
}

// A deliberately small pronunciation key, not an English dictionary. Preserve
// consonant order and vowel positions; do not collapse titles to Soundex buckets.
fn pronunciation(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut result = String::new();
    let mut i = 0;
    while i < bytes.len() {
        let next = bytes.get(i + 1).copied().unwrap_or(0);
        let (sound, advance) = match (bytes[i], next) {
            (b'p', b'h') => ("f", 2),
            (b'c', b'k') | (b'q', b'u') => ("k", 2),
            (b's', b'h') | (b'c', b'h') => ("s", 2),
            (b'x', _) => ("ks", 1),
            (b'c', b'e' | b'i' | b'y') | (b'z', _) => ("s", 1),
            (b'c' | b'q', _) => ("k", 1),
            (b'v', _) => ("f", 1),
            (b'a' | b'e' | b'i' | b'o' | b'u' | b'y', _) => ("a", 1),
            (b'h', _) => ("", 1),
            _ => (&text[i..i + 1], 1),
        };
        for c in sound.chars() {
            if !result.ends_with(c) { result.push(c); }
        }
        i += advance;
    }
    result
}

fn distance(a: &[u8], b: &[u8]) -> usize {
    let mut older = vec![0; b.len() + 1];
    let mut previous: Vec<_> = (0..=b.len()).collect();
    let mut current = vec![0; b.len() + 1];
    for (i, &left) in a.iter().enumerate() {
        current[0] = i + 1;
        for (j, &right) in b.iter().enumerate() {
            current[j + 1] = (previous[j + 1] + 1).min(current[j] + 1)
                .min(previous[j] + usize::from(left != right));
            if i > 0 && j > 0 && left == b[j - 1] && a[i - 1] == right {
                current[j + 1] = current[j + 1].min(older[j - 1] + 1);
            }
        }
        std::mem::swap(&mut older, &mut previous);
        std::mem::swap(&mut previous, &mut current);
    }
    previous[b.len()]
}

pub(crate) fn similarity(left: &str, right: &str) -> Similarity {
    if !compatible_initial(left, right) { return Similarity::default(); }
    let a = key(left);
    let b = key(right);
    if a.is_empty() || b.is_empty() { return Similarity::default(); }
    if a == b { return Similarity { spelling: 1.0, phonetic: 1.0, score: 1.0 }; }
    // Keep non-Latin titles exact until there is an appropriate pronunciation
    // model. Bound work and reject missing sequel/edition qualifiers outright.
    if !a.is_ascii() || !b.is_ascii() || a.len().min(b.len()) < 4
        || a.len().max(b.len()) > 80 || identity_terms(left) != identity_terms(right)
        || a.len().min(b.len()) * 10 < a.len().max(b.len()) * 6
    { return Similarity::default(); }
    let spelling = 1.0 - distance(a.as_bytes(), b.as_bytes()) as f64 / a.len().max(b.len()) as f64;
    if spelling < 0.5 { return Similarity::default(); }
    let pa = pronunciation(&a);
    let pb = pronunciation(&b);
    if pa.is_empty() || pb.is_empty() || (pa.as_bytes()[0] != pb.as_bytes()[0] && spelling < 0.9) {
        return Similarity::default();
    }
    let phonetic = 1.0 - distance(pa.as_bytes(), pb.as_bytes()) as f64 / pa.len().max(pb.len()) as f64;
    let score = 0.35 * spelling + 0.65 * phonetic;
    if phonetic < 0.68 || score < 0.72 { return Similarity::default(); }
    Similarity { spelling, phonetic, score }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recovers_pronunciation_and_spacing_without_a_title_alias_list() {
        for (heard, title) in [
            ("facsinidu", "Faxanadu"), ("fax in a do", "Faxanadu"),
            ("faxanadoo", "Faxanadu"), ("fascinadu", "Faxanadu"),
            ("metrod", "Metroid"), ("castlevanya", "Castlevania"),
        ] {
            let score = similarity(heard, title);
            assert!(score.score >= 0.80, "{heard} / {title}: {score:?}");
        }
        assert_eq!(key("Super Mario Brothers!"), key("Super Mario Bros."));
    }
    #[test]
    fn keeps_other_games_sequels_and_editions_distinct() {
        for (heard, title) in [
            ("Mario", "Faxanadu"), ("Mario", "Wario"),
            ("Faxanadu 2", "Faxanadu"), ("Metroid", "Metroid II"),
            ("Super Mario", "Super Mario Bros."), ("Super Mario Bros.", "New Super Mario Bros."),
            ("Sonic", "Sonic Collection"), ("Zelda", "Zelda Deluxe"),
            ("nothing matches", "Faxanadu"), ("", ""), ("Go", "God"),
            ("ゲーム", "ゲエム"),
        ] { assert_eq!(similarity(heard, title).score, 0.0, "{heard} / {title}"); }
    }
}
