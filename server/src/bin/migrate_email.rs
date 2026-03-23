use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() {
    dotenvy::from_filename("server/.env").ok();
    dotenvy::from_filename(".env").ok();
    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");

    let db = PgPoolOptions::new()
        .connect(&database_url)
        .await
        .expect("Failed to connect to database");

    println!("Adding email column to players table...");
    
    match sqlx::query("ALTER TABLE players ADD COLUMN email VARCHAR(255) UNIQUE")
        .execute(&db)
        .await {
        Ok(_) => println!("Migration successful!"),
        Err(e) => println!("Migration failed (it might already exist): {}", e),
    }
}
