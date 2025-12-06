//! WebTransport-like session layer over iroh QUIC connections
//!
//! This provides a simplified WebTransport-compatible session for use with moq-lite.
//! Since iroh-live uses a simplified "raw" mode that bypasses HTTP/3 framing,
//! we can implement a compatible session directly over iroh's QUIC connections.

use bytes::Bytes;
use iroh::endpoint::Connection;
use iroh::EndpointId;
use iroh_quinn as quinn;
use thiserror::Error;
use url::Url;

/// Session error type
#[derive(Debug, Clone, Error)]
pub enum SessionError {
    #[error("connection error: {0}")]
    Connection(#[from] iroh::endpoint::ConnectionError),

    #[error("write error")]
    Write,

    #[error("read error")]
    Read,

    #[error("session closed")]
    Closed,

    #[error("datagram error")]
    Datagram,
}

// Implement the web_transport_trait::Error marker
impl web_transport_trait::Error for SessionError {}

/// A send stream wrapper
pub struct SendStream {
    inner: quinn::SendStream,
}

impl SendStream {
    pub fn new(stream: quinn::SendStream) -> Self {
        Self { inner: stream }
    }

    pub async fn write(&mut self, data: &[u8]) -> Result<usize, SessionError> {
        self.inner.write(data).await.map_err(|_| SessionError::Write)
    }

    pub async fn write_all(&mut self, data: &[u8]) -> Result<(), SessionError> {
        self.inner.write_all(data).await.map_err(|_| SessionError::Write)
    }

    pub fn finish(&mut self) -> Result<(), SessionError> {
        self.inner.finish().map_err(|_| SessionError::Write)
    }

    pub fn reset(&mut self, code: u32) {
        let code = quinn::VarInt::try_from(code).unwrap_or(quinn::VarInt::from_u32(0));
        self.inner.reset(code).ok();
    }

    pub fn set_priority(&mut self, priority: i32) {
        self.inner.set_priority(priority).ok();
    }
}

impl std::fmt::Debug for SendStream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SendStream").finish()
    }
}

/// A receive stream wrapper
pub struct RecvStream {
    inner: quinn::RecvStream,
}

impl RecvStream {
    pub fn new(stream: quinn::RecvStream) -> Self {
        Self { inner: stream }
    }

    pub async fn read(&mut self, buf: &mut [u8]) -> Result<Option<usize>, SessionError> {
        self.inner.read(buf).await.map_err(|_| SessionError::Read)
    }

    pub async fn read_exact(&mut self, buf: &mut [u8]) -> Result<(), SessionError> {
        self.inner.read_exact(buf).await.map_err(|_| SessionError::Read)
    }

    pub async fn read_to_end(&mut self, limit: usize) -> Result<Vec<u8>, SessionError> {
        self.inner.read_to_end(limit).await.map_err(|_| SessionError::Read)
    }

    pub fn stop(&mut self, code: u32) {
        let code = quinn::VarInt::try_from(code).unwrap_or(quinn::VarInt::from_u32(0));
        self.inner.stop(code).ok();
    }
}

impl std::fmt::Debug for RecvStream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RecvStream").finish()
    }
}

/// WebTransport-like session over iroh QUIC
/// 
/// This uses the "raw" mode like iroh-live's web-transport-iroh,
/// where we treat the QUIC connection directly as a WebTransport session
/// without HTTP/3 framing.
#[derive(Clone)]
pub struct Session {
    conn: Connection,
    url: Url,
}

impl Session {
    /// Create a new raw session from an iroh connection
    pub fn new(conn: Connection) -> Self {
        let url: Url = format!("iroh://{}", conn.remote_id())
            .parse()
            .expect("valid url");
        Self { conn, url }
    }

    /// Create with explicit URL
    pub fn raw(conn: Connection, url: Url) -> Self {
        Self { conn, url }
    }

    /// Get the remote endpoint ID
    pub fn remote_id(&self) -> EndpointId {
        self.conn.remote_id()
    }

    /// Get the underlying connection
    pub fn conn(&self) -> &Connection {
        &self.conn
    }

    /// Get the session URL
    pub fn url(&self) -> &Url {
        &self.url
    }

    /// Accept a unidirectional stream
    pub async fn accept_uni(&self) -> Result<RecvStream, SessionError> {
        let recv = self.conn.accept_uni().await?;
        Ok(RecvStream::new(recv))
    }

    /// Accept a bidirectional stream
    pub async fn accept_bi(&self) -> Result<(SendStream, RecvStream), SessionError> {
        let (send, recv) = self.conn.accept_bi().await?;
        Ok((SendStream::new(send), RecvStream::new(recv)))
    }

    /// Open a unidirectional stream
    pub async fn open_uni(&self) -> Result<SendStream, SessionError> {
        let send = self.conn.open_uni().await?;
        Ok(SendStream::new(send))
    }

    /// Open a bidirectional stream
    pub async fn open_bi(&self) -> Result<(SendStream, RecvStream), SessionError> {
        let (send, recv) = self.conn.open_bi().await?;
        Ok((SendStream::new(send), RecvStream::new(recv)))
    }

    /// Send a datagram
    pub fn send_datagram(&self, data: Bytes) -> Result<(), SessionError> {
        self.conn.send_datagram(data).map_err(|_| SessionError::Datagram)
    }

    /// Receive a datagram
    pub async fn recv_datagram(&self) -> Result<Bytes, SessionError> {
        self.conn.read_datagram().await.map_err(|_| SessionError::Datagram)
    }

    /// Get maximum datagram size
    pub fn max_datagram_size(&self) -> usize {
        self.conn.max_datagram_size().unwrap_or(1200)
    }

    /// Close the session
    pub fn close(&self, code: u32, reason: &str) {
        let code = quinn::VarInt::try_from(code).unwrap_or(quinn::VarInt::from_u32(0));
        self.conn.close(code, reason.as_bytes());
    }

    /// Wait for session to close
    pub async fn closed(&self) -> SessionError {
        self.conn.closed().await.into()
    }
}

impl std::fmt::Debug for Session {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("remote", &self.remote_id().fmt_short().to_string())
            .field("url", &self.url)
            .finish()
    }
}

// Implement web_transport_trait::Session for compatibility with moq-lite
impl web_transport_trait::Session for Session {
    type SendStream = SendStream;
    type RecvStream = RecvStream;
    type Error = SessionError;

    async fn accept_uni(&self) -> Result<Self::RecvStream, Self::Error> {
        Session::accept_uni(self).await
    }

    async fn accept_bi(&self) -> Result<(Self::SendStream, Self::RecvStream), Self::Error> {
        Session::accept_bi(self).await
    }

    async fn open_bi(&self) -> Result<(Self::SendStream, Self::RecvStream), Self::Error> {
        Session::open_bi(self).await
    }

    async fn open_uni(&self) -> Result<Self::SendStream, Self::Error> {
        Session::open_uni(self).await
    }

    fn close(&self, code: u32, reason: &str) {
        Session::close(self, code, reason);
    }

    async fn closed(&self) -> Result<(), Self::Error> {
        match Session::closed(self).await {
            SessionError::Connection(iroh::endpoint::ConnectionError::LocallyClosed) => Ok(()),
            err => Err(err),
        }
    }

    fn send_datagram(&self, data: Bytes) -> Result<(), Self::Error> {
        Session::send_datagram(self, data)
    }

    async fn recv_datagram(&self) -> Result<Bytes, Self::Error> {
        Session::recv_datagram(self).await
    }

    fn max_datagram_size(&self) -> usize {
        Session::max_datagram_size(self)
    }
}

// Implement SendStream trait
impl web_transport_trait::SendStream for SendStream {
    type Error = SessionError;

    async fn write(&mut self, buf: &[u8]) -> Result<usize, Self::Error> {
        SendStream::write(self, buf).await
    }

    fn set_priority(&mut self, priority: i32) {
        SendStream::set_priority(self, priority);
    }

    fn reset(&mut self, code: u32) {
        SendStream::reset(self, code);
    }

    async fn finish(&mut self) -> Result<(), Self::Error> {
        SendStream::finish(self)
    }

    async fn closed(&mut self) -> Result<(), Self::Error> {
        // Wait for the peer to acknowledge all data
        self.inner.stopped().await.map_err(|_| SessionError::Closed)?;
        Ok(())
    }
}

// Implement RecvStream trait
impl web_transport_trait::RecvStream for RecvStream {
    type Error = SessionError;

    fn stop(&mut self, code: u32) {
        RecvStream::stop(self, code);
    }

    async fn read(&mut self, dst: &mut [u8]) -> Result<Option<usize>, Self::Error> {
        RecvStream::read(self, dst).await
    }

    async fn read_chunk(&mut self, max: usize) -> Result<Option<Bytes>, Self::Error> {
        self.inner
            .read_chunk(max, true)
            .await
            .map(|r| r.map(|chunk| chunk.bytes))
            .map_err(|_| SessionError::Read)
    }

    async fn closed(&mut self) -> Result<(), Self::Error> {
        // Wait for reset or finish
        match self.inner.received_reset().await {
            Ok(_) => Ok(()),
            Err(_) => Err(SessionError::Closed),
        }
    }
}
