//! Length-prefixed frames over [`tokio::io`] (same layout as [`crate::tcp_framing_std`]).

use std::io;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::tcp_framing_std::{FrameRead, MAX_PAYLOAD_LEN};

pub async fn read_frame<R: AsyncRead + Unpin>(reader: &mut R) -> io::Result<FrameRead> {
    let mut hdr = [0u8; 4];
    match reader.read_exact(&mut hdr).await {
        Ok(_) => {}
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(FrameRead::Closed),
        Err(e) if e.kind() == io::ErrorKind::TimedOut => return Ok(FrameRead::ReadTimedOut),
        Err(e) => return Err(e),
    }

    let len = u32::from_be_bytes(hdr);
    if len > MAX_PAYLOAD_LEN {
        return Ok(FrameRead::RejectedTooLarge);
    }

    let mut buf = vec![0u8; len as usize];
    match reader.read_exact(&mut buf).await {
        Ok(_) => Ok(FrameRead::Payload(buf)),
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => Ok(FrameRead::ConnectionLost),
        Err(e) if e.kind() == io::ErrorKind::TimedOut => Ok(FrameRead::ReadTimedOut),
        Err(e) => Err(e),
    }
}

pub async fn write_frame<W: AsyncWrite + Unpin>(writer: &mut W, payload: &[u8]) -> io::Result<()> {
    let n = payload.len();
    if n > MAX_PAYLOAD_LEN as usize {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "payload length exceeds MAX_PAYLOAD_LEN",
        ));
    }
    writer.write_all(&(n as u32).to_be_bytes()).await?;
    writer.write_all(payload).await?;
    writer.flush().await
}
