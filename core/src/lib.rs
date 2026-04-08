pub mod api;
pub mod db;
mod frb_generated;
pub mod game_logic;
pub mod models;
pub mod network;
pub mod utils;

#[cfg(test)]
mod tests;

// Re-export popular traits for workspace consistency
pub use serde::{Deserialize, Serialize};

/// Initialize the core engine
pub fn init() {
    println!("Are You Ghost? Core Engine initialized (Server Mode)");
}
