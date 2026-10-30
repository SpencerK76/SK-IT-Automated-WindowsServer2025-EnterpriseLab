<#
.SYNOPSIS
    SK_Automation-host_The-One-Ring.ps1 - The Master Orchestrator for the SK Automation Pipeline, built
    from the fires of mount doom!.

.DESCRIPTION
    This is the automation engine of the entire deployment. Running this script executes all stages (scripts)
    in order: building Packer golden image creations, creating Hyper-V virtual machines, 
    injecting network and identity configurations via PowerShell Direct, promoting the 
    Active Directory Root Domain Controller, joining member servers and client nodes, 
    and configuring DHCP scopes, Organizational Units, and test lab users.

    You can run this whole process hands-free, or execute individual scripts manually
    if you need to restart a specific stage after a halt or failure.  Please view each script for the explicit 
    script link for the individual code to be executed.  The scripts are designed to be idempotent, so you can safely re-run any stage.
    
    The following scripts are executed in sequence;

    1. build.pkr.hcl (via packer.exe)
       - Builds the baseline evaluation VHDX golden images for Windows Server 2025 and Windows 11.
    2. 01_SK_Automation-Host_CreateVM.ps1
       - Clones golden disks, creates Hyper-V VM shells, attaches virtual switches, and configures hardware resources.
    3. 02_SK_Automation-Host_VMConfigTest.ps1
       - Verifies that all provisioned guest nodes are alive and responsive over VMBus using PowerShell Direct.
    4. 03_SK_Automation-Host_VMConfigDeploy.ps1
       - Applies static IP addressing, subnets, gateways, DNS servers, and guest hostnames from SK_Automation-VMConfig.json.
    5. 04_SK_Automation-Host_PromoteRootDC.ps1
       - Installs AD DS and DNS roles, configures Active Directory, and promotes the primary Forest Root Domain Controller.
    6. 05_SK_Automation-Host_NodeJoin.ps1
       - Joins secondary Domain Controllers, member servers, and Windows 11 client nodes to the domain.
    7. 06_SK_Automation-Host_CustomConfigs.ps1
       - Installs and configures DHCP scopes on the Root DC, and creates test Organizational Units, groups, and lab user accounts.
#>
   
[CmdletBinding()]
param(
    # ------------------------------------------------------------------------------
    # PIPELINE CONTROL: SKIP THE PACKER BUILD PROCESS:  After you have created the golden images once, you can skip the Packer build process when adding nodes to your lab.
    # Set - $SkipPackerBuild to $true to bypass Stage 1 (The packer build).
    # When enabled, the pipeline assumes valid, Sysprepped Gen 2 VHDX templates exist at the file paths defined in 01_SK_Automation-Host_CreateVM.ps1 ($GoldenImages).
    # If you do intend to use your own pre-built VHDX templates, your VHDX images must meet 5 core requirements. 
    #
    # 1. Integration Services: The image must have 'vmicvmsession' set to Automatic and RemoteSigned execution policy enabled for host VMBus commands.
    # 2. Local Admin: The local Administrator account must remain active, unlocked, and assigned a known, static password that bypasses OOBE prompts.
    # 3. Provisioning & Firewall: Inbound management traffic (WinRM and PowerShell Direct) must be permitted through Windows Firewall across all network profiles.
    # 4. Networking: Network adapters must be set to DHCP before sysprep so new synthetic interfaces initialize cleanly without stale IP conflicts.
    # 5. UEFI/GPT Layout: The disk must use a GPT partition layout with valid EFI system and MSR partitions to support Generation 2 SCSI booting.
    # NOTE: It is significantly easier to simply configure your existing unattended .xml files and add these steps to the Packer 
    # build provisioning block than to manually configure all five requirements above on a custom VHDX.
    #
    #
    # ------------------------------------------------------------------------------
    [switch]$SkipPackerBuild = $false  # Set to $true to skip Stage 1 (Packer build) and use existing golden images or to carry over existing configurations.
)

# Stop execution immediately if any command encounters an unhandled terminating error.
$ErrorActionPreference = "Stop"

# Enable verbose logging for Packer so you can see detailed output in the VSC console if troubleshooting is needed. Recommended viewing!
$env:PACKER_LOG = 1


# ==============================================================================
# STEP 1a: PATH RESOLUTION & SCRIPT DISCOVERY!
# ==============================================================================
# Discover the current folder (SK-Automation-Scripts) and step up one level to the repository root.
$ScriptDir   = $PSScriptRoot
$ProjectRoot = Split-Path -Path $ScriptDir -Parent

# Stage 1: Packer Executable and Variable Files
$PackerExe   = Join-Path -Path $ProjectRoot -ChildPath "packer.exe"
$HclVarsPath = Join-Path -Path $ProjectRoot -ChildPath "packer.auto.pkrvars.hcl"

# Stage 2: VM Shell Creation, VMBus Verification, and Guest OS IP Configuration
$Stage2_1Path = Join-Path -Path $ScriptDir -ChildPath "01_SK_Automation-Host_CreateVM.ps1"
$Stage2_2Path = Join-Path -Path $ScriptDir -ChildPath "02_SK_Automation-Host_VMConfigTest.ps1"
$Stage2_3Path = Join-Path -Path $ScriptDir -ChildPath "03_SK_Automation-Host_VMConfigDeploy.ps1"

# Stage 3: Active Directory Domain Services, Node Joining, and Custom Lab Workloads
$Stage3_1Path = Join-Path -Path $ScriptDir -ChildPath "04_SK_Automation-Host_PromoteRootDC.ps1"
$Stage3_2Path = Join-Path -Path $ScriptDir -ChildPath "05_SK_Automation-Host_NodeJoin.ps1"
$Stage3_3Path = Join-Path -Path $ScriptDir -ChildPath "06_SK_Automation-Host_CustomConfigs.ps1"

Write-Host "Validating Packer templates..." -ForegroundColor Cyan

# Temporarily quiet standard output; let exit code tell us if it succeeded
$null = & $PackerExe validate $ProjectRoot

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Packer template validation failed!" -ForegroundColor Red
    # Rerun validate directly so errors print cleanly to the terminal
    & $PackerExe validate$ProjectRoot
    Write-Error "CRITICAL: Packer validation failed. Pipeline aborted."
    exit 1
}

Write-Host "Packer templates validated successfully.`n" -ForegroundColor Green


# ==============================================================================
# STEP 1b: CREDENTIAL EXTRACTION (set in packer.auto.pkrvars.hcl)!
# ==============================================================================
# We extract credentials directly from packer.auto.pkrvars.hcl so you only ever have to set passwords in one place.
if (-not (Test-Path -Path $HclVarsPath)) {
    Write-Error "CRITICAL: Configuration file 'packer.auto.pkrvars.hcl' not found at: $HclVarsPath"
    exit 1
}

$hclContent = Get-Content -Path $HclVarsPath -Raw
$adminUser  = ($hclContent | Select-String -Pattern 'admin_username\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$adminPass  = ($hclContent | Select-String -Pattern 'admin_password\s*=\s*"([^"]+)"').Matches.Groups[1].Value

# Convert the plain text password into a secure string and build a PSCredential object.
$secPass    = ConvertTo-SecureString $adminPass -AsPlainText -Force
$MasterCred = New-Object System.Management.Automation.PSCredential($adminUser, $secPass)

Write-Host "Master Pipeline credential initialized for administrative user: [$adminUser]" -ForegroundColor Green


# ==============================================================================
# STEP 1c: PRE-RUN VERIFICATION!
# ==============================================================================
# Verify all required script files exist before we begin, preventing half-built environments.
$RequiredFiles = @(
    $PackerExe,
    $Stage2_1Path,
    $Stage2_2Path,
    $Stage2_3Path,
    $Stage3_1Path,
    $Stage3_2Path,
    $Stage3_3Path
)

foreach ($File in $RequiredFiles) {
    if (-not (Test-Path -Path $File)) {
        Write-Error "CRITICAL PRE-RUN CHECK FAILED: Required file missing: '$File'"
        exit 1
    }
}
Write-Host "Pre-run file verification passed. All pipeline components located." -ForegroundColor Green


# ==============================================================================
# STAGE 1: PACKER DUAL-IMAGE BUILD - It begins.
# ==============================================================================
if (-not $SkipPackerBuild) {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host " [STAGE 1] INITIATING PACKER BUILD PIPELINE                 " -ForegroundColor Cyan
    Write-Host " [STAGE 1] CREATING WINDOWS SERVER 2025 & WINDOWS 11 IMAGES " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    Set-Location -Path $ProjectRoot

    # Run Packer using the local executable and current repository configuration files.
    & $PackerExe build -force .

    if ($LASTEXITCODE -ne 0) {
        Write-Error "CRITICAL: Packer build failed with exit code $LASTEXITCODE. Halting pipeline."
        exit $LASTEXITCODE
    }

    Write-Host "[STAGE 1 SUCCESS] Both Golden Images generated and sealed successfully." -ForegroundColor Green
} else {
    Write-Host "[STAGE 1 SKIPPED] Using existing Golden VHDX disk images." -ForegroundColor Yellow
}


# ==============================================================================
# STAGE 2.1: VM CLONING & HYPER-V ORCHESTRATION
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 2.1] HYPER-V VM CREATION                          " -ForegroundColor Cyan
Write-Host " [Running Script: 01_SK_Automation-Host_CreateVM.ps1]     " -ForegroundColor Cyan
Write-Host " Here we orchestrate your Hyper-V setup, creating the actual VMs from the `$VMList array & .JSON configs    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Execute Stage 2.1 to clone disks and create VM hardware shells
& $Stage2_1Path

if ($LASTEXITCODE -ne 0 -and $null -ne$LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 2.1 VM Creation failed. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

Write-Host "`n[STAGE 2.1 SUCCESS] All Hyper-V VMs created are now running and logged in with admin credentials." -ForegroundColor Green


# ==============================================================================
# STAGE 2.2: VM VMBUS & POWERSHELL DIRECT CONNECTIVITY TEST!
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 2.2] VM VMBUS TEST: Verifying Guest Responsiveness" -ForegroundColor Cyan
Write-Host " [Running Script: 02_SK_Automation-Host_VMConfigTest.ps1] " -ForegroundColor Cyan
Write-Host " Verifying that VMs are accepting PowerShell Direct sessions over the VMBus." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Tests guest connectivity over PowerShell Direct using the config from packer.auto.pkrvars.hcl.
& $Stage2_2Path -Credential $MasterCred

if ($LASTEXITCODE -ne 0 -and $null -ne$LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 2.2 verification failed on one or more nodes. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

Write-Host "`n[STAGE 2.2 SUCCESS] All guest nodes verified responsive over VMBus." -ForegroundColor Green


# ==============================================================================
# STAGE 2.3: GUEST IDENTITY & STATIC NETWORK CONFIGURATION!
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 2.3] VM CONFIGURATION: Applying Network Settings  " -ForegroundColor Cyan
Write-Host " [Running Script: 03_SK_Automation-Host_VMConfigDeploy.ps1]" -ForegroundColor Cyan
Write-Host " Applying IP addresses, subnets, and hostnames defined in SK_Automation-VMConfig.json." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Applies static IP configuration and hostnames into the guest VMs.
& $Stage2_3Path -Credential $MasterCred

if ($LASTEXITCODE -ne 0 -and $null -ne$LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 2.3 Guest Configuration Deployment failed. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

Write-Host "`n[STAGE 2.3 SUCCESS] All guest node VMs configured with static IPs and hostnames." -ForegroundColor Green


# ==============================================================================
# STAGE 3.1: PROMOTING ROOT DOMAIN CONTROLLER!
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.1] ACTIVE DIRECTORY: Promoting Forest Root DC  " -ForegroundColor Cyan
Write-Host " [Running Script: 04_SK_Automation-Host_PromoteRootDC.ps1]" -ForegroundColor Cyan
Write-Host " Installing AD DS, DNS Server role, and promoting the primary Forest Root DC." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Promotes the Root DC and reboots the guest machine.
& $Stage3_1Path -Credential $MasterCred

if ($LASTEXITCODE -ne 0 -and $null -ne$LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 3.1 Root Domain Controller Promotion failed. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

Write-Host "`n[STAGE 3.1 SUCCESS] Forest Root Domain Controller promoted and verified healthy." -ForegroundColor Green


# ==============================================================================
# STAGE 3.2: DOMAIN JOIN MEMBER SERVERS & CLIENTS!
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.2] DOMAIN INTEGRATION: Joining Nodes to Domain " -ForegroundColor Cyan
Write-Host " [Running Script: 05_SK_Automation-Host_NodeJoin.ps1]    " -ForegroundColor Cyan
Write-Host " Joining additional Domain Controllers, member servers, and Windows 11 clients." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Joins secondary DCs and all client/member nodes to the domain.
& $Stage3_2Path -Credential $MasterCred

if ($LASTEXITCODE -ne 0 -and $null -ne$LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 3.2 Node Joining failed. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

# ==============================================================================
# STAGE 3.3: POST-DEPLOYMENT CONFIGURATIONS (DHCP, OUs and USERS)!
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.3] WORKLOAD CONFIGURATION: Customizing Lab      " -ForegroundColor Cyan
Write-Host " [Running Script: 06_SK_Automation-Host_CustomConfigs.ps1]" -ForegroundColor Cyan
Write-Host " Installing DHCP scopes, creating Organizational Units, and provisioning test users." -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Configures DHCP, test accounts, and enterprise OU hierarchy.
& $Stage3_3Path -Credential $MasterCred

if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
    Write-Error "CRITICAL: Stage 3.3 Custom Configuration failed. Halting pipeline."
    Write-Error "NOTE: You can run lab-wipe.ps1 to reset (wipe) the VM lab environment."
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " 🧙 The One Ring Orchestrator has finished, Middle-earth is now restored. This day begins the realm of hope, and the years of peace. " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green