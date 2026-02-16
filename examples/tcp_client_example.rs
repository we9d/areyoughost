//! Example: Custom Protocol TCP Client
//!
//! Demonstrates how to connect to the game server using the custom protocol.

use std::io::{Read, Write};
use std::net::TcpStream;

fn main() -> std::io::Result<()> {
    println!("Connecting to server...");

    // Connect to local server
    let mut stream = TcpStream::connect("127.0.0.1:3000")?;
    println!("Connected to server");

    // Send a simple message
    let message = "Hello from custom client!";
    stream.write_all(message.as_bytes())?;
    println!("Sent: {}", message);

    // Read response
    let mut buffer = [0u8; 1024];
    let bytes_read = stream.read(&mut buffer)?;
    let response = String::from_utf8_lossy(&buffer[..bytes_read]);
    println!("Received: {}", response);

    Ok(())
}
