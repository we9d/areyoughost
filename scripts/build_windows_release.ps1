param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,
    [string]$WsUrl = "",
    [string]$OutputDir = "release"
)

if ([string]::IsNullOrWhiteSpace($WsUrl)) {
    if ($ApiBaseUrl.StartsWith("https://")) {
        $WsUrl = ($ApiBaseUrl -replace "^https://", "wss://") + "/ws"
    }
    elseif ($ApiBaseUrl.StartsWith("http://")) {
        $WsUrl = ($ApiBaseUrl -replace "^http://", "ws://") + "/ws"
    }
    else {
        throw "ApiBaseUrl must start with http:// or https://"
    }
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$frontend = Join-Path $root "frontend"
$releaseRoot = Join-Path $root $OutputDir
$releaseDir = Join-Path $releaseRoot "areyoughost-windows"

Write-Host "Building Windows release..."
Push-Location $frontend
flutter build windows --release --dart-define=API_BASE_URL="$ApiBaseUrl" --dart-define=WS_URL="$WsUrl"
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "flutter build windows failed"
}
Pop-Location

if (Test-Path $releaseDir) {
    Remove-Item -Recurse -Force $releaseDir
}
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$builtRelease = Join-Path $frontend "build\windows\x64\runner\Release\*"
Copy-Item -Recurse -Force $builtRelease $releaseDir

$configPath = Join-Path $releaseDir "app_config.json"
@"
{
  "apiBaseUrl": "$ApiBaseUrl",
  "wsUrl": "$WsUrl"
}
"@ | Out-File -FilePath $configPath -Encoding utf8

Write-Host ""
Write-Host "Done. Share this folder with friends:"
Write-Host "  $releaseDir"
Write-Host ""
Write-Host "Friends only need to open areyoughost.exe"
