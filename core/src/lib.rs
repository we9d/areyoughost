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
//! - **db**: SQLite database operations for persistence
//! - **utils**: Helper functions and utilities
//! - **config**: Configuration management

pub mod api;
pub mod network;
pub mod game_logic;
pub mod models;
pub mod db;
pub mod utils;
pub mod config;

/// Initialize the core engine
///
/// This function should be called once at application startup to
/// initialize the game engine, database, and networking components.
pub fn init() {
    println!("Are You Ghost? Core Engine initialized");
}
