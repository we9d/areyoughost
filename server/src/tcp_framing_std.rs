//! TCP byte framing using **only** the Rust standard library (`std::io`, `std::net`).
//!
//! Format: **4 bytes big-endian `u32` length** followed by exactly that many payload bytes.
//! This is the socket-level contract; higher layers may choose JSON, binary, etc.
//!
//! **Resilience:** use [`configure_stream`] after `accept` so blocking `read_exact` does not
//! hang forever on half-open or dead peers; [`read_frame`] distinguishes clean close vs
//! mid-frame loss vs read timeout.

use std::io::{self, Read, Write};
use std::net::TcpStream;
use std::time::Duration;

/// Maximum allowed payload length (one megabyte), excluding the 4-byte length header.
pub const MAX_PAYLOAD_LEN: u32 = 1_048_576;

/// Outcome of a single framed read from the stream.
#[derive(Debug)]
pub enum FrameRead {
    /// Full payload received.
    Payload(Vec<u8>),
    /// EOF before the 4-byte length header completed (normal peer close).
    Closed,
    /// Header was valid but the body did not arrive in full — typical of cable/Wi‑Fi drop or RST.
    ConnectionLost,
    /// [`TcpStream::set_read_timeout`] fired while waiting for header or body.
    ReadTimedOut,
    /// Declared length exceeds [`MAX_PAYLOAD_LEN`]; caller should send an error frame and drop the connection.
    RejectedTooLarge,
}

/// Apply blocking-socket settings that help detect broken or idle links.
///
/// - `read_timeout_ms` / `write_timeout_ms`: `0` means **no** timeout (wait indefinitely).
/// - Enables **TCP_NODELAY** (disable Nagle) for snappier small game frames.
pub fn configure_stream(stream: &TcpStream, read_timeout_ms: u64, write_timeout_ms: u64) -> io::Result<()> {
    let _ = stream.set_nodelay(true);
    stream.set_read_timeout(if read_timeout_ms > 0 {
        Some(Duration::from_millis(read_timeout_ms))
    } else {
        None
    })?;
    stream.set_write_timeout(if write_timeout_ms > 0 {
        Some(Duration::from_millis(write_timeout_ms))
    } else {
        None
    })?;
    Ok(())
}

/// Read one length-prefixed frame from `reader`.
pub fn read_frame<R: Read>(reader: &mut R) -> io::Result<FrameRead> {
    let mut hdr = [0u8; 4];
    match reader.read_exact(&mut hdr) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(FrameRead::Closed),
        Err(e) if e.kind() == io::ErrorKind::TimedOut => return Ok(FrameRead::ReadTimedOut),
        Err(e) => return Err(e),
    }

    let len = u32::from_be_bytes(hdr);
    if len > MAX_PAYLOAD_LEN {
        return Ok(FrameRead::RejectedTooLarge);
    }

    let mut buf = vec![0u8; len as usize];
    match reader.read_exact(&mut buf) {
        Ok(()) => Ok(FrameRead::Payload(buf)),
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => Ok(FrameRead::ConnectionLost),
        Err(e) if e.kind() == io::ErrorKind::TimedOut => Ok(FrameRead::ReadTimedOut),
        Err(e) => Err(e),
    }
}

/// Write one length-prefixed frame: `u32` BE length, then `payload`.
pub fn write_frame<W: Write>(writer: &mut W, payload: &[u8]) -> io::Result<()> {
    let n = payload.len();
    if n > MAX_PAYLOAD_LEN as usize {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "payload length exceeds MAX_PAYLOAD_LEN",
        ));
    }
    writer.write_all(&(n as u32).to_be_bytes())?;
    writer.write_all(payload)?;
    writer.flush()
}
