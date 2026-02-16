# Run All Tests
# Runs tests for all workspace members

Write-Host "Running all tests..." -ForegroundColor Cyan
Write-Host ""

# Run workspace tests
Write-Host "Testing workspace..." -ForegroundColor Yellow
cargo test --workspace -- --nocapture

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[OK] All tests passed!" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "[ERROR] Some tests failed" -ForegroundColor Red
    exit 1
}
