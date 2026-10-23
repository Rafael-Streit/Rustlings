<#
PowerShell script to set DCOM Launch permissions for an AppID via WMI.
WARNING: This modifies DCOM launch security. Run only as Administrator.
Usage (as Admin):
  .\apply_dcom_launch_permission.ps1 -AppID '{15C20B67-12E7-4BB6-92BB-7AFF07997402}' -Account 'NVG_Standalone\\NVG'
#>
param(
    [string]$AppID = '{15C20B67-12E7-4BB6-92BB-7AFF07997402}',
    [string]$Account = 'NVG_Standalone\\NVG',
    [int]$AccessMask = 3  # 1 = Local Launch, 2 = Local Activation, 3 = both
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

Write-Output "AppID: $AppID"
Write-Output "Account: $Account"

$sidBytes = Get-SidBytes -acct $Account
if (-not $sidBytes) { exit 1 }

# Create WMI embedded instances
$trusteeClass = [WMIClass]"\\.\root\cimv2:Win32_Trustee"
$aceClass = [WMIClass]"\\.\root\cimv2:Win32_ACE"
$sdClass = [WMIClass]"\\.\root\cimv2:Win32_SecurityDescriptor"

$trustee = $trusteeClass.CreateInstance()
$trustee.SID = $sidBytes

$ace = $aceClass.CreateInstance()
$ace.AccessMask = $AccessMask
$ace.AceFlags = 0
$ace.AceType = 0  # ACCESS_ALLOWED_ACE_TYPE
$ace.Trustee = $trustee

$sd = $sdClass.CreateInstance()
$sd.ControlFlags = 4  # SE_DACL_PRESENT
$sd.DACL = @($ace)

# Locate the DCOM application by AppID
$dcom = Get-WmiObject -Namespace root\cimv2 -Class Win32_DCOMApplicationSetting -Filter "AppID='$AppID'"
if (-not $dcom) {
    Write-Error "DCOM application with AppID $AppID not found."
    exit 1
}

Write-Output "Setting Launch security descriptor (Local Launch/Activation) for AppID $AppID..."
$result = $dcom.SetLaunchSecurityDescriptor($sd)

if ($result.ReturnValue -eq 0) {
    Write-Output "Success: Launch security descriptor updated."
} else {
    Write-Error "Failed to set Launch security descriptor. ReturnValue=$($result.ReturnValue)"
}
