//! # Are You Ghost? - Core Engine
//!
//! This is the Rust backend core for the "Are You Ghost?" game.
//! It provides the game logic, networking, database operations, and FFI exports
//! for integration with the Flutter frontend.
//!
//! ## Architecture
//!
//! - **api**: FFI exports to Flutter via flutter_rust_bridge
//! - **network**: TCP socket handling for multiplayer communication
//! - **game_logic**: Game state machine and rule enforcement
//! - **models**: Data structures shared across the application
// pub mod db; // Removed SQLite
pub mod utils;
pub mod config;

/// Initialize the core engine
pub fn init() {
    println!("Are You Ghost? Core Engine initialized (Server Mode)");
    // No local DB init needed anymore
}
