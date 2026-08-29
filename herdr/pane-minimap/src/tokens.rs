pub const TITLE_TOKEN: &str = "minimap_title";
pub const LINE_TOKEN_COUNT: usize = 6;

pub fn cleared_minimap_tokens() -> serde_json::Map<String, serde_json::Value> {
    let mut out = serde_json::Map::new();
    out.insert(TITLE_TOKEN.into(), serde_json::Value::Null);
    for i in 0..LINE_TOKEN_COUNT {
        out.insert(format!("minimap{i}"), serde_json::Value::Null);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleared_tokens_null_all_minimap_keys() {
        let tokens = cleared_minimap_tokens();
        assert_eq!(tokens.get(TITLE_TOKEN), Some(&serde_json::Value::Null));
        for i in 0..LINE_TOKEN_COUNT {
            assert_eq!(
                tokens.get(&format!("minimap{i}")),
                Some(&serde_json::Value::Null)
            );
        }
        assert_eq!(tokens.len(), LINE_TOKEN_COUNT + 1);
    }
}
