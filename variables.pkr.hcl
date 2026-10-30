# =========================================================================================
# SCRIPT: variables.pkr.hcl
# PURPOSE: Input variable declarations, data types, and default values for Packer Stage 1.
# TECHNOLOGY: HashiCorp Packer (v1.10.0+), Windows Server 2025 Eval, Windows 11 Enterprise
# DESCRIPTION: Centralizes all input definitions (OS media paths, SHA-256 validation hashes,
#              hypervisor switch bindings, and administrative credentials) for the build pipeline.
# =========================================================================================

# ==============================================================================
# SECTION 1: WINDOWS SERVER 2025 MEDIA & STORAGE
# ==============================================================================
variable "iso_url" {
  type        = string
  description = "Local file path or URI to the Windows Server 2025 installation ISO."
  default     = "ISOs/WinServer2025Eval.iso"
}

variable "iso_checksum" {
  type        = string
  description = "Cryptographic SHA-256 hash for the Windows Server 2025 ISO (prefixed with sha256:)."
}

variable "output_directory" {
  type        = string
  description = "Target destination folder where the finalized Windows Server 2025 master VHDX is exported."
  default     = "./output-ws2025-master-vhd"
}

# ==============================================================================
# SECTION 2: WINDOWS 11 ENTERPRISE MEDIA & STORAGE
# ==============================================================================
variable "win11_iso_url" {
  type        = string
  description = "Local file path or URI to the Windows 11 Enterprise installation ISO."
  default     = "ISOs/Win11ClientEntEval.iso"
}

variable "win11_iso_checksum" {
  type        = string
  description = "Cryptographic SHA-256 hash for the Windows 11 ISO (prefixed with sha256:)."
}

variable "win11_output_directory" {
  type        = string
  description = "Target destination folder where the finalized Windows 11 master VHDX is exported."
  default     = "./output-win11-master-vhd"
}

# ==============================================================================
# SECTION 3: HYPERVISOR NETWORKING & HOST INTERFACES
# ==============================================================================
variable "switch_name" {
  type        = string
  description = "Hyper-V Virtual Switch name used to bind VMs during the Packer build stage (e.g., WAN/Internet switch)."
  default     = "lab-switch-wan"
}

# ==============================================================================
# SECTION 4: GUEST ADMINISTRATIVE CREDENTIALS
# ==============================================================================
# NOTE: Set the actual password value inside 'packer.auto.pkrvars.hcl' or pass it 
# via environment variables. Do not hardcode production passwords directly into this file.
variable "admin_username" {
  type        = string
  description = "Local Administrator username configured during unattended setup."
  default     = "Administrator"
}

variable "admin_password" {
  type        = string
  description = "Local Administrator password injected into the answer files and WinRM communicators."
  sensitive   = true
}