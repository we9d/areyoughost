#[tokio::main]
async fn main() {
    println!("This binary is deprecated.");
    println!("Use SQL migrations under core/migrations instead:");
    println!("  cargo run --example migrate");
}
