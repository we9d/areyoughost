param(
    [Parameter(Mandatory = $false)]
    [switch]$WithPlayer2,
    [Parameter(Mandatory = $false)]
    [switch]$WithPlayer3,
    [Parameter(Mandatory = $false)]
    [string]$NgrokHost
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$player1Script = Join-Path $PSScriptRoot "start_player1.ps1"
$player2Script = Join-Path $PSScriptRoot "start_player2.ps1"
$player3Script = Join-Path $PSScriptRoot "start_player3.ps1"

if (-not (Test-Path $player1Script)) {
    throw "Missing script: $player1Script"
}

if ($WithPlayer2 -and -not (Test-Path $player2Script)) {
    throw "Missing script: $player2Script"
}

if ($WithPlayer3 -and -not (Test-Path $player3Script)) {
    throw "Missing script: $player3Script"
}

$serverCmd = "Set-Location -LiteralPath `"$repoRoot`"; cargo run -p areyoughost_server"
$playerArgs = @("-NoExit", "-ExecutionPolicy", "Bypass")

Write-Host "Starting backend server window..."
Start-Process powershell -ArgumentList "-NoExit", "-Command", $serverCmd | Out-Null

Start-Sleep -Seconds 2

Write-Host "Starting player1 window..."
$p1Args = $playerArgs + @("-File", $player1Script)
if ($NgrokHost) {
    $p1Args += @("-NgrokHost", $NgrokHost)
}
Start-Process powershell -WorkingDirectory $repoRoot -ArgumentList $p1Args | Out-Null

if ($WithPlayer2) {
    Start-Sleep -Seconds 2
    Write-Host "Starting player2 window..."
    $p2Args = $playerArgs + @("-File", $player2Script)
    if ($NgrokHost) {
        $p2Args += @("-NgrokHost", $NgrokHost)
    }
    Start-Process powershell -WorkingDirectory $repoRoot -ArgumentList $p2Args | Out-Null
}

if ($WithPlayer3) {
    Start-Sleep -Seconds 2
    Write-Host "Starting player3 window..."
    $p3Args = $playerArgs + @("-File", $player3Script)
    if ($NgrokHost) {
        $p3Args += @("-NgrokHost", $NgrokHost)
    }
    Start-Process powershell -WorkingDirectory $repoRoot -ArgumentList $p3Args | Out-Null
}

Write-Host "Done. Use -WithPlayer2 and -WithPlayer3 to launch more clients."
if ($NgrokHost) {
    Write-Host "Using Ngrok host: $NgrokHost"
}

