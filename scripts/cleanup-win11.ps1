<#
.SYNOPSIS
    Stage 4 - Automated Windows 11 Image Sanitization, BitLocker Decryption & Sysprep Prep.
    Script: cleanup-win11.ps1

.DESCRIPTION
    Executes guest OS sanitization and addresses known Windows 11 Sysprep blockers prior
    to final generalization and VHDX capture:

    1. Enforces BitLocker Decryption Verification:
       - Disables BitLocker on C: and enters a blocking poll loop until the volume status 
         reports 'FullyDecrypted'.
       - Resolves fatal Sysprep generalization aborts caused by Windows 11 modern automatic 
         device encryption remaining in an active or suspended state.
    2. Terminates Background Servicing Locks:
       - Stops AppX Servicing (AppXSvc) and Windows Update (wuauserv) to prevent dynamic 
         file locks while Sysprep accesses system hives.
    3. De-provisions Removable Consumer AppX Packages:
       - Strips non-framework, removable AppX packages across all user profiles to prevent 
         common 0x80073CF2 generalization failures.
    4. Purges Build Artifacts and Classic Event Logs:
       - Removes early-stage automation breadcrumbs, bootstrap logs, and clears classic logs.
    5. ReTrims and Compacts Storage:
       - Executes volume ReTrim to release unallocated sectors, keeping the final master VHDX 
         footprint as small as possible.

.NOTES
    Target OS        : Windows 11 Enterprise / Pro (64-bit)
    Execution Context: Packer PowerShell Provisioner (WinRM over HTTPS)
    Key Fix          : BitLocker must be fully decrypted; running Sysprep against an encrypted or 
                       partially decrypted system volume results in an immediate failure.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Starting Windows 11 Enterprise pre-Sysprep cleanup..." -ForegroundColor Cyan

# ==============================================================================
# 1. VERIFY AND FINALIZE BITLOCKER DECRYPTION FIRST
# ==============================================================================
# BitLocker must be fully decrypted before running Sysprep or generalization will fail
Write-Host "Verifying BitLocker status..." -ForegroundColor Gray
cmd.exe /c "manage-bde.exe -off C:" | Out-Null
Disable-BitLocker -MountPoint "C:" -ErrorAction SilentlyContinue | Out-Null

do {
    $vol = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
    $status = if ($vol) { $vol.VolumeStatus } else { $null }

    if ($status -and $status -ne "FullyDecrypted") {
        Write-Host "BitLocker status: $status. Waiting 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
} while ($status -and $status -ne "FullyDecrypted")

Write-Host "BitLocker fully decrypted." -ForegroundColor Green

# ==============================================================================
# 2. STOP BACKGROUND SERVICES PREVENTING SYSPREP
# ==============================================================================
# Halts update and modern app background tasks from locking files during Sysprep
Stop-Service -Name "AppXSvc" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 3. DE-PROVISION CONSUMER APPX PACKAGES
# ==============================================================================
# Removes provisioned consumer AppX packages that commonly trigger 0x80073CF2 errors
Get-AppxPackage -AllUsers |
    Where-Object { $_.NonRemovable -ne $true -and $_.IsFramework -ne $true } |
    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# ==============================================================================
# 4. REMOVE LOGS, BREADCRUMBS & EVENT LOGS
# ==============================================================================
# Cleans temporary setup flags and installer debug outputs
Remove-Item -Path "C:\step3*.txt", "C:\bootstrap*.txt", "C:\bootstrap_debug.log" -Force -ErrorAction SilentlyContinue

# Wipes classic application, system, and security logs
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 -and $_.IsClassicLog } |
    ForEach-Object { Clear-EventLog -LogName $_.LogName -ErrorAction SilentlyContinue }

# Cleans system recycle bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 5. FINAL DISK OPTIMIZATION (Must be last)
# ==============================================================================
# Issues SSD trim to ensure the dynamic VHDX captures at minimum file size
Write-Host "Optimizing and trimming C: volume for VHDX capture..." -ForegroundColor Cyan
Optimize-Volume -DriveLetter C -ReTrim -Verbose

Write-Host "Windows 11 sanitization complete. Ready for Sysprep sealing." -ForegroundColor Green