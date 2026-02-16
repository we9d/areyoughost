use reqwest::Client;
use serde::{Deserialize, Serialize};
use anyhow::Result;

#[derive(Clone)]
pub struct HttpClient {
    base_url: String,
    client: Client,
    pub auth_token: Option<String>,
}

#[derive(Serialize)]
struct RegisterRequest {
    player_name: String,
    password: String,
}

#[derive(Serialize)]
struct LoginRequest {
    player_name: String,
    password: String,
}

#[derive(Deserialize)]
struct AuthResponse {
    access_token: String,
    refresh_token: String,
    player_id: String,
    player_name: String,
}

impl HttpClient {
    pub fn new(base_url: String) -> Self {
        HttpClient {
            base_url,
            client: Client::new(),
            auth_token: None,
        }
    }

    pub async fn register(&mut self, username: String, password: String) -> Result<String> {
        let url = format!("{}/auth/register", self.base_url);
        let resp = self.client.post(&url)
            .json(&RegisterRequest {
                player_name: username,
                password,
            })
            .send()
            .await?;

        if !resp.status().is_success() {
            let error_text = resp.text().await?;
            return Err(anyhow::anyhow!("Registration failed: {}", error_text));
        }

        // For now, register just returns success. We might want to auto-login.
        Ok("Registration successful".to_string())
    }

    pub async fn login(&mut self, username: String, password: String) -> Result<(String, String)> {
        let url = format!("{}/auth/login", self.base_url);
        let resp = self.client.post(&url)
            .json(&LoginRequest {
                player_name: username,
                password,
            })
            .send()
            .await?;

        if !resp.status().is_success() {
            return Err(anyhow::anyhow!("Login failed: {}", resp.status()));
        }

        let auth_data: AuthResponse = resp.json().await?;
        
        // Store token
        self.auth_token = Some(auth_data.access_token.clone());

        Ok((auth_data.player_id, auth_data.access_token))
    }
}
