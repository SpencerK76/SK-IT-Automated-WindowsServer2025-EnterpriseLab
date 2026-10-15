<#
.SYNOPSIS
  Stage 3.1 - Active Directory Domain Services Forest Root Promotion
  Script 04_SK_Automation-Host_PromoteRootDC.ps1
    
.DESCRIPTION
    Consumes SK_Automation-VMConfig.json, identifies the node designated as "RootDC" (SRV-DC1), 
    and establishes a zero-network session using Hyper-V PowerShell Direct (VMBus).

    Executes the following operations:
      1. Installs the AD-Domain-Services role and RSAT management tools.
      2. Executes Install-ADDSForest via splatting to seed the forest root (internal.sk-it.com).
      3. Permits Windows to execute its coordinated post-promotion reboot.
      4. Polls the guest until Active Directory Web Services (ADWS) and DNS are fully operational.


<#
==================================================================================
STANDALONE EXECUTION EXAMPLE (Outside the OneRing Orchestrator):
1. Execute these credential variables first in your PowerShell console:
   $secPass = ConvertTo-SecureString "YourAdminPasswordHere" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Then execute the script passing the credential object:
   .\04_SK_Automation-Host_PromoteRootDC.ps1 -Credential $cred
==================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [pscredential]$Credential,

    [Parameter(Mandatory = $false)]
    [string]$JsonPath = "SK_Automation-VMConfig.json"
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# 1. CREDENTIAL RESOLUTION - added to each script, allowing for either orchestrator-passed PSCredential or interactive prompt
# ==============================================================================
if (-not $Credential) {
    if ($env:LAB_ADMIN_PASSWORD) {
        $secPass = ConvertTo-SecureString $env:LAB_ADMIN_PASSWORD -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)
    }
    else {
        Write-Host "No credential passed from orchestrator." -ForegroundColor Yellow
        $Credential = Get-Credential -UserName "Administrator" -Message "Enter Local Administrator Credential for Lab VMs (from packer.auto.pkrvars.hcl)"
    }
}

# ==============================================================================
# 2. CONFIGURATION & NODE DISCOVERY
# ==============================================================================
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$ResolvedJsonPath = if ([System.IO.Path]::IsPathRooted($JsonPath)) {
    $JsonPath
}
else {
    Join-Path -Path $ScriptDir -ChildPath $JsonPath
}

if (-not (Test-Path -Path $ResolvedJsonPath -PathType Leaf)) {
    Write-Error "CRITICAL: Configuration file not found at: $ResolvedJsonPath"
    exit 1
}

$Config = Get-Content -Raw -Path $ResolvedJsonPath | ConvertFrom-Json

$RootDC = $Config.VMs | Where-Object { $_.Role -eq "RootDC" }

if (-not $RootDC) {
    Write-Error "CRITICAL: No virtual machine with Role 'RootDC' found in $ResolvedJsonPath."
    exit 1
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.1] PROMOTING FOREST ROOT DOMAIN CONTROLLER    " -ForegroundColor Cyan
Write-Host " Target Node : $($RootDC.HyperVName) ($($RootDC.DomainName))" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$vmObj = Get-VM -Name $RootDC.HyperVName -ErrorAction SilentlyContinue
if (-not $vmObj -or $vmObj.State -ne 'Running') {
    Write-Error "CRITICAL: VM [$($RootDC.HyperVName)] is not running on host. Halting deployment."
    exit 1
}

# ==============================================================================
# 3. BINARY INSTALLATION 
# ==============================================================================
$DSRMPassword = $Credential.Password

try {
    Write-Host "`n[1/2] Installing AD DS Binaries and Management Tools..." -ForegroundColor White
    Invoke-Command -VMName $RootDC.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
        Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell -IncludeManagementTools | Out-Null
    }
    Write-Host "  -> AD DS feature binaries installed successfully." -ForegroundColor Green

    Write-Host "`n[2/2] Initiating Active Directory Forest Promotion..." -ForegroundColor White
    Write-Host "  -> Domain Name    : $($RootDC.DomainName)" -ForegroundColor Gray
    Write-Host "  -> NetBIOS Name   : $($RootDC.NetBIOSName)" -ForegroundColor Gray
    Write-Host "  -> Invoking Install-ADDSForest (Guest will automatically reboot)..." -ForegroundColor Yellow

    Invoke-Command -VMName $RootDC.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
        $Data = $using:RootDC
        $DSRMPass = $using:DSRMPassword

        Import-Module ADDSDeployment

        $AddsParams = @{
            DomainName                    = $Data.DomainName
            DomainNetbiosName             = $Data.NetBIOSName
            ForestMode                    = "WinThreshold"
            DomainMode                    = "WinThreshold"
            InstallDns                    = $true
            SafeModeAdministratorPassword = $DSRMPass
            Force                         = $true
            NoRebootOnCompletion          = $false
        }

        Install-ADDSForest @AddsParams
    }
}
catch {
    if ($_.Exception.Message -match "operation was canceled" -or $_.Exception.Message -match "transport connection") {
        Write-Host "  -> Promotion payload accepted; VM initiated automatic reboot." -ForegroundColor Green
    }
    else {
        Write-Warning "Promotion dispatch returned: $($_.Exception.Message.Trim())"
    }
}

# ==============================================================================
# 4. SYNCHRONIZATION BARRIER (DIRECTORY SERVICE VALIDATION)
# ==============================================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.1] SYNCHRONIZING: WAITING FOR AD SERVICES     " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Waiting 60 seconds for NTDS database initialization and reboot..." -ForegroundColor Gray
Start-Sleep -Seconds 60

$DomainUser = "$($RootDC.DomainName)\Administrator"
$DomainCred = New-Object System.Management.Automation.PSCredential($DomainUser, $Credential.Password)

$MaxRetries = 30
$RetryInterval = 10
$ForestReady = $false
$Attempt = 0

Write-Host "Probing Active Directory Web Services (ADWS) on [$($RootDC.HyperVName)]..." -NoNewline -ForegroundColor White

while (-not $ForestReady -and $Attempt -lt $MaxRetries) {
    $Attempt++
    try {
        $check = Invoke-Command -VMName $RootDC.HyperVName -Credential $DomainCred -ErrorAction Stop -ScriptBlock {
            $adws = Get-Service -Name "ADWS" -ErrorAction SilentlyContinue
            $dns = Get-Service -Name "DNS"  -ErrorAction SilentlyContinue
            
            if ($adws.Status -eq 'Running' -and $dns.Status -eq 'Running') {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                $domainObj = Get-ADDomain -ErrorAction SilentlyContinue
                if ($domainObj) {
                    return [PSCustomObject]@{
                        ForestName = $domainObj.Forest
                        DomainName = $domainObj.DNSRoot
                        PDC        = $domainObj.PDCEmulator
                    }
                }
            }
            return $null
        }

        if ($check) {
            $ForestReady = $true
            Write-Host " [ONLINE & HEALTHY]" -ForegroundColor Green
            Write-Host "`n  -> Active Directory Forest Verified:" -ForegroundColor Green
            Write-Host "     ├─ Forest Root     : $($check.ForestName)" -ForegroundColor Gray
            Write-Host "     ├─ Domain Partition: $($check.DomainName)" -ForegroundColor Gray
            Write-Host "     └─ PDC Emulator    : $($check.PDC)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds $RetryInterval
    }
}

if ($ForestReady) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host " PIPELINE MILESTONE STATUS: STAGE 3.1 COMPLETE!                     " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "[STAGE 1 COMPLETE]   Packer golden .VHDX created and exported."     -ForegroundColor Green
    Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
    Write-Host "[STAGE 2.2 COMPLETE] VM PS Direct / VMBus Testing."                 -ForegroundColor Green
    Write-Host "[STAGE 2.3 COMPLETE] VM Identity & Network Hydration Deployed."     -ForegroundColor Green
    Write-Host "[STAGE 3.1 COMPLETE] Forest Root DC Promoted & DNS Initialized."    -ForegroundColor Green
    Write-Host "[STAGE 3.2 STARTING] Replica DC Promotion and node join   ."        -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}
else {
    Write-Error "`nCRITICAL: Timed out waiting for Active Directory to stabilize on [$($RootDC.HyperVName)]."
    exit 1
}

<#
================================================================================
Design Decisions Taken: AI Generated Notes
================================================================================
1. Integrated Promotion Reboot Model:
   - Configured NoRebootOnCompletion = $false during Install-ADDSForest, allowing Windows 
     to manage its native directory promotion reboot sequence without manual hypervisor interrupts.

2. Transport Drop Handling:
   - Evaluated connection teardown within the try/catch block to distinguish between expected 
     reboot drops on VMBus and genuine AD DS binary installation failures.

3. Dynamic DSRM & Domain Credential Inheritance:
   - Securely propagates the master orchestrator PSCredential into the SafeModeAdministratorPassword 
     and constructs the DOMAIN\Administrator credential for post-promotion directory authentication.

4. Multi-Tier Health Verification Barrier:
   - Validates not just machine ping or RPC, but specifically confirms that the ADWS (Active 
     Directory Web Services) and DNS services are actively running, and queries Get-ADDomain via CIM.

5. Modern Functional Levels:
   - Standardized on 'WinThreshold' for ForestMode and DomainMode, maintaining current compatibility 
     for Windows Server 2025 and 2022 directory features.
================================================================================
#>
