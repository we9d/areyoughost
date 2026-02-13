use anyhow::{Result, anyhow};
use reqwest::Client;
use crate::models::GameResult;
use urlencoding::encode;
use std::time::Duration;

pub struct FirebaseClient {
    base_url: String,
    client: Client,
    auth_token: Option<String>,
}

impl FirebaseClient {
    /// Create a new Firebase client with timeout and validation
    /// 
    /// # Arguments
    /// * `base_url` - The Firebase Realtime Database URL (must start with https://)
    /// * `auth_token` - Optional ID token for authentication
    pub fn new(base_url: &str, auth_token: Option<String>) -> Result<Self> {
        if !base_url.starts_with("https://") {
            return Err(anyhow!("Invalid Firebase URL: must start with https://"));
        }

        // Remove trailing slash if present
        let base_url = base_url.trim_end_matches('/').to_string();
        
        // Build client with timeout and user agent
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("areyoughost/0.1")
            .build()
            .map_err(|e| anyhow!("Failed to build HTTP client: {}", e))?;

        Ok(Self {
            base_url,
            client,
            auth_token,
        })
    }

    /// Helper to append auth token to URL
    fn append_auth(&self, url: &str) -> String {
        if let Some(token) = &self.auth_token {
            let sep = if url.contains('?') { "&" } else { "?" };
            format!("{}{}{}", url, sep, "auth=".to_string() + &encode(token))
        } else {
            url.to_string()
        }
    }

    /// Helper to handle response status
    async fn handle_response(&self, response: reqwest::Response) -> Result<()> {
        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            
            match status.as_u16() {
                401 | 403 => Err(anyhow!("Firebase Auth/Permission error {}: {}", status, text)),
                404 => Err(anyhow!("Firebase Not found (check URL) {}: {}", status, text)),
                _ => Err(anyhow!("Firebase API error {}: {}", status, text)),
            }
        }
    }

    /// Sync a completed game result (Auto-ID)
    /// POST /game_results.json
    pub async fn sync_game_result(&self, result: &GameResult) -> Result<()> {
        let url = self.append_auth(&format!("{}/game_results.json", self.base_url));
        
        let response = self.client.post(&url)
            .json(result)
            .send()
            .await
            .map_err(|e| anyhow!("Network error syncing to Firebase: {}", e))?;

        self.handle_response(response).await
    }

    /// Upsert a game result by ID (Idempotent)
    /// PUT /game_results/{game_id}.json
    pub async fn upsert_game_result(&self, game_id: &str, result: &GameResult) -> Result<()> {
        let safe_id = encode(game_id);
        let url = self.append_auth(&format!("{}/game_results/{}.json", self.base_url, safe_id));

        let response = self.client.put(&url)
            .json(result)
            .send()
            .await
            .map_err(|e| anyhow!("Network error upserting to Firebase: {}", e))?;

        self.handle_response(response).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_construction() {
        let url = "https://test-project.firebaseio.com/";
        let client = FirebaseClient::new(url, None).unwrap();
        assert_eq!(client.base_url, "https://test-project.firebaseio.com");
    }

    #[test]
    fn test_invalid_url() {
        let url = "http://insecure.firebaseio.com";
        assert!(FirebaseClient::new(url, None).is_err());
    }

    #[test]
    fn test_auth_token_encoding() {
        let url = "https://test.firebaseio.com";
        let token = "token/with+special=chars";
        let client = FirebaseClient::new(url, Some(token.to_string())).unwrap();
        
        let req_url = client.append_auth(&format!("{}/data.json", client.base_url));
        // encoded: token%2Fwith%2Bspecial%3Dchars
        assert!(req_url.contains("auth=token%2Fwith%2Bspecial%3Dchars"));
    }

    #[test]
    fn test_game_id_encoded_in_path() {
        let url = "https://test.firebaseio.com";
        let client = FirebaseClient::new(url, None).unwrap();

        let game_id = "id/with?bad#chars";
        let safe = encode(game_id);
        let req_url = format!("{}/game_results/{}.json", client.base_url, safe);

        assert!(!req_url.contains(game_id)); // Should not contain raw ID
        assert!(req_url.contains("id%2Fwith%3Fbad%23chars")); // Should contain encoded ID
    }
}
