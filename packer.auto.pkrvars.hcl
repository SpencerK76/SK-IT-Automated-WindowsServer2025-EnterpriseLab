# =========================================================================================
# SCRIPT: packer.auto.pkrvars.hcl
# PURPOSE: Supplies runtime variable values and sensitive credentials to the Packer pipeline.
# TECHNOLOGY: HashiCorp Packer (v1.10.0+), Windows Server 2025 Eval, Windows 11 Enterprise
# SECURITY: Auto-loaded by Packer (*.auto.pkrvars.hcl). Exclude from public git commits (.gitignore).
# =========================================================================================

# ==============================================================================
# SECTION 1: CENTRAL ADMINISTRATIVE CREDENTIALS
# ==============================================================================
# The credentials declared here serve as the root identity across the entire pipeline:
#   1. Injected into Autounattend.xml for the local Administrator account
#   2. Used by Packer for the WinRM HTTPS communicator
#   3. Passed downstream via PowerShell Direct (VMBus) for VM identity hydration
#   4. Assigned as the Active Directory DSRM SafeMode Administrator password
#   5. Used to authenticate post-promotion as DOMAIN\Administrator
# ==============================================================================
admin_username = "Administrator"
admin_password = "ENTER YOUR ADMIN PASSWORD"

# ==============================================================================
# SECTION 2: INSTALLATION MEDIA INTEGRITY (SHA-256 CHECKSUMS)
# ==============================================================================
# Cryptographic hashes validating that the local ISO files match Microsoft evaluation media.
# Must include the 'sha256:' prefix.
# ==============================================================================

# Windows Server 2025 Evaluation ISO Checksum (ADD YOUR CHECKSUM)
iso_checksum       = "sha256:7B052573BA7894C9924E3E87BA732CCD354D18CB75A883EFA9B900EA125BFD51"
#Enter your checksum here for Windows Server 2025

# Windows 11 Enterprise Evaluation ISO Checksum (ADD YOUR CHECKSUM)
win11_iso_checksum = "sha256:6E861B93EB9501182AD2E4DC3FA8C411AFB6D7ED86A8CCBE37CA67D75470B95F"
#Enter your checksum here for Windows 11

git check-ignore -v "ISOs\WinServer2025Eval.iso"