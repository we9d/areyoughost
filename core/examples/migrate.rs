use sqlx::postgres::PgPoolOptions;
use std::error::Error;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let database_url = "postgres://postgres:password@localhost/areyoughost";

    println!("Connecting to {}", database_url);

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await?;

    println!("Connection successful. Running migrations...");

    sqlx::migrate!("./migrations").run(&pool).await?;

    println!("Migrations executed successfully!");

    Ok(())
}
