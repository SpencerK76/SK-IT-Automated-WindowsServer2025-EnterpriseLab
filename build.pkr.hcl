# =========================================================================================
# SCRIPT: build.pkr.hcl
# PURPOSE: To create Sysprepped VHD's that PS Direct can then use to create a Lab in Hyper-v
# TECHNOLOGY: HashiCorp Packer (v1.16.0), Windows Server 2025 evaluation ISO (WinServer2025Eval)
# DESCRIPTION: Build an automated Packer workflow that produces a Golden VHD image, fully prepared
#       
# =========================================================================================

# ==============================================================================
# SECTION 1: PACKER ENGINE & PLUGIN SETUP
# ==============================================================================
# This section tells Packer what minimum version it needs to run this project
# the official Hyper-V plugin from GitHub so Packer knows how to talk to Hyper-V.
packer {
  required_version = ">= 1.10.0"
  required_plugins {
    hyperv = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

# ==============================================================================
# SECTION 2: BUILDER SOURCE 1 — WINDOWS SERVER 2025
# ==============================================================================
# This block builds the Windows Server 2025 golden image.
source "hyperv-iso" "win2025" {

  # --- Virtual Machine Identity & Sizing ---
  vm_name               = "Win2025-GoldenImage-Build" # The temporary name shown inside Hyper-V Manager for the individiual VMs
  generation            = 2                           # Gen 2 uses UEFI firmware instead of old BIOS
  cpus                  = 2                           # 2 CPU cores are used
  memory                = 4096                        # Allocates 4 GB of RAM 
  enable_dynamic_memory = false                       # Static RAM ensures the installer never runs short of memory
  enable_secure_boot    = false                       # Kept off here so custom install files load without signature blocks
  mac_address           = "00155D010203"              # A unique static MAC address to avoid network IP clashes

  # --- Virtual Hard Disk (Storage) ---
  disk_size             = 61440                       # 60 GB vDisk size - change this for default WinSer2025 VM vDisk size (note each OS min req!)
  disk_block_size       = 1                           # 1 MB block size creates a smaller, more storage-efficient VHDX

  # --- Installation Media (ISO) & Network ---  (change values in variables.pkr.hcl, not here)
  switch_name           = var.switch_name             # Name of your virtual switch from variables.pkr.hcl
  iso_url               = var.iso_url                 # Path to your Windows Server 2025 ISO file
  iso_checksum          = var.iso_checksum            # SHA-256 hash verifying the ISO is legitimate
  #============================================================================================  
  #============================================================================================
  # --- Ephemeral Virtual CD (OEMDRV) ---
  # Packer builds a small, temporary virtual CD drive in memory containing two files:
  # 1. Autounattend.pkrtpl.hcl (Autounattend.xml): Automatically answers all Windows install prompts for automated install
  # 2. bootstrap-winrm-https.ps1: The script that sets up secure remote PowerShell (WinRM) at first boot to allow PS to inject the 1-6 scripts.
  
  # Labeling it "OEMDRV" makes Windows find this setup file automatically.
  cd_content = {
    "Autounattend.xml"          = templatefile("${path.root}/templates/Autounattend.pkrtpl.hcl", {
      admin_username = var.admin_username #  Placeholder variables: Go to packer.auto.pkrvars.hcl and add your Windows Administrator Credentials
      admin_password = var.admin_password #  You only have to enter your credentials once. 
    })
    "bootstrap-winrm-https.ps1" = file("${path.root}/scripts/bootstrap-winrm-https.ps1") # the bootstrap files are run after Windows Starts, before Sysprep!
  }
  cd_label              = "OEMDRV" #reates a temporary ISO containing Autounattend.xml (rendered with injected credentials) and the WinRM bootstrap script.

  # --- Boot Keystroke Sequence ---  This is the very first step of the automation. process!
  # When UEFI starts, it shows "Press any key to boot from CD or DVD".
  # Packer waits 1 second, then presses the spacebar twice so the installer launches. 
  # Has to be kept at 1s, or Windows Setup will not load correctly
  boot_wait             = "1s"
  boot_command          = [
    "<spacebar><spacebar>"
  ]
  #============================================================================================
  #============================================================================================
  # --- Secure Communicator (WinRM over HTTPS) ---
  # How Packer connects to the VM after Windows installs:
  # It uses an encrypted HTTPS connection on port 5986 using your admin login.
  # "insecure = true" allows connection using the self-signed security certificate created on the VM.
  communicator          = "winrm"
  winrm_username        = var.admin_username
  winrm_password        = var.admin_password
  winrm_port            = 5986
  winrm_use_ssl         = true
  winrm_insecure        = true
  winrm_timeout         = "30m"
  #============================================================================================
  #============================================================================================
  # --- Sealing & Final Shutdown (Sysprep) for Server 2025 ---
  # After all tasks finish, Packer runs Windows Sysprep.
  # Sysprep strips unique machine IDs, optimizes the disk for cloning, and powers down the VM.
  # The finalized master hard drive is saved directly to your server output folder.
  shutdown_command      = "powershell -Command \"Start-Sleep -Seconds 10; & $${env:SystemRoot}\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown /mode:vm\""
  shutdown_timeout      = "20m"
  output_directory      = var.output_directory
}
#============================================================================================

# ==============================================================================
# SECTION 3: BUILDER SOURCE 2 — WINDOWS 11 ENTERPRISE
# ==============================================================================
# This block builds the Windows 11 Enterprise golden client image.
# Notice the strict hardware enforcement required specifically for Windows 11.
source "hyperv-iso" "win11" {

  # --- Virtual Machine Identity & Sizing ---
  vm_name               = "Win11-GoldenImage-Build" # Temporary VM name inside Hyper-V Manager during build
  generation            = 2                          # Gen 2 uses UEFI firmware (enforced by Windows 11)
  cpus                  = 2                          # Windows 11 enforces a strict minimum of 2 vCPUs
  memory                = 4096                       # Windows 11 enforces a strict minimum of 4 GB RAM
  enable_dynamic_memory = false                      # Static RAM ensures the installer never runs short of memory during setup

  # --- Windows 11 Mandatory Hardware Security ---
  # Windows 11 will refuse to install unless both Secure Boot and a TPM 2.0 chip are present.
  enable_secure_boot    = true                       # Enforces UEFI Secure Boot compliance
  secure_boot_template  = "MicrosoftWindows"         # Standard Microsoft UEFI certificate authority
  enable_tpm            = true                       # Enables the virtual TPM 2.0 chip inside Hyper-V
  mac_address           = "00155D010204"             # A unique static MAC address to avoid network IP clashes

  # --- Virtual Hard Disk (Storage) ---
  disk_size             = 61440                      # 60 GB vDisk size - change this to set the default client disk size
  disk_block_size       = 1                          # 1 MB block size creates a smaller, more storage-efficient VHDX

  # --- Installation Media (ISO) & Network --- (change values in variables.pkr.hcl, not here)
  switch_name           = var.switch_name            # Name of your virtual switch from variables.pkr.hcl
  iso_url               = var.win11_iso_url          # Path to your Windows 11 ISO file
  iso_checksum          = var.win11_iso_checksum     # SHA-256 hash verifying the ISO is legitimate
  #============================================================================================  
  #============================================================================================
  # --- Ephemeral Virtual CD (OEMDRV) ---
  # Packer builds a temporary virtual CD drive in memory containing two files:
  # 1. Autounattend.xml: The client answer file rendered with your credentials
  # 2. bootstrap-winrm-https.ps1: The script setting up WinRM on first boot before Sysprep
  #
  # NOTE ON WINDOWS 11 CD ATTACHMENT:
  # Windows 11 receives its own tailored answer file (Autounattend-Win11.pkrtpl.hcl) and its
  # own bootstrap script (bootstrap-win11.ps1). While Server 2025 finds OEMDRV automatically,
  # Windows 11 media can occasionally ignore the virtual volume during WinPE startup.
  # We still mount it as OEMDRV, but use the specialized boot sequence below to guarantee detection.

  cd_content = {
    "Autounattend.xml"          = templatefile("${path.root}/templates/Autounattend-Win11.pkrtpl.hcl", {
      admin_username = var.admin_username # Pulls credentials from packer.auto.pkrvars.hcl
      admin_password = var.admin_password # Entered once and reused throughout the deployment
    })
    "bootstrap-winrm-https.ps1" = file("${path.root}/scripts/bootstrap-win11.ps1")
  }
  cd_label              = "OEMDRV"                   # Label used by Windows Setup to detect automated answer files

  # --- Boot Keystroke Sequence & Setup Bypass ---
  # The Windows 11 installer requires a tailored sequence compared to Server 2025:
  # When WinPE starts, it often ignores automatic answer file, from what I have witnessed and halts at the UI.
  # We clear the initial UEFI prompt, wait for WinPE to load, open Command Prompt (Shift+F10),
  # terminate the stalled setup.exe process, and force-restart it using a dynamic drive-letter
  # scan (C through H) to locate the answer file regardless of which drive letter Hyper-V assigns.
  
  boot_wait             = "1s"
  boot_command          = [
    # 1. Clear UEFI "Press any key to boot" prompt
    "<spacebar><spacebar><spacebar>",

    # 2. Wait for WinPE environment to load into memory
    "<wait10s>",

    # 3. Open Command Prompt inside WinPE
    "<shift><f10>",
    "<wait2s>",

    # 4. Modern process kill and dynamic drive search to force unattended setup
    "taskkill /f /im setup.exe<enter>",
    "<wait1s>",
    "cmd /c \"for %d in (C D E F G H) do if exist %d:\\Autounattend-Win11.pkrtpl.hcl (setup.exe /unattend:%d:\\Autounattend-Win11.pkrtpl.hcl)\"<enter>"
  ]
  #============================================================================================
  

  #============================================================================================
  # --- Secure Communicator (WinRM over HTTPS) ---
  # How Packer connects to the VM after Windows 11 installs:
  # Uses an encrypted HTTPS connection on port 5986 with your administrator login.
  # "insecure = true" permits the self-signed certificate generated during first boot.
  communicator          = "winrm"
  winrm_username        = var.admin_username
  winrm_password        = var.admin_password
  winrm_port            = 5986
  winrm_use_ssl         = true
  winrm_insecure        = true
  winrm_timeout         = "30m"
  #============================================================================================


  #============================================================================================
  # --- Sealing & Final Shutdown (Sysprep) for Windows 11 ---
  # After running client cleanup and staging the clone answer file, Packer invokes Sysprep.
  # Strips machine SIDs, generalizes hardware drivers, optimizes for cloning, and powers off.
  # The finalized master hard drive is saved directly to your Windows 11 output folder.
  shutdown_command      = "powershell -Command \"Start-Sleep -Seconds 10; & $${env:SystemRoot}\\System32\\Sysprep\\sysprep.exe /oobe /generalize /quiet /shutdown /mode:vm\""
  shutdown_timeout      = "20m"
  output_directory      = var.win11_output_directory # Saves into the dedicated Windows 11 folder
}
#============================================================================================


# ====================================================================================
# SECTION 4: PROVISIONING PIPELINE - Base image applications & Clean up scripts
# ====================================================================================
# This block handles all software delivery, OS sanitization, and answer file staging
# before Sysprep seals the virtual hard drives.
#
# CUSTOM APPLICATIONS:
# Place any software installers (MSI, EXE, Chocolatey/Winget scripts) directly in 
# this section BEFORE the cleanup scripts run. Always execute application installs 
# before disk cleanup to ensure temporary install caches get purged prior to sealing.
build {

  sources = [
    "source.hyperv-iso.win2025",
    "source.hyperv-iso.win11"
  ]

  /* ----------------------------------------------------------------------------------
  # EXAMPLE: Custom Application Installation (PowerShell 7) - this has not been implemented in the working build, thus has not been tested.
  # Reason being I wanted to keep the golden images as clean as possible.
  # ----------------------------------------------------------------------------------
  # To bake PowerShell 7 into either or both golden images, uncomment this block.
  # It downloads the official x64 MSI directly from GitHub and executes a silent,
  # non-interactive installation before the cleanup tasks execute.
  #
  # provisioner "powershell" {
  #   # Targets both sources by default, or restrict with: only = ["hyperv-iso.win2025"]
  #   inline = [
  #     "Write-Host 'Downloading PowerShell 7 MSI...' -ForegroundColor Cyan",
  #     "$url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/PowerShell-7.4.2-win-x64.msi'",
  #     "$dest = 'C:\\Windows\\Temp\\PowerShell-7-x64.msi'",
  #     "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
  #     "Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing",
  #     "",
  #     "Write-Host 'Installing PowerShell 7 silently...' -ForegroundColor Cyan",
  #     "$args = '/i C:\\Windows\\Temp\\PowerShell-7-x64.msi /qn /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1'",
  #     "Start-Process msiexec.exe -ArgumentList $args -Wait -NoNewWindow",
  #     "",
  #     "Write-Host 'Cleaning up installer binary...' -ForegroundColor Cyan",
  #     "Remove-Item -Path $dest -Force -ErrorAction SilentlyContinue"
  #   ]
  # }
  # ----------------------------------------------------------------------------------*/
  # Provisioner A1: Windows Server 2025 Cleanup
  # Runs server maintenance: clears update caches and wipes setup temp files.
 
 
  provisioner "powershell" {
    only   = ["hyperv-iso.win2025"]
    script = "${path.root}/scripts/cleanup-server2025.ps1" 
  }

  # Provisioner A2: Windows 11 Cleanup
  # Runs client maintenance: enforces BitLocker decryption, strips consumer apps, and trims disk.

  provisioner "powershell" {
    only   = ["hyperv-iso.win11"]
    script = "${path.root}/scripts/cleanup-win11.ps1"  #This differs from the cleanup script used by Server 2025, to Sysprep Win11, I had to decrypt Win11 first 
  } # because, by default, the latest version of Win11 enables Bit Locker by default if all hardware requirements are met.

  # Provisioner A3: Stage Answer File for Server 2025 Clones
  # Injects admin credentials into unattend.xml and drops it in C:/Windows/Panther/
  provisioner "file" {
    only = ["hyperv-iso.win2025"]
    content = templatefile("${path.root}/Hyper-VM_source/unattend.pkrtpl.hcl", {
      admin_username = var.admin_username
      admin_password = var.admin_password
    })
    destination = "C:/Windows/Panther/unattend.xml"
  }

  # Provisioner A4: Stage Answer File for Windows 11 Clones
  # Injects admin credentials into the Windows 11 unattend.xml in C:/Windows/Panther/
  provisioner "file" {
    only = ["hyperv-iso.win11"]
    content = templatefile("${path.root}/Hyper-VM_source/unattend-win11.pkrtpl.hcl", {
      admin_username = var.admin_username
      admin_password = var.admin_password
    })
    destination = "C:/Windows/Panther/unattend.xml"
  }
}
# ====================================================================================