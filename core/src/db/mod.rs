//! # Database Module
//!
//! This module provides database abstraction and SQLite implementation
//! for persisting game data including users, rooms, and game history.
//!
//! The `Database` trait allows for potential future support of other
//! database backends while the current implementation uses SQLite.

use rusqlite::Result;

pub mod sqlite;

/// Database trait for abstracting database operations
///
/// Implementations must provide initialization and migration capabilities.
pub trait Database {
    /// Initialize the database schema
    fn init(&self) -> Result<()>;
    
    /// Run database migrations
    fn migrate(&self) -> Result<()>;
}
