use sqlx::PgPool;
use std::env;

#[tokio::main]
async fn main() -> Result<(), sqlx::Error> {
    dotenvy::dotenv().ok();
    let db_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let pool = PgPool::connect(&db_url).await?;

    println!("Checking table 'skills'...");
    let rows = sqlx::query(
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'skills'"
    )
    .fetch_all(&pool)
    .await?;

    for row in rows {
        let name: String = sqlx::Row::get(&row, "column_name");
        let dtype: String = sqlx::Row::get(&row, "data_type");
        println!("Column: {} - Type: {}", name, dtype);
    }

    println!("\nChecking table 'roles'...");
    let rows = sqlx::query(
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'roles'"
    )
    .fetch_all(&pool)
    .await?;

    for row in rows {
        let name: String = sqlx::Row::get(&row, "column_name");
        let dtype: String = sqlx::Row::get(&row, "data_type");
        println!("Column: {} - Type: {}", name, dtype);
    }

    Ok(())
}
