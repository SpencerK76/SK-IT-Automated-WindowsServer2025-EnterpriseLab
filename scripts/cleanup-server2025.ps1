<#
.SYNOPSIS
    Stage 4 - Windows Server 2025 Image Sanitization & Sysprep Preparation
    Script: cleanup-server2025.ps1

.DESCRIPTION
    Prepares the Windows Server 2025 golden image for Sysprep generalization and VHDX capture:
      - Purges temporary bootstrap breadcrumbs, installer logs, and debug traces
      - Cleans the Windows Update download cache (SoftwareDistribution) and CBS log files
      - Flushes system and user temp directories and clears the Recycle Bin
      - Clears classic Windows Event Logs to remove build-time noise
      - ReTrims unallocated volume space to compact the final virtual disk footprint

.NOTES
    Target OS        : Windows Server 2025 (Standard / Datacenter)
    Execution Mode   : Packer PowerShell Provisioner (WinRM over HTTPS)
    Prerequisites    : Run prior to invoking Sysprep with /generalize /oobe /shutdown
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

# ==============================================================================
# 1. REMOVE BREADCRUMBS & BOOTSTRAP ARTIFACTS
# ==============================================================================
# Purges transient setup flags and debug logs created during initial first-logon runs
$bootstrapFiles = @(
    "C:\step3*.txt",
    "C:\bootstrap*.txt",
    "C:\bootstrap_debug.log"
)
foreach ($file in $bootstrapFiles) {
    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# 2. PURGE WINDOWS UPDATE CACHE & SERVICING LOGS
# ==============================================================================
# Stops background update services to release file locks on download folders
Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue

# Cleans stale update patches and Component Based Servicing (CBS) logs
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Logs\CBS\*.log" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 3. WIPE SYSTEM & USER TEMPORARY DIRECTORIES
# ==============================================================================
# Cleans Windows Temp folder
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Cleans local user temp folders
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 4. CLEAR WINDOWS EVENT LOGS
# ==============================================================================
# Clears all classic application, security, and system event logs before capturing
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 -and $_.IsClassicLog } |
    ForEach-Object { Clear-EventLog -LogName $_.LogName -ErrorAction SilentlyContinue }

# ==============================================================================
# 5. PURGE SYSTEM RECYCLE BIN
# ==============================================================================
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 6. STORAGE LAYOUT OPTIMIZATION (RETRIM)
# ==============================================================================
# Reclaims unused blocks, ensuring the exported dynamic VHDX remains as compact as possible
Optimize-Volume -DriveLetter C -ReTrim -Verbose