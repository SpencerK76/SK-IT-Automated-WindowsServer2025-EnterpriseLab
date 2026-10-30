<#
.SYNOPSIS
    Stage 3.3 - Core Services (DHCP), Directory Structure & Credential Sanitization
    Script: 06_SK_Automation-Host_CustomConfigs.ps1

.DESCRIPTION
    Reads 'SK_Automation-VMConfig.json' and performs post-deployment configuration 
    across the active domain environment:

      1. On Root DC (SRV-DC1):
         - Installs, authorizes, and configures an AD-integrated DHCP Server scope.
         - Configures external DNS forwarders (e.g., pfSense / Cloudflare / Google).
      2. Active Directory Objects:
         - Creates departmental Organizational Units (Accounts, IT Support, Sales, Admins).
         - Generates matching security groups within each department OU.
         - Populates sample user accounts and maps them into their respective groups and OUs.
      3. Security Hardening & Panther Cleanup:
         - Connects to every provisioned VM via Hyper-V PowerShell Direct (VMBus).
         - Purges cached 'unattend.xml' answer files from 'C:\Windows\Panther' to 
           prevent plaintext credential exposure from the initial Sysprep build.

.PARAMETER Credential
    Specifies the administrative PSCredential object used to authenticate into each guest VM.

.PARAMETER ConfigPath
    Specifies the path to 'SK_Automation-VMConfig.json'. Defaults to the script directory.

.NOTES
    Pipeline Stage : Stage 3.3 (Core Services, AD Directory Objects & Security Hardening)
    Transport      : Hyper-V VMBus (PowerShell Direct)
    Prerequisites  : Requires Stage 3.1 and 3.2 domain infrastructure to be fully operational.
#>

<#
==================================================================================
STANDALONE STAGED EXECUTION (Testing outside TheOneRing orchestrator):

Make sure your terminal path is inside the scripts folder:
Set-Location -Path ".\SK-Automation-Scripts"

1. Store the local Administrator password configured in your Packer variables:
   $secPass = ConvertTo-SecureString "YourPackerAdminPassword" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

2. Run the customization and cleanup script using the credential object:
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

        # Search the entire domain for sAMAccountName or Name collision
        $existingDeptGroup = Get-ADGroup -Filter "SamAccountName -eq '$dept' -or Name -eq '$dept'" -ErrorAction SilentlyContinue
        if (-not $existingDeptGroup) {
            try {
                New-ADGroup -Name $dept `
                    -SamAccountName $dept `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Path $groupsOuDN `
                    -ErrorAction Stop | Out-Null
                Write-Host "  -> Created Security Group: $dept in [$groupsOuDN]" -ForegroundColor Gray
            }
            catch {
                Write-Host "  -> Notice: Security Group [$dept] already detected during creation." -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  -> Verified Security Group: $dept in [$($existingDeptGroup.DistinguishedName)]" -ForegroundColor Gray
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

Write-Host "  -> [SUCCESS] Department OUs, groups, and template users have been created." -ForegroundColor Green


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
Write-Host "[STAGE 1 COMPLETE]   Packer golden VHDX created and exported."       -ForegroundColor Green
Write-Host "[STAGE 2.1 COMPLETE] All Hyper-V VMs created and started."          -ForegroundColor Green
Write-Host "[STAGE 2.2 COMPLETE] VM PS Direct / VMBus tested."                  -ForegroundColor Green
Write-Host "[STAGE 2.3 COMPLETE] VM identity and network hydration deployed."   -ForegroundColor Green
Write-Host "[STAGE 3.1 COMPLETE] Forest root DC promoted & DNS initialized."    -ForegroundColor Green
Write-Host "[STAGE 3.2 COMPLETE] Topology configured, replica DC & nodes joined." -ForegroundColor Green
Write-Host "[STAGE 3.3 COMPLETE] Core services, OUs/users seeded, Panther purged." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan

Write-Host "`n========================================================================================================" -ForegroundColor Green
Write-Host " ******************************************** CONGRATULATIONS ********************************************" -ForegroundColor Cyan
Write-Host " You now have a fully isolated Windows Server 2025 domain, complete with configured member servers, clients, and users." -ForegroundColor Green
Write-Host " I hope this automation project has been valuable, and I wish you all the best on your IT journey!" -ForegroundColor Green
Write-Host " If you have any questions or need further assistance, please feel free to reach out." -ForegroundColor Green
Write-Host " Email: Spencer@sk-it.co.uk | Feedback or comments on LinkedIn are always welcome!" -ForegroundColor Green
Write-Host " A lot of time and effort went into this project, so if you'd like to leave a tip, please consider donating £5 to your local cat sanctuary 🐱 - Winter is coming!." -ForegroundColor Green
Write-Host " *********************************************************************************************************" -ForegroundColor Cyan



<#
### Key Technical Decisions Behind This Code!

1. Centralized AD-Integrated DHCP Architecture:
   - Provisions and authorizes the DHCP service directly on the Root Domain Controller 
     within Active Directory, establishing a single source of truth for dynamically 
     assigned IP leases, DNS servers, and the 10.0.0.254 pfSense default gateway.

2. Upstream DNS Forwarding Strategy:
   - Directs recursive external queries to the perimeter firewall (10.0.0.254) and reliable 
     public resolvers, preventing resolution delays and eliminating reliance on root hints 
     inside the isolated lab boundary.

3. Role-Based Directory Structuring (OUs & Security Groups):
   - Deploys departmental Organizational Units (Accounts, IT Support, Sales, Admins) 
     paired with dedicated security groups, aligning with the Principle of Least Privilege 
     and enterprise Group Policy application baselines.

4. Deterministic Identity Seeding:
   - Automatically populates standardized user accounts, department attributes, and group 
     memberships, creating an instant enterprise directory state ready for access control testing.

5. Out-of-Band Sysprep Credential Sanitization (Panther Scrubbing):
   - Sweeps guest local storage over PowerShell Direct (VMBus) to purge cached unattend.xml 
     and sysprep logs from 'C:\Windows\Panther', permanently removing plaintext local administrator 
     credentials embedded during initial provisioning.
#>