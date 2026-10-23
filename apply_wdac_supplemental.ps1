<#
apply_wdac_supplemental.ps1
Creates and installs a supplemental WDAC (Code Integrity) policy that allows the specified helper and project folders.
WARNING: Very risky. Requires Administrator and may require a reboot. May be blocked by enterprise GPO/MDM.
Run elevated.
#>
param(
    [string[]]$ScanPaths = @('C:\Uprogs\RustRover 2026.2.4\bin\native-helper\intellij-rust-native-helper.exe', 'C:\Udev\rust\rustlings\target\debug\deps'),
    [switch]$RebootAfter = $true
)
function ErrExit($msg) { Write-Error $msg; exit 1 }
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { ErrExit 'This script must be run as Administrator.' }
# Check for required cmdlets
if (-not (Get-Command New-CIPolicy -ErrorAction SilentlyContinue)) { ErrExit 'New-CIPolicy not available. ConfigCI module not present on this system.' }
if (-not (Get-Command ConvertFrom-CIPolicy -ErrorAction SilentlyContinue)) { ErrExit 'ConvertFrom-CIPolicy not available.' }

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$work = Join-Path $env:TEMP ("wdac_policy_$timestamp")
New-Item -Path $work -ItemType Directory -Force | Out-Null
$xml = Join-Path $work 'policy.xml'
bin = Join-Path $work 'policy.cip'

Write-Output "Scan paths: $($ScanPaths -join ', ')"
Write-Output "Working dir: $work"
try {
    Write-Output 'Generating XML policy with New-CIPolicy (FileHash rules) ...'
    New-CIPolicy -ScanPath $ScanPaths -FilePath $xml -Level FileHash -UserPEs -ErrorAction Stop
} catch {
    ErrExit "New-CIPolicy failed: $_"
}

try {
    Write-Output 'Converting XML to binary CIP policy...'
    ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $bin -ErrorAction Stop
} catch {
    ErrExit "ConvertFrom-CIPolicy failed: $_"
}

$destDir = 'C:\Windows\System32\CodeIntegrity\CiPolicies\Active'
if (-not (Test-Path $destDir)) { $destDir = 'C:\Windows\System32\CodeIntegrity\CiPolicies' }
if (-not (Test-Path $destDir)) { ErrExit "CodeIntegrity policy folder not found: $destDir" }

# Backup existing policies
$backupDir = Join-Path $env:TEMP ("ci_policies_backup_$timestamp")
New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
Get-ChildItem -Path $destDir -Filter '*.cip' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item -Path $_.FullName -Destination $backupDir -Force }
Write-Output "Existing policies backed up to $backupDir"

# Copy new policy as supplemental (name starts with Supplemental)
$dest = Join-Path $destDir ("Supplemental_$timestamp.cip")
try {
    Copy-Item -Path $bin -Destination $dest -Force
    Write-Output "Copied policy to $dest"
} catch {
    ErrExit "Failed to copy policy into $destDir: $_"
}

Write-Output 'Policy installed. Note: WDAC loads policies at boot; a reboot is recommended to activate the new supplemental policy.'
if ($RebootAfter) {
    Write-Output 'Rebooting in 10 seconds... (Press CTRL+C to cancel)'
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
