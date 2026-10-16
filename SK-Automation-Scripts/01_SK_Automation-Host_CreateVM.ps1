<#
.SYNOPSIS
    Stage 2.1 - Hyper-V Virtual Machine Provisioning & Startup Orchestration
    Script: 01_SK_Automation-Host_CreateVM.ps1
.DESCRIPTION
    Automates the provisioning of Gen2 virtual machines from Sysprepped golden 
    VHDX templates produced by Packer.  Want to use your own Sysprepped .VHDx?

    In TheOneRing.ps1.
    
    "param(
    # Set this to $true if you want to skip straight to VM creation using your .VHDx.  
    # Just place them in the correct Output directory listed in variables.pkr.hcl - "output_directory" 
    [switch]$SkipPackerBuild = $false

    Also, the .VHDx names need to be changed below:
    $GoldenImages = @{
    "Win2025" = Join-Path -Path $ProjectRoot -ChildPath "output-ws2025-master-vhd\Virtual Hard Disks\Win2025-GoldenImage-Build.vhdx"
    "Win11"   = Join-Path -Path $ProjectRoot -ChildPath "output-win11-master-vhd\Virtual Hard Disks\Win11-GoldenImage-Build.vhdx"
}

)"  
    This script also validates the project switches, clones disks, configures hardware profiles (vCPU, Dynamic Memory, 
    vTPM, Secure Boot), and initiates a staggered startup to prevent storage booting issues.
.NOTES
    Environment  : Hyper-V Host (Windows 11 / Windows Server 2025)
    Dependencies : Packer golden VHDX output, existing Hyper-V virtual switch (e.g., pfSense  lab-switch-lan (for VM isolation)
    and lab-switch-wan (for outbound host connectivity)
#>

<#
==================================================================================
STANDALONE STAGED EXECUTIONS  (Outside the OneRing Orchestrator - execute each script in secquence):

1. Execute these credential variables first in your VSC PowerShell console - make sure you enter the correct password you set in Packer for the Administrator account:

   $secPass = ConvertTo-SecureString "Enter the password you put enter in the auto.packer.pkrvars.hcl" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Then execute the script passing the credential object:
   .\02_SK_Automation-Host_VMConfigTest.ps1 -Credential $cred

This will run this script and not carry on to the next.
==================================================================================
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# ==============================================================================
# 1. ENVIRONMENT CONFIGURATION & PRE-RUN PATH CHECKS
# ==============================================================================
# Resolve root directories relative to the current script execution path
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }

# Determine the parent directory: the root of the SK-Automation-Scripts project
$ProjectRoot = Split-Path -Path $ScriptDir -Parent

# Target directory where individual VM configuration folders and cloned VHDXs reside
$VMPath = Join-Path -Path $ProjectRoot -ChildPath "Hyper-V_VMs" # change this if you want to store your VMs somewhere else, but make sure you have enough disk space for all the VMs and their VHDX files.
if (-not (Test-Path -Path $VMPath)) {  #View documentation for more info on how to change this path if you want to store your VMs somewhere else.
    New-Item -ItemType Directory -Path $VMPath -Force | Out-Null
}

# ------------------------------------------------------------------------------
#This hashtable tells the deployment script exactly where to find the sealed base disks created by Packer in Stage 1. When Stage 2 provisions a new VM, 
#it references this list to clone the correct master VHDX (Windows Server 2025 or Windows 11 Enterprise) directly into the new node's storage folder.

$GoldenImages = @{
    "Win2025" = Join-Path -Path $ProjectRoot -ChildPath "output-ws2025-master-vhd\Virtual Hard Disks\Win2025-GoldenImage-Build.vhdx"
    "Win11"   = Join-Path -Path $ProjectRoot -ChildPath "output-win11-master-vhd\Virtual Hard Disks\Win11-GoldenImage-Build.vhdx"
}

# Pre-run check: Verify all required packer images exist prior to provisioning
foreach ($osTag in $GoldenImages.Keys) {
    $imgPath = $GoldenImages[$osTag]
    if (-not (Test-Path -Path $imgPath -PathType Leaf)) {
        Write-Error "CRITICAL: Master template for [$osTag] was not found at: $imgPath"
        exit 1
    }
    Write-Host "Verified Golden Image for [$osTag]: $(Split-Path -Leaf $imgPath)" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# NOTE: HYPER-V VIRTUAL SWITCH VALIDATION
# The switch names specified below must match the virtual switches created on
# your host exactly. If you rename a switch in Hyper-V Manager, update both
# $RequiredSwitches here and the 'Switch' property for each VM in $VMList.
#
# MULTI-FOREST DEPLOYMENTS:
# If you are deploying an additional Active Directory forest or isolated subnet,
# create its dedicated switch in Hyper-V and pfSense first, then add it to this
# validation array (e.g., @("lab-switch-lan", "lab-switch-lan2")) and ensure it
# matches the corresponding node entries in your $VMList hashtable.
# ------------------------------------------------------------------------------
$RequiredSwitches = @("lab-switch-lan")
foreach ($sw in $RequiredSwitches) {
    $existingSwitch = Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue
    if (-not $existingSwitch) {# 2. VIRTUAL MACHINE CONFIGURATION ($VMList)
        Write-Error "CRITICAL: Virtual Switch [$sw] was not found in Hyper-V."
        Write-Host "Ensure your pfSense LAN switch exists and matches the exact name before deploying VMs." -ForegroundColor Yellow
        exit 1
    }# 2. VIRTUAL MACHINE CONFIGURATION ($VMList)
    Write-Host "Verified Virtual Switch: [$($existingSwitch.Name)] (Type: $($existingSwitch.SwitchType))" -ForegroundColor Green
}
# ==============================================================================


# ==============================================================================
# 2. VIRTUAL MACHINE CONFIGURATION ($VMList)
# ==============================================================================
# IMPORTANT:
# - Ensure SK_Automation-VMConfig.json mirrors all changes made here (IP, Role, DNS).
# - Disk size (default: 60 GB) is set in build.pkr.hcl (disk_size = 61440).
# - Add, comment out (#), or remove nodes to match your hardware capacity and lab infrastructure
# - Assign the correct 'Role' (RootDC, ReplicaDC, MS, Client) so the scripts run properly.
# ==============================================================================
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers - used for replication / HA etc..
    @{Name = "SRV-DC1"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "RootDC"; Forest = "internal.sk-it.com" },
    @{Name = "SRV-DC2"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "ReplicaDC"; Forest = "internal.sk-it.com" },

    # Member Servers: MS Exchange, Azure Backup, Web-server Fail-over clustering etc.. 
   # @{Name = "SRV-EX01"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "MS"; Forest = "internal.sk-it.com" },
    @{Name = "SRV-MS01"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "MS"; Forest = "internal.sk-it.com" }
   
    # Client Workstations: Windows 11 Enterprise for WAC, Permissions testing, FSLogix profiles, Azure SSO etc..
    @{Name = "CLI-WIN11-01"; OS = "Win11"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 4GB; VCPU = 2; Role = "Client"; Forest = "internal.sk-it.com" }
)
# ==============================================================================

# ==============================================================================
# 3. CREATION & PROVISIONING PHASE (CLONING & HARDWARE EXTENSIONS)
# ==============================================================================
foreach ($VM in $VMList) {
    if (Get-VM -Name $VM.Name -ErrorAction SilentlyContinue) {
        Write-Warning "VM [$($VM.Name)] is already registered in Hyper-V. Skipping creation..."
        continue
    }

    # Resolve master disk template path based on OS identifier (Win2025 or Win11)
    $sourceImagePath = $GoldenImages[$VM.OS]
    if (-not $sourceImagePath) {
        Write-Error "Invalid OS identifier [$($VM.OS)] defined for VM [$($VM.Name)]. Skipping..."
        continue
    }

    Write-Host "`n>>> Deploying [$($VM.Name)] using [$($VM.OS)] Image..." -ForegroundColor Cyan
    
    # Establish VM directory structure
    $VHDDir = Join-Path -Path $VMPath -ChildPath $VM.Name
    if (-not (Test-Path -Path $VHDDir)) { 
        New-Item -ItemType Directory -Path $VHDDir -Force | Out-Null 
    }
    $NewVHDPath = Join-Path -Path $VHDDir -ChildPath "$($VM.Name).vhdx"

    # Clone the target OS master disk if a previous disk does not already exist
    if (-not (Test-Path -Path $NewVHDPath)) {
        Write-Host "    Cloning [$($VM.OS)] base disk to:$NewVHDPath..." -ForegroundColor Gray
        Copy-Item -Path $sourceImagePath -Destination $NewVHDPath -Force
    }
    else {
        Write-Host "    Existing disk detected at $NewVHDPath. Attaching existing file..." -ForegroundColor Yellow
    }

    # Create Generation 2 VM shell
    Write-Host "    Registering Generation 2 VM..." -ForegroundColor Gray
    $null = New-VM -Name $VM.Name `
        -MemoryStartupBytes $VM.MemStart `
        -Generation 2 `
        -Path $VMPath `
        -VHDPath $NewVHDPath `
        -SwitchName $VM.Switch
    
    # Configure Dynamic Memory allocations and vCPU count
    Set-VMMemory -VMName $VM.Name `
        -DynamicMemoryEnabled $true `
        -MinimumBytes $VM.MemMin `
        -MaximumBytes $VM.MemMax
    
    Set-VMProcessor -VMName $VM.Name -Count $VM.VCPU

    # Security configuration: Local Key Protector, Virtual TPM, and Checkpoint policy
    Set-VMKeyProtector -VMName $VM.Name -NewLocalKeyProtector
    Enable-VMTPM -VMName $VM.Name
    Set-VM -Name $VM.Name -CheckpointType Disabled

    # Configure UEFI boot order and Secure Boot template
    $VHD = Get-VMHardDiskDrive -VMName $VM.Name
    Set-VMFirmware -VMName $VM.Name `
        -FirstBootDevice $VHD `
        -EnableSecureBoot On `
        -SecureBootTemplate "MicrosoftWindows"
    
    Write-Host "    [$($VM.Name)] provisioned successfully." -ForegroundColor Green
}
# ==============================================================================


# ==============================================================================
# 4. STARTUP & ORCHESTRATION PHASE
# ==============================================================================
# Starts VMs sequentially with a delay to mitigate storage I/O boot storms.
# ==============================================================================
Write-Host "`n>>> Initiating Virtual Machine Startup Sequence..." -ForegroundColor Cyan

$AllVMsStarted = $true

foreach ($VM in $VMList) {
    $vmObject = Get-VM -Name $VM.Name -ErrorAction SilentlyContinue

    if ($null -eq $vmObject) {
        Write-Warning "Unable to start [$($VM.Name)]: VM not found in Hyper-V."
        $AllVMsStarted = $false
        continue
    }

    if ($vmObject.State -eq 'Running') {
        Write-Host "VM [$($VM.Name)] is already running. Skipping start." -ForegroundColor Yellow
    }
    else {
        Write-Host "Starting [$($VM.Name)]..." -ForegroundColor Yellow
        Start-VM -Name $VM.Name
        
        # 5-second stagger interval to smooth out storage I/O during specialization
        Start-Sleep -Seconds 5
    }
}

# --- STAGE COMPLETION SUMMARY ---
if ($AllVMsStarted) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host "PIPELINE MILESTONE STATUS: STAGE 2.1 COMPLETE!                    " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "[STAGE 1 COMPLETE]   Packer golden .VHDX created and exported."     -ForegroundColor Green
    Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
    Write-Host "[STAGE 2.2 STARTING] VM PS Direct / VMBus Testing."                 -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}
else {
    Write-Warning "`n[STAGE 2.1 WARNING] One or more virtual machines failed to provision or start."
    Write-Warning "Check Hyper-V host resources, event logs, and virtual disk paths before proceeding."
}


### Key Technical cecisions behind the provisioning Code (AI Generated Notes)
<#
* **Dynamic Memory allocation:** Prevents host RAM exhaustion by letting idle nodes drop to 1–2 GB while providing a 6 GB ceiling during heavy operations like domain promotion.
* **Checkpoints disabled during build:** Avoids disk locking and messy `.avhdx` differencing trees while cloning and configuring nodes.
* **Generation 2 and Virtual TPM:** Delivers native UEFI Secure Boot and vTPM for clean Windows 11 and Server 2025 installs without registry bypasses.
* **Staggered 5-second boot intervals:** Eliminates storage I/O bottlenecks caused by multiple VMs running sysprep specialization at the same time.
* **Pre-run dependency checks:** Verifies that required virtual switches and base VHDXs exist in Hyper-V before attempting VM creation.#>