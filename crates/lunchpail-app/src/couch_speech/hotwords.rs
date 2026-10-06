//! Bounded catalog hints for the installed English recognizer. This vocabulary
//! was exported from the upstream SentencePiece model whose first 500 symbols
//! exactly match our pinned tokens.txt; see docs/couch-mode.md for provenance.
pub(crate) const BPE_VOCAB: &str = include_str!("zipformer-en.vocab");

pub(crate) fn phrases(titles: &[String]) -> String {
    let mut seen = std::collections::HashSet::new();
    titles.iter().take(32).filter_map(|title| {
        // The English model has no digit/non-English tokens. Do not create
        // malformed hotwords or silently drop a sequel number from a title.
        if title.len() > 100 || title.chars().any(|c| c.is_alphanumeric() && !c.is_ascii_alphabetic()) {
            return None;
        }
        let text = title.to_ascii_uppercase().split(|c: char| !c.is_ascii_alphabetic())
            .filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ");
        (!text.is_empty() && seen.insert(text.clone())).then_some(text)
    }).collect::<Vec<_>>().join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_bounded_english_phrases_reach_the_native_tokenizer() {
        assert_eq!(phrases(&["Faxanadu".into(), "FAXANADU".into(), "Super Mario Bros.".into()]),
            "FAXANADU\nSUPER MARIO BROS");
        assert!(phrases(&["évil".into(), "Faxanadu 2".into(), "".into()]).is_empty());
        assert_eq!(phrases(&["A : / B\nC".into()]), "A B C");
        assert_eq!(BPE_VOCAB.lines().count(), 500);
        assert!(BPE_VOCAB.lines().any(|line| line.starts_with("▁FA\t")));
    }
}
