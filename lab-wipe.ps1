#Lab break-down script for SK-Automation-Project. This script will stop and remove all lab VMs and their associated storage folders. It is intended for use in a lab environment where you want to quickly reset the state of your Hyper-V host.

# Resolve paths relative to where this script is executed
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$VMBasePath = Join-Path -Path $ScriptDir -ChildPath "Hyper-V_VMs"
$TargetVMFilter = @("*SRV*", "*CLI*")

Write-Host "Target VM Filter : $($TargetVMFilter -join ', ')" -ForegroundColor Cyan
Write-Host "Storage Path     : $VMBasePath" -ForegroundColor Cyan

# Confirmation gate
$confirmation = Read-Host "Proceed with deleting lab VMs and disks? (Y/N)"
if ($confirmation -notmatch '^[Yy]$') {
    Write-Host "Teardown cancelled. No changes were made." -ForegroundColor Gray
    exit
}


$vms = Get-VM -Name $TargetVMFilter -ErrorAction SilentlyContinue

if ($vms) {
    Write-Host "Stopping running VMs..." -ForegroundColor Yellow
    $vms | Where-Object { $_.State -ne 'Off' } | Stop-VM -TurnOff -Force -Confirm:$false

    Write-Host "Removing VM configurations from Hyper-V..." -ForegroundColor Yellow
    $vms | Remove-VM -Force -Confirm:$false
} else {
    Write-Host "No matching VMs found registered in Hyper-V." -ForegroundColor Gray
}


Write-Host "Waiting 5 seconds for disk locks to clear..." -ForegroundColor Gray
Start-Sleep -Seconds 5

if (Test-Path -Path $VMBasePath) {
    Write-Host "Deleting VM disk folders..." -ForegroundColor Yellow
    Get-ChildItem -Path $VMBasePath -Directory |
        Where-Object { $_.Name -like "*SRV*" -or $_.Name -like "*CLI*" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Lab environment wiped cleanly." -ForegroundColor Green
Write-Host "Note: Packer master golden image files were not touched. Delete them if needed." -ForegroundColor Cyan