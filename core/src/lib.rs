pub mod api;
pub mod db;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod game_logic;
pub mod models;
pub mod network;
pub mod utils;

/// Initialize the core engine
pub fn init() {
    println!("Are You Ghost? Core Engine initialized (Server Mode)");
    // No local DB init needed anymore
}
