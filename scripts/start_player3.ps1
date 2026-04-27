param(
    [Parameter(Mandatory = $false)]
    [string]$NgrokHost
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$frontendDir = Join-Path $repoRoot "frontend"
$envFile = Join-Path $repoRoot ".env"

if (-not (Test-Path $frontendDir)) {
    throw "Frontend directory not found: $frontendDir"
}

if ((-not $NgrokHost) -and (Test-Path $envFile)) {
    $envLines = Get-Content $envFile
    foreach ($line in $envLines) {
        if ($line -match '^\s*#' -or $line.Trim().Length -eq 0) { continue }
        $parts = $line -split '=', 2
        if ($parts.Length -ne 2) { continue }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key -eq 'NGROK_HOST' -and $value) { $NgrokHost = $value }
        if ($key -eq 'API_BASE_URL' -and $value) { $env:API_BASE_URL = $value }
        if ($key -eq 'WS_URL' -and $value) { $env:WS_URL = $value }
    }
}

if (-not $NgrokHost -and -not $env:API_BASE_URL) {
    throw "Missing Ngrok host. Provide -NgrokHost or set NGROK_HOST/API_BASE_URL in .env"
}

$apiBaseUrl = if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "https://$NgrokHost" }
$wsUrl = if ($env:WS_URL) { $env:WS_URL } else { "wss://$NgrokHost/ws" }

Write-Host "Starting Player 3 with:"
Write-Host "API_BASE_URL=$apiBaseUrl"
Write-Host "WS_URL=$wsUrl"
Write-Host "SESSION_NAMESPACE=player3"

Set-Location $frontendDir
$env:API_BASE_URL = $apiBaseUrl
$env:WS_URL = $wsUrl
$env:SESSION_NAMESPACE = "player3"

$exePath = Join-Path $frontendDir "build\windows\x64\runner\Debug\areyoughost.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "Debug executable not found, building once..."
    flutter build windows --debug
    if ($LASTEXITCODE -ne 0) {
        throw "Build process failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $exePath)) {
    throw "Executable not found after build: $exePath"
}

Write-Host "Launching executable: $exePath"
$exeDir = Split-Path -Parent $exePath
Push-Location $exeDir
try {
    & $exePath
} finally {
    Pop-Location
}
