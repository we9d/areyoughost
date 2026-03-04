//! # Auth Helpers
//!
//! JWT sign/verify + password hashing utilities.

use anyhow::{Context, Result};
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// JWT claims we embed in every access token.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    /// player_id (UUID as string)
    pub sub: String,
    /// username for convenience
    pub username: String,
    /// expiry (Unix timestamp)
    pub exp: usize,
}

/// Sign a JWT for a given player. `secret` comes from `JWT_SECRET` env var.
pub fn sign_jwt(player_id: Uuid, username: &str, secret: &str) -> Result<String> {
    let exp = chrono::Utc::now()
        .checked_add_signed(chrono::Duration::days(7))
        .context("overflow computing exp")?
        .timestamp() as usize;

    let claims = Claims {
        sub: player_id.to_string(),
        username: username.to_string(),
        exp,
    };

    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .context("failed to encode JWT")?;

    Ok(token)
}

/// Verify a JWT and return the embedded claims.
pub fn verify_jwt(token: &str, secret: &str) -> Result<Claims> {
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .context("invalid or expired token")?;

    Ok(token_data.claims)
}

/// Hash a plaintext password with Argon2id.
pub fn hash_password(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("argon2 hash error: {e}"))?
        .to_string();
    Ok(hash)
}

/// Verify a plaintext password against an Argon2 hash string.
pub fn verify_password(password: &str, hash: &str) -> Result<bool> {
    let parsed = PasswordHash::new(hash).map_err(|e| anyhow::anyhow!("bad hash: {e}"))?;
    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok())
}
