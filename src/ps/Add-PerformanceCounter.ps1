<#
.SYNOPSIS
Add-PerformanceCounter.

.DESCRIPTION
Adds performance counter to a Power BI streaming dataset.

.PARAMETER DatasetId
Id of the Power BI streaming dataset.

.PARAMETER TableName
Table name within the Power BI streaming dataset.

.PARAMETER Token
Bearer token for authentication.

.EXAMPLE
Add-PerformanceCounter.ps1 -DatasetId ********-****-****-****-************ -TableName RealtimeData -Token ********************

.NOTES
Run the following commands to generate an access token
az login
az account get-access-token --resource https://analysis.windows.net/powerbi/api
#>

# script parameters
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$DatasetId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String[]]$TableName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String[]]$Token
)

$endpoint = "https://api.powerbi.com/v1.0/myorg/datasets/${DatasetId}/tables/${TableName}/rows"

$headers = @{
    Authorization = "Bearer $Token"
    ContentType   = "application/json"
}

$computerName = $env:COMPUTERNAME
$processorName = (Get-WmiObject Win32_Processor).Name
$diskName = (Get-Disk).FriendlyName
$diskTotalSizeBytes = (Get-Disk).Size
$ethernetName = Get-NetAdapter | Where-Object { $_.Name -eq 'Ethernet' } | Select-Object -ExpandProperty InterfaceDescription
$wlanName = Get-NetAdapter | Where-Object { $_.Name -eq 'WLAN' } | Select-Object -ExpandProperty InterfaceDescription

$performanceCounter = @(
    '\Processor Information(*)\% Processor Time',
    '\Processor Information(*)\% of Maximum Frequency',
    '\Thermal Zone Information(*)\Temperature',
    '\Memory\Available Bytes',
    '\Memory\Committed Bytes',
    '\Memory\% Committed Bytes In Use',
    '\Network Interface(*)\Bytes Received/sec',
    '\Network Interface(*)\Bytes Sent/sec',
    '\LogicalDisk(*)\Free Megabytes',
    '\LogicalDisk(*)\% Free Space',
    '\LogicalDisk(*)\Disk Read Bytes/sec',
    '\LogicalDisk(*)\Disk Write Bytes/sec',
    '\Process(*)\% Processor Time'
)

[System.Collections.Hashtable]$payload = @{}

while ($true) {
    $performanceCounterValues = Get-Counter -Counter $performanceCounter -SampleInterval 2

    $timestampUTC = ($performanceCounterValues.Timestamp).ToUniversalTime()
    $timestampString = $timestampUTC.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')  # use this format to refresh the dashboard constantly
    $id = $timestampUTC.ToFileTimeUtc()

    $payload.Clear()
    $payload.Add('Id', $id)
    $payload.Add('Timestamp', $timestampString)
    $payload.Add('Server', $computerName)
    $payload.Add('Processor', $processorName)
    $payload.Add('Disk', $diskName)
    $payload.Add('Disk total size bytes', $diskTotalSizeBytes)
    $payload.Add('Ethernet', $ethernetName)
    $payload.Add('WLAN', $wlanName)

    $counterSamples = $performanceCounterValues | Select-Object -ExpandProperty CounterSamples
    $numberOfProcesses = -1 # ignore _total
    foreach ($counterSample in $counterSamples) {
        $value = $counterSample.CookedValue
        if (!$value) {
            $value = 0
        }
        
        if ($counterSample.Path -eq "\\$($computerName.ToLower())\processor information(0,_total)\% processor time") {
            $payload.Add('CPU usage percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\processor information(0,0)\% processor time") {
            $payload.Add('CPU 0 usage percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\processor information(0,1)\% processor time") {
            $payload.Add('CPU 1 usage percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\processor information(0,2)\% processor time") {
            $payload.Add('CPU 2 usage percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\processor information(0,3)\% processor time") {
            $payload.Add('CPU 3 usage percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\processor information(0,_total)\% of maximum frequency") {
            $payload.Add('CPU max frequency percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\thermal zone information(\_tz.thm0)\temperature") {
            $payload.Add('Temperature', [Math]::Round($($value - 273.15), 2)) # Kelvin to Celsius
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\memory\available bytes") {
            $payload.Add('Memory available bytes', $value)
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\memory\committed bytes") {
            $payload.Add('Memory used bytes', $value)
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\memory\% committed bytes in use") {
            $payload.Add('Memory used percent', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\network interface(intel[r] ethernet connection [5] i219-lm)\bytes received/sec") {
            $payload.Add('Ethernet bytes received/sec', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\network interface(intel[r] ethernet connection [5] i219-lm)\bytes sent/sec") {
            $payload.Add('Ethernet bytes sent/sec', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\network interface(intel[r] dual band wireless-ac 8265)\bytes received/sec") {
            $payload.Add('WLAN bytes received/sec', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\network interface(intel[r] dual band wireless-ac 8265)\bytes sent/sec") {
            $payload.Add('WLAN bytes sent/sec', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\logicaldisk(c:)\free megabytes") {
            $payload.Add('Disk free bytes', $value * 1024 * 1024)
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\\logicaldisk(c:)\% free space") {
            $payload.Add('Disk free space percent', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\logicaldisk(c:)\disk read bytes/sec") {
            $payload.Add('Disk read bytes/sec', [Math]::Round($value, 0))
        }
        elseif ($counterSample.Path -eq "\\$($computerName)\logicaldisk(c:)\disk write bytes/sec") {
            $payload.Add('Disk write bytes/sec', [Math]::Round($value, 2))
        }
        elseif ($counterSample.Path -like "*process(*)\% processor time*") {
            $numberOfProcesses++
        }
        # else { Write-Host $counterSample.Path }
    }

    $payload.Add('Processes', $numberOfProcesses)

    Write-Host "$(ConvertTo-Json @($payload))"
    
    $null = Invoke-RestMethod -Method Post -Uri "$endpoint" -Headers $headers -Body (ConvertTo-Json @($payload)) -TimeoutSec 10
}
