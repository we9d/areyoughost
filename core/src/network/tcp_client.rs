//! # TCP Client Module
//!
//! Raw TCP client implementation with basic string splitting

use anyhow::Result;
use tokio::net::TcpStream;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};

/// TCP client to communicate with the raw TCP server
pub struct TcpClient {
    read_half: BufReader<OwnedReadHalf>,
    write_half: OwnedWriteHalf,
}

impl TcpClient {
    /// Connect to a server
    pub async fn connect(addr: &str) -> Result<Self> {
        let stream = TcpStream::connect(addr).await?;
        let (read_half, write_half) = stream.into_split();
        Ok(Self {
            read_half: BufReader::new(read_half),
            write_half,
        })
    }

    /// Send a JSON command ending with a newline
    pub async fn send_command(&mut self, cmd_json: &str) -> Result<()> {
        let mut data = cmd_json.to_string();
        if !data.ends_with('\n') {
            data.push('\n');
        }
        self.write_half.write_all(data.as_bytes()).await?;
        Ok(())
    }

    /// Read a JSON response line
    pub async fn read_line(&mut self) -> Result<String> {
        let mut line = String::new();
        let bytes_read = self.read_half.read_line(&mut line).await?;
        if bytes_read == 0 {
            return Err(anyhow::anyhow!("Connection closed by server"));
        }
        Ok(line.trim().to_string())
    }
}
