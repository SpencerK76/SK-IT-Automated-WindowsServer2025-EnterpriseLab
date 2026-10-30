<#
.SYNOPSIS
    Script run on the host machine to detail the hardware/software environment that this project was created on.
.DESCRIPTION
    This script does a quick inventory of your hardware / software. To view my results, 
    please refer to the Technical Reference: Host Environment 
    
#>

# Gathered sys specs
$OS = Get-CimInstance Win32_OperatingSystem
$CPU = Get-CimInstance Win32_Processor
$CS = Get-CimInstance Win32_ComputerSystem
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

# Hyper-V Status
$HyperV = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue

# Check VS Code Installation (User or System level)
$VSCodePath = "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
$VSCodeSysPath = "$env:ProgramFiles\Microsoft VS Code\Code.exe"
$HasVSCode = (Test-Path $VSCodePath) -or (Test-Path $VSCodeSysPath)

$SystemReport = [PSCustomObject]@{
    ComputerName      = $env:COMPUTERNAME
    OSName            = $OS.Caption
    OSVersion         = $OS.Version
    OSBuild           = $OS.BuildNumber
    CPUName           = $CPU.Name
    Cores             = $CPU.NumberOfCores
    LogicalProcessors = $CPU.NumberOfLogicalProcessors
    TotalMemoryGB     = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
    DiskSpace         = foreach ($d in $Disks) {
        [PSCustomObject]@{
            Drive  = $d.DeviceID
            FreeGB = [math]::Round($d.FreeSpace / 1GB, 2)
            TotalGB = [math]::Round($d.Size / 1GB, 2)
        }
    }
    HyperVEnabled     = if ($HyperV) { $HyperV.State -eq 'Enabled' } else { $false }
    VSCodeInstalled   = $HasVSCode
}

# 1. Display the report on the screen
$SystemReport | Format-List

# 2. Define output path and ensure directory exists
$OutputPath = "C:\Temp\SystemSpecs.json"
$OutputDirectory = Split-Path $OutputPath
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
}

# 3. Export to file simultaneously
$SystemReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "`n[+] System specifications successfully exported to: $OutputPath" -ForegroundColor Green