pub mod simple;
mod streaming;  // Private - gossip-based (not exposed to FRB)
pub mod flutter_api;

// Direct connection streaming (alternative to gossip)
mod direct_streaming;  // Private - core implementation
pub mod direct_flutter_api;  // Public - Flutter API

// Live streaming (iroh-live inspired features)
mod live_streaming;  // Private - core implementation
pub mod live_flutter_api;  // Public - Flutter API with catalog, quality, stats

// MoQ (Media over QUIC) protocol features
pub mod moq_protocol;  // Track hierarchy, subscriptions, priorities, namespaces
pub mod moq_flutter_api;  // Flutter API for MoQ features
