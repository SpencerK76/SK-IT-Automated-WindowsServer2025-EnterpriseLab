<#
.SYNOPSIS
    Script: 06_SK_Automation-Host_CustomConfigs.ps1
    Stage 3.3 - Core Services (DHCP), Department OUs, Users & Panther Sanitization
    
.DESCRIPTION
    Consumes SK_Automomation-VMConfig.json and finalizes the deployment environment:
      1. Installs, authorizes, and configures an AD-integrated DHCP Server and upstream DNS forwarders on Root DC.
      2. Creates department-level OUs (Accounts, IT Support, Sales, Admins) directly off domain root.
      3. Seeds matching security groups inside each of those department OU.
      4. Seeds  users and adds them to their department OUs and groups.
      5. Sweeps all virtual machines via PowerShell Direct to purge cached unattend.xml 
         files from C:\Windows\Panther to prevent credential leakage
#>

<#
==================================================================================
STANDALONE SCRIPT EXECUTIONS (Outside the OneRing Orchestrator - execute each script in sequence):

1. Execute these credential variables first in your VSC PowerShell console - make sure you enter the correct password you set in Packer for the Administrator account:
   Also make sure you are running theses scripts from PS:\Automated-WindowsServer2025-EnterpriseLab\SK-Automation-Scripts\
   
   $secPass = ConvertTo-SecureString "Enter the password you put enter in the auto.packer.pkrvars.hcl" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Then execute the script passing the credential object:
   .\06_SK_Automation-Host_CustomConfigs.ps1 -Credential $cred
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
# 2. CONFIGURATION  & NODE RESOLUTION
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
    $RootDC = $Config.VMs | Where-Object { $_.Role -match "DC" } | Select-Object -First 1
}

if (-not $RootDC) {
    Write-Error "CRITICAL: Could not resolve Root Domain Controller from $ResolvedJsonPath."
    exit 1
}

$DomainAdminUser = "$($RootDC.DomainName)\Administrator"
$DomainCred = New-Object System.Management.Automation.PSCredential($DomainAdminUser, $Credential.Password)
$PlainPassword = $Credential.GetNetworkCredential().Password

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [STAGE 3.3] CORE SERVICES, USERS & ARTIFACT PURGE      " -ForegroundColor Cyan
Write-Host " Target Forest Root: $($RootDC.OSHostName) ($($RootDC.DomainName))" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ==============================================================================
# PART A: DHCP ROLE, SCOPE & DNS UPSTREAM FORWARDERS (ON ROOT DC)
# ==============================================================================
Write-Host "`n>>> [Part A] Configuring DHCP & DNS Forwarders on [$($RootDC.HyperVName)]..." -ForegroundColor Yellow

Invoke-Command -VMName $RootDC.HyperVName -Credential $DomainCred -ScriptBlock {
    $Data = $using:RootDC

    $dhcpFeature = Get-WindowsFeature -Name DHCP
    if (-not $dhcpFeature.Installed) {
        Write-Host "  -> Installing DHCP Server role..." -ForegroundColor Gray
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    }

    $moduleDir = "$env:windir\System32\WindowsPowerShell\v1.0\Modules\DhcpServer"
    $enGbDir = Join-Path $moduleDir "en-GB"
    $enDir = Join-Path $moduleDir "en"

    if ((Test-Path $enGbDir) -and (-not (Test-Path $enDir))) {
        try {
            Copy-Item -Path $enGbDir -Destination $enDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }

    $authCheck = Get-DhcpServerInDC -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $Data.IP }
    if (-not $authCheck) {
        Write-Host "  -> Authorizing DHCP Server [$($Data.OSHostName).$($Data.DomainName)] in Active Directory..." -ForegroundColor Gray
        Add-DhcpServerInDC -DnsName "$($Data.OSHostName).$($Data.DomainName)" -IPAddress $Data.IP -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "  -> Verified: DHCP server is already authorized in AD." -ForegroundColor Gray
    }

    $ScopeName = "$($Data.Site) Client Range"
    $NetworkPrefix = ($Data.IP.Split('.')[0..2] -join '.')
    $ScopeID = "$NetworkPrefix.0"
    $StartRange = "$NetworkPrefix.100"
    $EndRange = "$NetworkPrefix.200"
    $SubnetMask = "255.255.255.0"
    $Gateway = $Data.Gateway

    $existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId -eq $ScopeID }
    if (-not $existingScope) {
        Write-Host "  -> Provisioning Scope: [$ScopeName] ($StartRange - $EndRange)..." -ForegroundColor Gray
        Add-DhcpServerv4Scope -Name $ScopeName `
            -StartRange $StartRange `
            -EndRange $EndRange `
            -SubnetMask $SubnetMask `
            -State Active -ErrorAction SilentlyContinue | Out-Null

        Set-DhcpServerv4OptionValue -ScopeId $ScopeID `
            -DnsDomain $Data.DomainName `
            -DnsServer $Data.IP `
            -Router $Gateway -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  -> DHCP Scope and Option values configured successfully." -ForegroundColor Green
    }
    else {
        Write-Host "  -> Verified: Scope [$ScopeName] already exists." -ForegroundColor Gray
    }

    # 5. Upstream DNS Forwarders Configuration
    Import-Module DNSServer -ErrorAction SilentlyContinue
    $UpstreamDNS = @("8.8.8.8", "1.1.1.1")
    Write-Host "  -> Configuring DNS Upstream Forwarders ($($UpstreamDNS -join ', '))..." -ForegroundColor Gray
    Set-DnsServerForwarder -IPAddress $UpstreamDNS -ErrorAction SilentlyContinue
    Write-Host "  -> DNS Upstream Forwarders successfully applied." -ForegroundColor Green
}

# ==============================================================================
# PART B: CORP_OU HIERARCHY, CORP_ACCOUNTS & USER SEEDING (ON ROOT DC)
# ==============================================================================
Write-Host "`n>>> [Part B] Provisioning Corp Hierarchy, Accounts & Groups on [$($RootDC.HyperVName)]..." -ForegroundColor Yellow

Invoke-Command -VMName $RootDC.HyperVName -Credential $DomainCred -ScriptBlock {
    $UserSec = $using:PlainPassword | ConvertTo-SecureString -AsPlainText -Force

    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    $domainDN = (Get-ADDomain).DistinguishedName
    $domainName = (Get-ADDomain).DNSRoot

    # 1. Root Hierarchy OU (Corp_OU)
    $corpOuDN = "OU=Corp_OU,$domainDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Corp_OU'" -SearchBase $domainDN -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "Corp_OU" -Path $domainDN -ProtectedFromAccidentalDeletion $false | Out-Null
        Write-Host "  -> Created Root Hierarchy OU: $corpOuDN" -ForegroundColor Gray
    }
    else {
        Write-Host "  -> Verified Root Hierarchy OU: $corpOuDN" -ForegroundColor Gray
    }

    # 2. Dedicated OU for Security Groups
    $groupsOuDN = "OU=Security_Groups,$corpOuDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Security_Groups'" -SearchBase $corpOuDN -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "Security_Groups" -Path $corpOuDN -ProtectedFromAccidentalDeletion $false | Out-Null
        Write-Host "  -> Created Dedicated Groups OU: $groupsOuDN" -ForegroundColor Gray
    }
    else {
        Write-Host "  -> Verified Dedicated Groups OU: $groupsOuDN" -ForegroundColor Gray
    }

    $departments = @("Accounts", "IT Support", "Sales", "Admins")

    # 3. Department OUs & Security Groups
    foreach ($dept in $departments) {
        $deptOuDN = "OU=$dept,$corpOuDN"

        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $corpOuDN -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $dept -Path $corpOuDN -ProtectedFromAccidentalDeletion $false | Out-Null
            Write-Host "  -> Created Department OU: $deptOuDN" -ForegroundColor Gray
        }
        else {
            Write-Host "  -> Verified Department OU: $deptOuDN" -ForegroundColor Gray
        }

        if (-not (Get-ADGroup -Filter "Name -eq '$dept'" -SearchBase $groupsOuDN -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $dept -GroupScope Global -GroupCategory Security -Path $groupsOuDN | Out-Null
            Write-Host "  -> Created Security Group: $dept in [$groupsOuDN]" -ForegroundColor Gray
        }
        else {
            Write-Host "  -> Verified Security Group: $dept in [$groupsOuDN]" -ForegroundColor Gray
        }
    }

    $UsersTemplate = @(
        @{ GivenName = 'John'; Surname = 'Smith'; Department = 'Accounts'; Title = 'Technician' }
        @{ GivenName = 'Paul'; Surname = 'Jones'; Department = 'IT Support'; Title = 'Engineer' }
        @{ GivenName = 'Sharon'; Surname = 'Brown'; Department = 'Sales'; Title = 'Rep' }
        @{ GivenName = 'Sam'; Surname = 'Clark'; Department = 'Admins'; Title = 'Clerk' }
        @{ GivenName = 'Rachel'; Surname = 'Davis'; Department = 'Accounts'; Title = 'Coordinator' }
        @{ GivenName = 'Spencer'; Surname = 'Evans'; Department = 'IT Support'; Title = 'Technician' }
        @{ GivenName = 'David'; Surname = 'Baker'; Department = 'Sales'; Title = 'Rep' }
        @{ GivenName = 'Peter'; Surname = 'Allen'; Department = 'Admins'; Title = 'Clerk' }
        @{ GivenName = 'Jason'; Surname = 'Young'; Department = 'IT Support'; Title = 'Engineer' }
        @{ GivenName = 'Pat'; Surname = 'Price'; Department = 'Accounts'; Title = 'Assistant' }
    )

    # 4. Provision Users
    $i = 1
    foreach ($u in $UsersTemplate) {

        $sam = $u.GivenName.ToLower()
        $upn = "$sam@$domainName"

        $display = "$($u.GivenName) $($u.Surname)"
        $phone = ('01234 {0:000000}' -f (100000 + $i))

        $userTargetOU = "OU=$($u.Department),$corpOuDN"

        $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADUser -Name $display `
                -SamAccountName $sam `
                -UserPrincipalName $upn `
                -GivenName $u.GivenName `
                -Surname $u.Surname `
                -DisplayName $display `
                -Path $userTargetOU `
                -Department $u.Department `
                -Title $u.Title `
                -Description "Automated Lab User" `
                -Office "HQ" `
                -OfficePhone $phone `
                -EmailAddress $upn `
                -AccountPassword $UserSec `
                -ChangePasswordAtLogon $false `
                -PasswordNeverExpires $true `
                -Enabled $true | Out-Null

            Add-ADGroupMember -Identity $u.Department -Members $sam -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  -> Provisioned: $display [$sam] into [$userTargetOU] -> Member of Group [$($u.Department)]" -ForegroundColor Green
        }
        else {
            Add-ADGroupMember -Identity $u.Department -Members $sam -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  -> User [$sam] exists; verified membership in Group [$($u.Department)]" -ForegroundColor Gray
        }
        $i++
    }
}

Write-Host "  -> [SUCCESS] Department OUs, groups, and template users live." -ForegroundColor Green


# ==============================================================================
# PART C: FLEET-WIDE PANTHER CREDENTIAL SANITIZATION
# ==============================================================================
Write-Host "`n>>> [Part C] Sweeping Fleet to Purge Cached Setup Credentials..." -ForegroundColor Yellow

$AllVMs = $Config.VMs

foreach ($VM in $AllVMs) {
    Write-Host "Sanitizing [$($VM.HyperVName)]..." -NoNewline -ForegroundColor White
    try {
        Invoke-Command -VMName $VM.HyperVName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $pantherFiles = @(
                "C:\Windows\Panther\unattend.xml",
                "C:\Windows\Panther\Autounattend.xml",
                "C:\Windows\Panther\UnattendGC\unattend.xml"
            )
            $purged = 0
            foreach ($file in $pantherFiles) {
                if (Test-Path $file) {
                    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
                    $purged++
                }
            }
            return $purged
        } | Out-Null
        Write-Host " [CLEANED]" -ForegroundColor Green
    }
    catch {
        Write-Host " [SKIPPED / UNREACHABLE]" -ForegroundColor Yellow
    }
}

# ==============================================================================
# 4. STAGE COMPLETION SUMMARY & CONGRATULATIONS BANNER
# ==============================================================================
Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " The SK-IT Windows Server 2025 Automation Project is complete!     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "[STAGE 1 COMPLETE]   Packer golden .VHDX created and exported."     -ForegroundColor Green
Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
Write-Host "[STAGE 2.2 COMPLETE] VM PS Direct / VMBus Testing."                 -ForegroundColor Green
Write-Host "[STAGE 2.3 COMPLETE] VM Identity & Network Hydration Deployed."     -ForegroundColor Green
Write-Host "[STAGE 3.1 COMPLETE] Forest Root DC Promoted & DNS Initialized."    -ForegroundColor Green
Write-Host "[STAGE 3.2 COMPLETE] Topology Configured, Replica DC & Nodes Joined." -ForegroundColor Green
Write-Host "[STAGE 3.3 COMPLETE] Core Services, OUs/Users Seeded, Panther Purged." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan

Write-Host "`n========================================================================================================" -ForegroundColor Green
Write-Host " ******************************************** CONGRATULATIONS ********************************************" -ForegroundColor Cyan
Write-Host " You now have a fully isolated Windows Server 2025 Domain, with configured Member Servers, Clients and Users." -ForegroundColor Green
Write-Host " I hope this automation project has helped you, and I wish you the very best in your IT journey!"      -ForegroundColor Green
Write-Host " Please feel free to reach out if you have any questions or need further assistance!"                   -ForegroundColor Green
Write-Host " Email: Spencer@sk-it.co.uk | Please feel free to leave a comment on Linkedin if this helped you out" -ForegroundColor Green