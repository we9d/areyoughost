# Setup Script for Are You Ghost
# Run this script after cloning the repository

Write-Host "Are You Ghost - Initial Setup" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check Rust
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    $rustVersion = cargo --version
    Write-Host "[OK] Rust: $rustVersion" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Rust not found. Please install from https://rustup.rs" -ForegroundColor Red
    exit 1
}

# Check Flutter
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterVersion = flutter --version | Select-Object -First 1
    Write-Host "[OK] Flutter: $flutterVersion" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Flutter not found. Please install from https://flutter.dev" -ForegroundColor Red
    exit 1
}

# Check Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVersion = docker --version
    Write-Host "[OK] Docker: $dockerVersion" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] Docker not found. Database won't be available." -ForegroundColor Yellow
}

Write-Host ""

# Setup environment
Write-Host "Setting up environment..." -ForegroundColor Yellow
if (-Not (Test-Path ".env")) {
    Copy-Item ".env.example" -Destination ".env"
    Write-Host "[OK] Created .env file" -ForegroundColor Green
}
else {
    Write-Host "[INFO] .env already exists" -ForegroundColor Cyan
}

# Install Flutter dependencies
Write-Host ""
Write-Host "Installing Flutter dependencies..." -ForegroundColor Yellow
Push-Location frontend
flutter pub get
Pop-Location
Write-Host "[OK] Flutter dependencies installed" -ForegroundColor Green

# Build Rust workspace
Write-Host ""
Write-Host "Building Rust workspace..." -ForegroundColor Yellow
cargo build --workspace
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Rust workspace built successfully" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Rust build failed" -ForegroundColor Red
    exit 1
}

# Start database (if Docker available)
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "Starting PostgreSQL database..." -ForegroundColor Yellow
    docker-compose up -d
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Database started" -ForegroundColor Green
        Write-Host "   PostgreSQL: localhost:5433" -ForegroundColor Cyan
        Write-Host "   PgAdmin: http://localhost:5050" -ForegroundColor Cyan
    }
}

# Summary
Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run the server: cargo run -p areyoughost_server" -ForegroundColor Cyan
Write-Host "  2. Run the app: cd frontend && flutter run -d windows" -ForegroundColor Cyan
Write-Host ""
Write-Host "For more info, see README.md and docs/DEVELOPMENT.md" -ForegroundColor Cyan
