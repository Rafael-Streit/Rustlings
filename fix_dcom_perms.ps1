# Backup existing LaunchPermission and open Component Services for manual edit
# Run this script as Administrator.
param(
    [string]$AppID = '{15C20B67-12E7-4BB6-92BB-7AFF07997402}',
    [string]$WorkingDir = 'C:\Udev\rust\rustlings',
    [string]$BinName = 'if1'
)
$regPath = "HKCR:\AppID\$AppID"
if (-not (Test-Path $regPath)) {
    Write-Error "Registry path $regPath not found. Aborting."
    exit 1
}
# Backup LaunchPermission value if present
try {
    $lp = (Get-ItemProperty -Path $regPath -Name LaunchPermission -ErrorAction Stop).LaunchPermission
    $backup = Join-Path -Path $env:TEMP -ChildPath ("LaunchPermission_$($AppID.Trim('{}')).bin")
    [IO.File]::WriteAllBytes($backup, $lp)
    Write-Output "Backup of LaunchPermission written to: $backup"
} catch {
    Write-Warning "No LaunchPermission value found or could not read it. Proceeding without backup."
}
Write-Output "Opening Component Services (dcomcnfg). Please grant Local Launch and Local Activation to the user you want (e.g. NVG_Standalone\\NVG) for the application named PerAppRuntimeBroker or matching APPID."
Start-Process -FilePath dcomcnfg -Verb runAs
Write-Output "When finished granting permissions in Component Services, come back to this console and press ENTER to run the tests as Administrator."
Read-Host -Prompt 'Press ENTER after you applied the permissions (or Ctrl+C to cancel)'
# Run tests elevated
$psCmd = "cd '$WorkingDir'; cargo test --bin $BinName --color never"
Write-Output "Starting elevated test run..."
Start-Process -FilePath powershell -ArgumentList ('-NoProfile','-Command', $psCmd) -Verb runAs -Wait
Write-Output "Elevated test run finished. Check the elevated window or this console for results."