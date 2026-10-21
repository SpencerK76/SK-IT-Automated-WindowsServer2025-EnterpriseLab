<#
.SYNOPSIS
    Stage 3.2 - AD Topology, Replica DC Promotion & Fleet Domain Integration
    Script: 05_SK_Automation-Host_NodeJoin.ps1

.DESCRIPTION
    Reads 'SK_Automation-VMConfig.json' and provisions core domain infrastructure 
    across all remaining nodes via Hyper-V PowerShell Direct (VMBus):

      1. Root DC (SRV-DC1):
         - Creates the designated Active Directory Site (e.g., Kent-DataCenter) and Subnet
         - Moves the Root DC into its defined AD Site
         - Configures the Class C Reverse Lookup Zone (e.g., 0.0.10.in-addr.arpa)

      2. Replica DC (SRV-DC2):
         - Installs the AD-Domain-Services role and RSAT administration tools
         - Promotes the server to an additional domain controller in internal.sk-it.com
         - Reboots to finalize directory replication

      3. Member Servers & Client Workstations (SRV-FS1, CLI-WIN11, etc.):
         - Verifies DNS resolution against the active Domain Controllers
         - Joins each node to the domain via Add-Computer
         - Triggers a restart to commit domain membership

.PARAMETER Credential
    Specifies the administrative PSCredential object used to authenticate into each guest VM.

.PARAMETER ConfigPath
    Specifies the path to 'SK_Automation-VMConfig.json'. Defaults to the script directory.

.NOTES
    Pipeline Stage : Stage 3.2 (AD Topology & Fleet Domain Join)
    Transport      : Hyper-V VMBus (PowerShell Direct)
    Prerequisites  : Requires Stage 3.1 (Root DC promotion) to be completed and operational.
#>

<#
==================================================================================
STANDALONE STAGED EXECUTION (Testing outside TheOneRing orchestrator):

Make sure your terminal path is inside the scripts folder:
Set-Location -Path ".\SK-Automation-Scripts"

1. Store the local Administrator password configured in your Packer variables:
   $secPass = ConvertTo-SecureString "YourPackerAdminPassword" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Run the domain join and topology script using the credential object:
   .\05_SK_Automation-Host_NodeJoin.ps1 -Credential $cred
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
        $Credential = Get-Credential -UserName "Administrator" -Message "Enter Local/Domain Administrator Credential for Lab VMs (from packer.auto.pkrvars.hcl)"
    }
}

# ==============================================================================
# 2. CONFIGURATION & ROLE SEGREGATION
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
$ReplicaDC = $Config.VMs | Where-Object { $_.Role -eq "ReplicaDC" }
$Members = $Config.VMs | Where-Object { $_.Role -notin @("RootDC", "ReplicaDC") }

if (-not $RootDC) {
    Write-Error "CRITICAL: No VM with Role 'RootDC' found in $ResolvedJsonPath."
    exit 1
}

$DomainAdminUser = "$($RootDC.DomainName)\Administrator"
$DomainCred = New-Object System.Management.Automation.PSCredential($DomainAdminUser, $Credential.Password)
$PlainPassword = $Credential.GetNetworkCredential().Password

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.2] ACTIVE DIRECTORY TOPOLOGY & FLEET JOIN     " -ForegroundColor Cyan
Write-Host " Forest Root: $($RootDC.OSHostName) | Domain: $($RootDC.DomainName)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

$AllStagesSuccessful = $true

# ==============================================================================
# PART A: AD TOPOLOGY & DNS INFRASTRUCTURE (ON ROOT DC)
# ==============================================================================
Write-Host "`n>>> [Part A] Configuring Sites, Subnets & Reverse DNS on [$($RootDC.HyperVName)]..." -ForegroundColor Yellow

try {
    Invoke-Command -VMName $RootDC.HyperVName -Credential $DomainCred -ErrorAction Stop -ScriptBlock {
        $Data = $using:RootDC
        Import-Module ActiveDirectory, DNSServer -ErrorAction SilentlyContinue

        $ready = $false
        $retry = 0
        while (-not $ready -and $retry -lt 12) {
            $checkDC = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction SilentlyContinue
            if ((Get-Service -Name "ADWS" -ErrorAction SilentlyContinue).Status -eq 'Running' -and $checkDC) {
                $ready = $true
            }
            else {
                Start-Sleep -Seconds 5
                $retry++
            }
        }

        if (-not (Get-ADReplicationSite -Filter "Name -eq '$($Data.Site)'" -ErrorAction SilentlyContinue)) {
            Write-Host "  -> Creating AD Site: [$($Data.Site)]" -ForegroundColor Gray
            New-ADReplicationSite -Name $Data.Site | Out-Null
        }

        if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$($Data.Subnet)'" -ErrorAction SilentlyContinue)) {
            Write-Host "  -> Creating AD Subnet: [$($Data.Subnet)] bound to [$($Data.Site)]" -ForegroundColor Gray
            New-ADReplicationSubnet -Name $Data.Subnet -Site $Data.Site | Out-Null
        }

        try {
            $currentSite = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name
            if ($currentSite -ne $Data.Site) {
                Write-Host "  -> Relocating $env:COMPUTERNAME from [$currentSite] to [$($Data.Site)]..." -ForegroundColor Gray
                Move-ADDirectoryServer -Identity "$env:COMPUTERNAME" -Site "$($Data.Site)" -Confirm:$false
            }
            else {
                Write-Host "  -> Verified: $env:COMPUTERNAME already resides in [$currentSite]." -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Could not relocate site for $env:COMPUTERNAME: $($_.Exception.Message)"
        }

        $octets = $Data.IP.Split('.')[0..2]
        $revZone = "$($octets[2]).$($octets[1]).$($octets[0]).in-addr.arpa"
        $networkID = "$($octets -join '.')/24"

        if (-not (Get-DnsServerZone -Name $revZone -ErrorAction SilentlyContinue)) {
            Write-Host "  -> Provisioning Reverse DNS Zone: [$revZone]" -ForegroundColor Gray
            Add-DnsServerPrimaryZone -NetworkID $networkID -ReplicationScope Forest -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Write-Host "  -> [SUCCESS] Active Directory topology configured." -ForegroundColor Green
}
catch {
    Write-Host "  -> [FAILED] Error configuring topology on $($RootDC.HyperVName): $($_.Exception.Message.Trim())" -ForegroundColor Red
    $AllStagesSuccessful = $false
}

# ==============================================================================
# PART B: REPLICA DOMAIN CONTROLLER PROMOTION (SRV-DC2)
# ==============================================================================
if ($ReplicaDC) {
    Write-Host "`n>>> [Part B] Promoting Replica Domain Controller: [$($ReplicaDC.HyperVName)]..." -ForegroundColor Yellow

    try {
        Write-Host "  -> Installing AD DS binaries on $($ReplicaDC.OSHostName)..." -ForegroundColor Gray
        Invoke-Command -VMName $ReplicaDC.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell -IncludeManagementTools | Out-Null
        }

        Write-Host "  -> Executing Install-ADDSDomainController (Targeting $($ReplicaDC.DomainName))..." -ForegroundColor Gray
        $DSRMPass = $Credential.Password

        Invoke-Command -VMName $ReplicaDC.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $Data = $using:ReplicaDC
            $AdminUser = $using:DomainAdminUser
            $PlainPass = $using:PlainPassword
            $DSRM = $using:DSRMPass
            $RootIP = $using:RootDC.IP

            # Point DNS directly to Root DC from inside SRV-DC2
            $nic = (Get-NetAdapter | Where-Object Status -eq 'Up').InterfaceAlias
            Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses $RootIP

            # Wait for domain DNS resolution
            $resolved = $false
            $retryCount = 0
            while (-not $resolved -and $retryCount -lt 12) {
                if (Resolve-DnsName -Name $Data.DomainName -Type A -ErrorAction SilentlyContinue) {
                    $resolved = $true
                    Write-Host "  -> DNS resolution for [$($Data.DomainName)] verified." -ForegroundColor Green
                }
                else {
                    Write-Host "  -> Waiting for DNS discovery of $($Data.DomainName) ($retryCount/12)..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                    $retryCount++
                }
            }

            if (-not $resolved) {
                throw "SRV-DC2 could not resolve domain $($Data.DomainName) via Root DC ($RootIP)."
            }

            $domCred = New-Object System.Management.Automation.PSCredential($AdminUser, ($PlainPass | ConvertTo-SecureString -AsPlainText -Force))

            Import-Module ADDSDeployment

            $replicaParams = @{
                DomainName                    = $Data.DomainName
                InstallDns                    = $true
                SiteName                      = $Data.Site
                Credential                    = $domCred
                SafeModeAdministratorPassword = $DSRM
                Force                         = $true
                NoRebootOnCompletion          = $false
            }

            Install-ADDSDomainController @replicaParams
        }
    }
    catch {
        if ($_.Exception.Message -match "operation was canceled" -or $_.Exception.Message -match "transport connection") {
            Write-Host "  -> Replica promotion payload accepted; VM initiated automatic reboot." -ForegroundColor Green
        }
        else {
            Write-Warning "Replica DC dispatch notice: $($_.Exception.Message.Trim())"
        }
    }

    Write-Host "  -> [SUCCESS] Replica DC promotion initiated for $($ReplicaDC.OSHostName)." -ForegroundColor Green
}

# ==============================================================================
# PART C: MEMBER SERVER & CLIENT DOMAIN JOINS
# ==============================================================================
Write-Host "`n>>> [Part C] Joining Member Nodes to [$($RootDC.DomainName)]..." -ForegroundColor Yellow

foreach ($VM in $Members) {
    Write-Host "`nProcessing Node: [$($VM.HyperVName)] ($($VM.Role))" -ForegroundColor Cyan

    try {
        Invoke-Command -VMName $VM.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $Data = $using:VM
            $AdminUser = $using:DomainAdminUser
            $PlainPass = $using:PlainPassword

            $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
            if ($systemInfo.PartOfDomain -and $systemInfo.Domain -eq $Data.DomainName) {
                Write-Host "  -> [SKIP] $($Data.OSHostName) is already a domain member." -ForegroundColor Green
                return
            }

            $joinCred = New-Object System.Management.Automation.PSCredential($AdminUser, ($PlainPass | ConvertTo-SecureString -AsPlainText -Force))

            Write-Host "  -> Joining $($Data.OSHostName) to domain $($Data.DomainName)..." -ForegroundColor Yellow
            Add-Computer -DomainName $Data.DomainName -Credential $joinCred -Force -Restart
            Write-Host "  -> [JOINED] Machine restarted to commit domain membership." -ForegroundColor Green
        }
    }
    catch {
        if ($_.Exception.Message -match "operation was canceled" -or $_.Exception.Message -match "transport connection") {
            Write-Host "  -> [JOINED] Payload processed; machine initiated restart." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAILED] Error on $($VM.HyperVName): $($_.Exception.Message.Trim())" -ForegroundColor Red
            $AllStagesSuccessful = $false
        }
    }
}

# ==============================================================================
# 4. STAGE COMPLETION SUMMARY
# ==============================================================================
if ($AllStagesSuccessful) {
    Write-Host "`n==================================================================" -ForegroundColor Cyan
    Write-Host " PIPELINE MILESTONE STATUS: STAGE 3.2 COMPLETE!                                                   " -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "[STAGE 1 COMPLETE]   Packer golden .VHDX created and exported."     -ForegroundColor Green
    Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
    Write-Host "[STAGE 2.2 COMPLETE] VM PS Direct / VMBus Testing."                 -ForegroundColor Green
    Write-Host "[STAGE 2.3 COMPLETE] VM Identity & Network Hydration Deployed."     -ForegroundColor Green
    Write-Host "[STAGE 3.1 COMPLETE] Forest Root DC Promoted & DNS Initialized."    -ForegroundColor Green
    Write-Host "[STAGE 3.2 COMPLETE] Topology Configured, Replica DC & Nodes Joined." -ForegroundColor Green
    Write-Host "[STAGE 3.3 STARTING] Organizational Units & User Hydration."        -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}
else {
    Write-Warning "`n[STAGE 3.2 WARNING] One or more nodes failed domain integration or topology setup."
    Write-Warning "Verify DNS resolution, Root DC status, and administrative credentials."
}

<#
### Key Technical decisions behind this Code! 

1. Role-Segregated Infrastructure Orchestration:
   - Evaluates roles dynamically from SK_Automation-VMConfig.json, separating the Forest Root, 
     Replica Domain Controllers, and  Member Servers/Clients into distinct execution paths.

2. Out-of-Band Double-Hop Mitigation:
   - Generates authentic domain credentials directly inside the target VM's session boundary 
     over PowerShell Direct, eliminating Kerberos double-hop delegation failures.

3. Automated Site & Subnet Boundary Definition:
   - Provisions Active Directory Sites and Services objects (Site, Subnet, and DC Site Relocation) 
     to ensure correct Kerberos ticket issuing, LDAP referral boundaries, and replication topology.

4. Reverse Lookup Zone Hydration:
   - Automatically computes and registers the Class C Reverse DNS lookup zone (in-addr.arpa) 
     with forest-wide replication scope, preventing PTR record lookup timeouts across enterprise tools.

5. Idempotent Join Execution:
   - Uses CIM instance queries (Win32_ComputerSystem.PartOfDomain) to evaluate current join 
     status, allowing safe re-runs without throwing Active Directory computer account conflicts.

#>
