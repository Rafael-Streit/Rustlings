<#
remove_restrictions_for_rust.ps1

Dieses Skript setzt die DCOM "Launch and Activation"-Berechtigungen für eine gegebene AppID so, dass die angegebenen Konten Local Launch + Local Activation erhalten.
ACHTUNG: Macht sicherheitsrelevante Änderungen. Nur ausführen wenn du Administrator bist und die Konsequenzen kennst.

Usage (als Administrator):
  powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Udev\rust\rustlings\remove_restrictions_for_rust.ps1"

Parameter:
  -AppID    AppID der DCOM-Anwendung (Default: PerAppRuntimeBroker APPID)
  -Accounts Array von Konten, denen Launch+Activation gewährt wird (Default: NVG_Standalone\NVG, BUILTIN\Users, BUILTIN\Administrators, NT AUTHORITY\SYSTEM)
  -CreateStartupTask  Wenn gesetzt, wird eine geplante Aufgabe erstellt, die das Skript bei Systemstart erneut ausführt (erfordert Admin-Rechte)
  -ReapplyOnly  Wenn gesetzt, wird nur die Berechtigung angewendet und keine Aufgabe erstellt
#>
param(
    [string]$AppID = '{15C20B67-12E7-4BB6-92BB-7AFF07997402}',
    [string[]]$Accounts = @('NVG_Standalone\\NVG','BUILTIN\\Users','BUILTIN\\Administrators','NT AUTHORITY\\SYSTEM'),
    [switch]$CreateStartupTask = $true,
    [switch]$ReapplyOnly = $false
)

function Get-SidBytes([string]$acct) {
    try {
        $nt = New-Object System.Security.Principal.NTAccount($acct)
        $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier])
        $bytes = New-Object byte[] ($sid.BinaryLength)
        $sid.GetBinaryForm($bytes,0)
        return $bytes
    } catch {
        Write-Error "Could not resolve account '$acct' to a SID: $_"
        return $null
    }
}

# Backup existing LaunchPermission (if present)
$regPath = "HKCR:\AppID\$AppID"
try {
    if (Test-Path $regPath) {
        $lp = (Get-ItemProperty -Path $regPath -Name LaunchPermission -ErrorAction SilentlyContinue).LaunchPermission
        if ($lp) {
            $backup = Join-Path $env:TEMP ("LaunchPermission_$($AppID.Trim('{}')).bin")
            [IO.File]::WriteAllBytes($backup, $lp)
            Write-Output "Backup of LaunchPermission written to: $backup"
        } else {
            Write-Output "No LaunchPermission value found to backup."
        }
    } else {
        Write-Warning "Registry path $regPath not found. The AppID may not exist under HKCR\\AppID."
    }
} catch {
    Write-Warning "Could not backup LaunchPermission: $_"
}

# Build ACEs for each account
$aceClass = [WMIClass]"\\.\root\cimv2:Win32_ACE"
$trusteeClass = [WMIClass]"\\.\root\cimv2:Win32_Trustee"
$sdClass = [WMIClass]"\\.\root\cimv2:Win32_SecurityDescriptor"

$aces = @()
foreach ($acct in $Accounts) {
    $sidBytes = Get-SidBytes -acct $acct
    if (-not $sidBytes) { continue }
    $trustee = $trusteeClass.CreateInstance()
    $trustee.SID = $sidBytes

    $ace = $aceClass.CreateInstance()
    $ace.AccessMask = 3   # 1 = Local Launch, 2 = Local Activation => 3 = both
    $ace.AceFlags = 0
    $ace.AceType = 0      # ACCESS_ALLOWED_ACE_TYPE
    $ace.Trustee = $trustee
    $aces += $ace
    Write-Output "Prepared ACE for $acct"
}

if ($aces.Count -eq 0) {
    Write-Error "Keine gültigen ACEs erstellt. Abbruch."
    exit 1
}

$sd = $sdClass.CreateInstance()
$sd.ControlFlags = 4   # SE_DACL_PRESENT
$sd.DACL = $aces

# Locate and apply via WMI
try {
    $dcom = Get-WmiObject -Namespace root\cimv2 -Class Win32_DCOMApplicationSetting -Filter "AppID='$AppID'" -ErrorAction Stop
} catch {
    Write-Error "DCOM application with AppID $AppID not found via WMI: $_"
    exit 1
}

Write-Output "Applying Launch security descriptor for AppID $AppID..."
$result = $dcom.SetLaunchSecurityDescriptor($sd)
if ($result.ReturnValue -eq 0) {
    Write-Output "Success: Launch security descriptor updated."
} else {
    Write-Error "Failed to set Launch security descriptor. ReturnValue=$($result.ReturnValue)"
}

# Optionally create a scheduled task to reapply at startup (if requested and not in reapply-only mode)
if ($CreateStartupTask -and -not $ReapplyOnly) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    $taskName = 'Reapply-DCOM-Perms-Rust'
    $schtaskCmd = "schtasks /Create /SC ONSTART /TN \"$taskName\" /TR \"powershell -NoProfile -ExecutionPolicy Bypass -File '$scriptPath' -AppID '$AppID' -ReapplyOnly\" /RL HIGHEST /RU SYSTEM /F"
    try {
        Write-Output "Creating scheduled task to reapply permissions at startup (requires Admin)..."
        $p = Start-Process -FilePath schtasks -ArgumentList "/Create","/SC","ONSTART","/TN",$taskName,"/TR","powershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -AppID `"$AppID`" -ReapplyOnly","/RL","HIGHEST","/RU","SYSTEM","/F" -NoNewWindow -Wait -PassThru -ErrorAction Stop
        Write-Output "Scheduled task created: $taskName"
    } catch {
        Write-Warning "Could not create scheduled task automatically: $_"
        Write-Output "Du kannst die Aufgabe manuell erstellen mit (als Admin):`n$schtaskCmd"
    }
}

Write-Output "Fertig. Prüfe mit: cargo test --bin if1"