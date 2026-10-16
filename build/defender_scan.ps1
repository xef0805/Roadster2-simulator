param(
    [Parameter(Mandatory=$true)][string[]]$Files,
    [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference = 'Stop'
$result = [ordered]@{
    scanner = 'Microsoft Defender Antivirus'
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    status = 'unavailable'
    explanation = 'A scan result is not a guarantee of safety.'
    files = @()
}
try {
    $status = Get-MpComputerStatus
    $result.signature_version = $status.AntivirusSignatureVersion
    $result.signature_updated_utc = $status.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o')
    if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) { throw 'Defender is not enabled on this runner.' }
    $platform = Get-ChildItem -LiteralPath "$env:ProgramData\Microsoft\Windows Defender\Platform" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $scanner = Join-Path $platform.FullName 'MpCmdRun.exe'
    if (-not (Test-Path -LiteralPath $scanner)) { $scanner = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" }
} catch {
    $result.reason = $_.Exception.Message
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Report -Encoding utf8
    Write-Host "Defender scan unavailable: $($result.reason)"
    exit 0
}
$result.status = 'passed'
foreach ($file in $Files) {
    $target = (Resolve-Path -LiteralPath $file).Path
    $log = & $scanner -Scan -ScanType 3 -File $target -DisableRemediation 2>&1 | Out-String
    $code = $LASTEXITCODE
    $entry = [ordered]@{
        name = (Split-Path -Leaf $target)
        sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        exit_code = $code
        output = $log.Replace($target, (Split-Path -Leaf $target))
    }
    $result.files += $entry
    if ($code -ne 0) { $result.status = 'failed' }
    Write-Host "$($entry.name): scan exit $code"
}
$result.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Report -Encoding utf8
if ($result.status -ne 'passed') { throw 'Defender detected a threat or could not finish scanning. Read the raw report.' }
