# BTC Vault — Base mainnet fork test (simulation only, no real money moves)
# Run from PowerShell:  powershell -ExecutionPolicy Bypass -File "$HOME\Documents\run-fork-test.ps1"
# Output is saved to Documents\fork-test-log.txt so Claude can read it.

$ErrorActionPreference = "Continue"
$root  = Join-Path $HOME "Documents\btc-vault-forktest"
$zip   = Join-Path $HOME "Documents\vault-forktest.zip"
$tools = Join-Path $root "foundry"
$forge = Join-Path $tools "forge.exe"
$log   = Join-Path $HOME "Documents\fork-test-log.txt"
"BTC Vault fork test  $(Get-Date -Format s)" | Out-File $log -Encoding utf8

if (-not (Test-Path (Join-Path $root "btc-vault"))) {
    Write-Host "Unpacking project..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $root -Force
}
if (-not (Test-Path $forge)) {
    Write-Host "Downloading Foundry..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $tools -Force | Out-Null
    $fz = Join-Path $tools "foundry.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/foundry-rs/foundry/releases/download/stable/foundry_stable_win32_amd64.zip" -OutFile $fz
    Expand-Archive -Path $fz -DestinationPath $tools -Force
}
Set-Location (Join-Path $root "btc-vault")

Write-Host "Unit tests..." -ForegroundColor Cyan
$unit = & $forge test 2>&1 | Out-String
$unit | Out-File $log -Append -Encoding utf8
if ($unit -match "(\d+) tests passed, (\d+) failed") { Write-Host "   $($Matches[0])" }

# Free public Base RPCs. Requests are throttled and retried so they don't get blocked.
$rpcs = @(
  "https://base-rpc.publicnode.com",
  "https://base.drpc.org",
  "https://1rpc.io/base",
  "https://base.gateway.tenderly.co",
  "https://mainnet.base.org"
)
$passed = $false
foreach ($rpc in $rpcs) {
    Write-Host "Fork test via $rpc ..." -ForegroundColor Cyan
    $env:BASE_RPC = $rpc
    $out = & $forge test --match-contract BaseFork -vv --fork-url $rpc --fork-retries 8 --fork-retry-backoff 3000 --compute-units-per-second 25 2>&1 | Out-String
    # keep the log readable: drop any HTML error pages a server sends back
    $clean = ($out -split "`n" | Where-Object { $_ -notmatch "^\s*<" }) -join "`n"
    "`n===== $rpc =====`n$clean" | Out-File $log -Append -Encoding utf8
    if ($out -match "\[PASS\] test_BaseForkAaveCompoundRoundTrip") { $passed = $true; break }
    Write-Host "   didn't work with that server, trying the next one..." -ForegroundColor Yellow
}

if ($passed) {
    "RESULT: PASSED" | Out-File $log -Append -Encoding utf8
    Write-Host "`nFORK TEST PASSED. Tell Claude 'done'." -ForegroundColor Green
} else {
    "RESULT: FAILED" | Out-File $log -Append -Encoding utf8
    Write-Host "`nFork test didn't pass. Tell Claude 'done' and it will read the log." -ForegroundColor Red
}
