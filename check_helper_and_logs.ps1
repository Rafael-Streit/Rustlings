$helper = 'C:\Uprogs\RustRover 2026.2.4\bin\native-helper\intellij-rust-native-helper.exe'
Write-Output "Helper path: $helper"
if (Test-Path $helper) {
    Write-Output 'Helper exists'
    try {
        $zone = Get-Content -Path $helper -Stream Zone.Identifier -ErrorAction Stop
        Write-Output 'Zone.Identifier found:'
        $zone
    } catch {
        Write-Output 'No Zone.Identifier stream'
    }
} else {
    Write-Output 'Helper not found at that path'
}

Write-Output '--- Checking AppLocker/CodeIntegrity logs for helper ---'
$since = (Get-Date).AddDays(-2)
$patterns = @('intellij-rust-native-helper.exe','intellij-rust-native-helper')
$logs = @('Microsoft-Windows-AppLocker/EXE and DLL','Microsoft-Windows-CodeIntegrity/Operational','System','Application')
foreach ($log in $logs) {
    Write-Output "Checking $log"
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName=$log; StartTime=$since} -ErrorAction Stop
        $matched = @()
        foreach ($e in $events) {
            foreach ($p in $patterns) {
                if ($e.Message -match $p) { $matched += $e; break }
            }
        }
        if ($matched.Count -gt 0) {
            $limit = [Math]::Min(20, $matched.Count)
            for ($i=0; $i -lt $limit; $i++) {
                $m = $matched[$i]
                Write-Output ("Time:" + $m.TimeCreated + " Id:" + $m.Id + " Log:" + $m.LogName)
                Write-Output ($m.Message -replace "`r`n", " | ")
            }
        } else {
            Write-Output "No matching events in $log"
        }
    } catch {
        Write-Output ("Cannot read " + $log + ": " + $_.ToString())
    }
}
