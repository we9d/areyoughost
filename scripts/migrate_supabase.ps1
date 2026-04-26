param(
    [string]$DatabaseUrl = $env:DATABASE_URL
)

function Read-DatabaseUrlFromEnvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    foreach ($raw in Get-Content $Path -ErrorAction SilentlyContinue) {
        $line = $raw.Trim()
        if ($line -match '^\s*#' -or $line -eq '') { continue }
        if ($line -match '^\s*DATABASE_URL\s*=\s*(.+)\s*$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

if (-not $DatabaseUrl) {
    $DatabaseUrl = Read-DatabaseUrlFromEnvFile "server\.env"
}
if (-not $DatabaseUrl) {
    $DatabaseUrl = Read-DatabaseUrlFromEnvFile ".env"
}

if (-not $DatabaseUrl) {
    Write-Error @"
DATABASE_URL is not set.

Either:
  1) Run from repo root:  .\scripts\migrate_supabase.ps1
     (loads DATABASE_URL from server\.env or .env if present)

  2) Or set then migrate:
     `$env:DATABASE_URL = '<your-supabase-url>?sslmode=require'
     sqlx migrate run --source core/migrations
"@
    exit 1
}

Write-Host "Running migrations from core/migrations..."
sqlx migrate run --database-url "$DatabaseUrl" --source "core/migrations"
