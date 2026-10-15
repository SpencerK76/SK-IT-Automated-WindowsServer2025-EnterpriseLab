<#
.SYNOPSIS
    Automated WinRM HTTPS and Remote Management Bootstrap for Windows Server 2025.
    Script: Win2025 bootstrap-winrm-https.ps1
.DESCRIPTION
    Initializes secure remote management immediately following unattended setup so 
    Packer can attach over WinRM during golden image generation:
    
    1. Sets active network profiles to Private to relax initial firewall drops.
    2. Flags the local Administrator account password to never expire.
    3. Generates a self-signed TLS certificate bound to localhost and the node hostname.
    4. Flushes default WSMan listeners and registers an encrypted HTTPS listener on TCP 5986.
    5. Enables Basic authentication and sets LocalAccountTokenFilterPolicy to bypass 
       remote UAC restrictions for local admin accounts.
    6. Creates an explicit Windows Defender Firewall inbound rule for TCP 5986 across all profiles.
    7. Restarts the WinRM service to finalize the configuration.
.NOTES
    Transport : WinRM over HTTPS (TCP Port 5986)
    Target OS : Windows Server 2025
    Context   : Executed via OEMDRV / Autounattend.xml FirstLogonCommands
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# ==============================================================================
# 1. NETWORK PROFILE CONFIGURATION
# ==============================================================================
# Forces active network connection profiles to Private to prevent default Public firewall blocks
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

# ==============================================================================
# 2. LOCAL IDENTITY HARDENING
# ==============================================================================
# Prevents the local Administrator account password from expiring during build operations
Set-LocalUser -Name "Administrator" -PasswordNeverExpires $true

# ==============================================================================
# 3. TLS CERTIFICATE GENERATION
# ==============================================================================
# Generates a self-signed certificate bound to localhost and the local hostname for port 5986
$Cert = New-SelfSignedCertificate -CertStoreLocation Cert:\LocalMachine\My -DnsName "localhost", $env:COMPUTERNAME
$Thumbprint = $Cert.Thumbprint

# ==============================================================================
# 4. WSMAN SERVICE INITIALIZATION & CLEANUP
# ==============================================================================
# Enables PowerShell Remoting and strips default listeners to ensure a clean slate
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Get-ChildItem -Path WSMan:\Localhost\listener | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ==============================================================================
# 5. SECURE HTTPS LISTENER REGISTRATION
# ==============================================================================
# Binds the new HTTPS listener to all IP interfaces using the generated certificate thumbprint
New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $Thumbprint -Force | Out-Null

# ==============================================================================
# 6. SERVICE AUTHENTICATION & REMOTE UAC BYPASS
# ==============================================================================
# Enables Basic authentication for the WinRM communicator and disables remote UAC filtering
# Disabling UAC restrictions for remote local admin connections ensures Packer does not receive an Access Denied error
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force
Set-ItemProperty -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -Force

# ==============================================================================
# 7. FIREWALL EXCEPTION CONFIGURATION
# ==============================================================================
# Cleans existing rules if present and explicitly permits inbound TCP 5986 across all profiles
Remove-NetFirewallRule -Name "WinRM-HTTPS" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "WinRM-HTTPS" `
                   -DisplayName "WinRM HTTPS (Packer Provisioning)" `
                   -Direction Inbound `
                   -LocalPort 5986 `
                   -Protocol TCP `
                   -Action Allow `
                   -Profile Any | Out-Null

# ==============================================================================
# 8. SERVICE RESTART & COMMIT
# ==============================================================================
# Restarts the WinRM service to commit listener and security policy changes
Restart-Service -Name WinRM