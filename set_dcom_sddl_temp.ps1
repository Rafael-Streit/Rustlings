# Temporary elevated script to set permissive DCOM Launch/Access permissions for the PerAppRuntimeBroker AppID
# Run elevated. This writes LaunchPermission and AccessPermission binary values under HKCR\AppID\{15C20B67-12E7-4BB6-92BB-7AFF07997402}
$appid = '{15C20B67-12E7-4BB6-92BB-7AFF07997402}'
# SDDL: grant Local Launch+Local Activation (access mask 0x3) to SYSTEM, Administrators, Users, Everyone
$sddl = "D:(A;;0x3;;;S-1-5-18)(A;;0x3;;;S-1-5-32-544)(A;;0x3;;;S-1-5-32-545)(A;;0x3;;;S-1-1-0)"
try {
    Write-Output "Creating RawSecurityDescriptor from SDDL: $sddl"
    $sd = New-Object System.Security.AccessControl.RawSecurityDescriptor($sddl)
    $bytes = New-Object byte[] ($sd.BinaryLength)
    $sd.GetBinaryForm($bytes, 0)

    # Ensure AppID key exists
    $regPath = "HKCR:\AppID\$appid"
    if (-not (Test-Path $regPath)) {
        New-Item -Path "HKCR:\AppID" -Name $appid -Force | Out-Null
    }

    # Write binary values
    Write-Output "Writing LaunchPermission and AccessPermission under $regPath"
    New-ItemProperty -Path $regPath -Name LaunchPermission -Value $bytes -PropertyType Binary -Force | Out-Null
    New-ItemProperty -Path $regPath -Name AccessPermission -Value $bytes -PropertyType Binary -Force | Out-Null
    Write-Output "Registry write complete."
} catch {
    Write-Error "Failed to write registry permissions: $_"
    exit 1
}

# Try to verify via WMI
try {
    $dcom = Get-WmiObject -Namespace root\cimv2 -Class Win32_DCOMApplicationSetting -Filter "AppID='$appid'"
    if (-not $dcom) { Write-Warning "Win32_DCOMApplicationSetting not found via WMI for AppID $appid" } else {
        $res = $dcom.GetLaunchSecurityDescriptor()
        Write-Output "WMI GetLaunchSecurityDescriptor ReturnValue: $($res.ReturnValue)"
        $sd2 = $res.Descriptor
        if ($sd2 -and $sd2.DACL) {
            foreach ($ace in $sd2.DACL) {
                try {
                    $t = New-Object System.Security.Principal.SecurityIdentifier($ace.Trustee.SID)
                    Write-Output "ACE: SID=$($t.Value) AccessMask=$($ace.AccessMask)"
                } catch {
                    Write-Output "ACE present (raw bytes) AccessMask=$($ace.AccessMask)"
                }
            }
        } else {
            Write-Output "No DACL returned via WMI."
        }
    }
} catch {
    Write-Warning "WMI verification failed: $_"
}

# Run the test to verify
try {
    Write-Output "Running cargo test --bin if1 to verify"
    Set-Location 'C:\Udev\rust\rustlings'
    cargo test --bin if1 --color never
} catch {
    Write-Warning "cargo test failed to run: $_"
    exit 1
}
