use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use serde::{Deserialize, Serialize};

use crate::state::manager::AppState;
use crate::auth::{hash_password, sign_jwt, verify_password};

#[derive(Deserialize, Debug)]
#[serde(tag = "command")]
pub enum ClientCommand {
    Login {
        username: String,
        password: String,
    },
    Register {
        username: String,
        password: String,
    }
}

#[derive(Serialize, Debug)]
#[serde(tag = "response_type")]
pub enum ServerResponse {
    AuthSuccess {
        token: String,
        player_id: String,
        username: String,
    },
    AuthError {
        message: String,
    }
}

pub async fn start_raw_tcp_server(state: Arc<AppState>) {
    let listener = TcpListener::bind("0.0.0.0:3001").await.expect("Failed to bind raw TCP port 3001");
    tracing::info!("Raw TCP server listening on 0.0.0.0:3001");

    loop {
        match listener.accept().await {
            Ok((socket, addr)) => {
                tracing::info!("New TCP connection from {}", addr);
                let state_clone = state.clone();
                tokio::spawn(async move {
                    handle_connection(socket, state_clone).await;
                });
            }
            Err(e) => tracing::error!("Error accepting connection: {}", e),
        }
    }
}

async fn handle_connection(mut socket: TcpStream, state: Arc<AppState>) {
    let (reader, mut writer) = socket.split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    loop {
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => {
                break;
            }
            Ok(_) => {
                let trimmed = line.trim();
                let cmd: Result<ClientCommand, _> = serde_json::from_str(trimmed);
                
                match cmd {
                    Ok(ClientCommand::Login { username, password }) => {
                        let response = process_login(&username, &password, &state).await;
                        let mut res_str = serde_json::to_string(&response).unwrap();
                        res_str.push('\n');
                        let _ = writer.write_all(res_str.as_bytes()).await;
                    }
                    Ok(ClientCommand::Register { username, password }) => {
                        let response = process_register(&username, &password, &state).await;
                        let mut res_str = serde_json::to_string(&response).unwrap();
                        res_str.push('\n');
                        let _ = writer.write_all(res_str.as_bytes()).await;
                    }
                    Err(e) => {
                        let error = ServerResponse::AuthError {
                            message: format!("Invalid JSON or Command: {}", e),
                        };
                         let mut res_str = serde_json::to_string(&error).unwrap();
                        res_str.push('\n');
                        let _ = writer.write_all(res_str.as_bytes()).await;
                    }
                }
            }
            Err(e) => {
                tracing::error!("Error reading line from TCP stream: {}", e);
                break;
            }
        }
    }
}

#[derive(sqlx::FromRow)]
struct PlayerRow {
    player_id: String,
    username: String,
}

#[derive(sqlx::FromRow)]
struct PlayerAuthRow {
    player_id: String,
    username: String,
    password_hash: String,
}

async fn process_login(uname: &str, pwd: &str, state: &Arc<AppState>) -> ServerResponse {
    let row = sqlx::query_as::<_, PlayerAuthRow>(
        "SELECT player_id::text, username, password_hash FROM players WHERE username = $1",
    )
    .bind(&uname.trim())
    .fetch_optional(&state.db)
    .await;

    match row {
        Ok(Some(r)) => {
            if let Ok(true) = verify_password(pwd, &r.password_hash) {
                let pid_uuid = uuid::Uuid::parse_str(&r.player_id).unwrap_or_default();
                if let Ok(token) = sign_jwt(pid_uuid, &r.username, &state.jwt_secret) {
                    return ServerResponse::AuthSuccess {
                        token,
                        player_id: r.player_id,
                        username: r.username,
                    };
                }
            }
            ServerResponse::AuthError { message: "Invalid username or password".to_string() }
        }
        Ok(None) => ServerResponse::AuthError { message: "Invalid username or password".to_string() },
        Err(e) => ServerResponse::AuthError { message: format!("Database error: {}", e) },
    }
}

async fn process_register(uname: &str, pwd: &str, state: &Arc<AppState>) -> ServerResponse {
    let uname = uname.trim();
    if uname.len() < 3 || uname.len() > 20 {
        return ServerResponse::AuthError { message: "Username must be 3-20 chars".to_string() };
    }
    if pwd.len() < 6 {
        return ServerResponse::AuthError { message: "Password must be at least 6 chars".to_string() };
    }
    
    let hash = match hash_password(pwd) {
         Ok(h) => h,
         Err(_) => return ServerResponse::AuthError { message: "Hash error".to_string() }
    };
    let new_player_id = uuid::Uuid::new_v4().to_string();

    let result = sqlx::query_as::<_, PlayerRow>(
        "INSERT INTO players (player_id, username, password_hash, created_at, updated_at) VALUES ($1::uuid, $2, $3, now(), now()) RETURNING player_id::text, username",
    )
    .bind(&new_player_id)
    .bind(&uname)
    .bind(&hash)
    .fetch_one(&state.db)
    .await;

    match result {
        Ok(row) => {
             let pid_uuid = uuid::Uuid::parse_str(&row.player_id).unwrap_or_default();
             if let Ok(token) = sign_jwt(pid_uuid, &row.username, &state.jwt_secret) {
                  return ServerResponse::AuthSuccess {
                      token,
                      player_id: row.player_id,
                      username: row.username,
                  };
             }
             ServerResponse::AuthError { message: "Error signing token".to_string() }
        }
        Err(sqlx::Error::Database(e)) if e.constraint() == Some("players_username_key") => {
             ServerResponse::AuthError { message: "Username already taken".to_string() }
        }
        Err(e) => ServerResponse::AuthError { message: format!("DB error: {}", e) }
    }
}
