<#
.SYNOPSIS
    Stage 2.3 - Guest Identity, Static Networking & DNS Hydration
    Script 03_SK_Automation-Host_VMConfigDeploy.ps1
    
.DESCRIPTION
    Consumes the configuration settings in SK_Automation-VMConfig.json and establishes 
    (zero-network) sessions into each guest via Hyper-V PowerShell Direct (VMBus).

    Applies essential guest OS baseline settings:
      - Hostname synchronization (Rename-Computer)
      - Static IPv4 address, prefix length, and default gateway injection
      - Primary and secondary DNS client server assignment
      - Coordinated guest reboot to commit identity changes


<#
==================================================================================
STANDALONE STAGED EXECUTIONS  (Outside the OneRing Orchestrator - execute each script in secquence!):

1. Execute these credential variables first in your PowerShell console:
   $secPass = ConvertTo-SecureString "Enter the password you put enter in the auto.packer.pkrvars.hcl" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Then execute the script passing the credential object:
   .\03_SK_Automation-Host_VMConfigDeploy.ps1 -Credential $cred
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
# 1.# CREDENTIAL RESOLUTION - added to each script, allowing for either orchestrator-passed PSCredential or interactive prompt
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
# 2. CONFIGURATION INGESTION
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

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 2.3] INJECTING IDENTITY & NETWORK CONFIGURATION  " -ForegroundColor Cyan
Write-Host " Applying network and hostname attributes from JSON      " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ==============================================================================
# 3. DEPLOYMENT & IN-GUEST LOOP
# ==============================================================================
$AllNodesConfigured = $true

foreach ($VM in $Config.VMs) {

    Write-Host "`nTargeting node: [$($VM.HyperVName)]" -ForegroundColor Cyan

    $vmObj = Get-VM -Name $VM.HyperVName -ErrorAction SilentlyContinue
    if (-not $vmObj -or $vmObj.State -ne 'Running') {
        Write-Warning "VM [$($VM.HyperVName)] is not running on host. Skipping configuration..."
        $AllNodesConfigured = $false
        continue
    }

    try {
        $result = Invoke-Command -VMName $VM.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $Data = $using:VM

            $currentHost = $env:COMPUTERNAME
            $targetHost = if ($Data.OSHostName) { $Data.OSHostName } else { $Data.HyperVName }
            $renamed = $false

            if ($currentHost -ne $targetHost) {
                Rename-Computer -NewName $targetHost -Force -ErrorAction SilentlyContinue
                $renamed = $true
            }

            $Nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if (-not $Nic) {
                throw "No active network adapter (Status = 'Up') detected inside guest."
            }

            Remove-NetIPAddress -InterfaceIndex $Nic.InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute     -InterfaceIndex $Nic.InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

            New-NetIPAddress -InterfaceIndex $Nic.InterfaceIndex `
                -IPAddress $Data.IP `
                -PrefixLength $Data.Prefix `
                -DefaultGateway $Data.Gateway `
                -ErrorAction Stop | Out-Null

            if ($Data.DNS) {
                Set-DnsClientServerAddress -InterfaceIndex $Nic.InterfaceIndex `
                    -ServerAddresses $Data.DNS `
                    -ErrorAction Stop
            }

            return @{
                AppliedName = $targetHost
                AppliedIP   = $Data.IP
                AppliedDNS  = ($Data.DNS -join ", ")
                Renamed     = $renamed
            }
        }

        Write-Host "  -> [SUCCESS] Configuration injected:" -ForegroundColor Green
        Write-Host "     ├─ Target Hostname : $($result.AppliedName)" -ForegroundColor Gray
        Write-Host "     ├─ Static IPv4     : $($result.AppliedIP)" -ForegroundColor Gray
        Write-Host "     └─ DNS Addresses   : $($result.AppliedDNS)" -ForegroundColor Gray

        Write-Host "  -> Initiating graceful OS restart to commit identity..." -ForegroundColor Yellow
        Invoke-Command -VMName $VM.HyperVName -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
            Restart-Computer -Force
        }

    }
    catch {
        Write-Host "  -> [FAILED] Error on $($VM.HyperVName): $($_.Exception.Message.Trim())" -ForegroundColor Red
        $AllNodesConfigured = $false
    }
}

# ==============================================================================
# 4. STAGE COMPLETION SUMMARY
# ==============================================================================
if ($AllNodesConfigured) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host " PIPELINE MILESTONE STATUS: STAGE 2.3 COMPLETE!                     " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "[STAGE 1 COMPLETE]   Packer golden .VHDX created and exported."     -ForegroundColor Green
    Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
    Write-Host "[STAGE 2.2 COMPLETE] VM PS Direct / VMBus Testing."                 -ForegroundColor Green
    Write-Host "[STAGE 2.3 COMPLETE] VM Identity & Network Config Deployed."       -ForegroundColor Green
    Write-Host "[STAGE 3.1 STARTING] Active Directory Domain Services Provisioning." -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}
else {
    Write-Warning "`n[STAGE 2.3 WARNING] One or more virtual machines failed identity or network configuration."
    Write-Warning "Verify guest VM states, virtual switch links, and JSON property schema."
}

<#
================================================================================
Design Decisions Taken: AI Generated Notes
================================================================================
1. Zero-Network Out-of-Band Hydration:
   - Configures networking entirely via Hyper-V PowerShell Direct (VMBus), eliminating 
     the dilemma of needing functional TCP/IP or DHCP to assign static IPs.

2. Deterministic IP Stack Teardown & Binding:
   - Automatically purges residual DHCP, APIPA (169.254.x.x), and stale default routes 
     prior to binding static IP parameters, preventing duplicate IP and gateway conflicts.

3. Resilient Hostname & Property Fallback:
   - Dynamically evaluates $Data.OSHostName with an automatic fallback to $Data.HyperVName, 
     ensuring schema compatibility whether custom OS names are defined or inferred.

4. Non-Blocking In-Guest Reboots:
   - Dispatches 'Restart-Computer -Force' without host-side execution barriers, allowing 
     all guest nodes to commit their computer rename and network changes concurrently.

5. Dynamic Relative Path Resolution:
   - Utilizes $PSScriptRoot resolution for SK_Automation-VMConfig.json.
================================================================================
#>
