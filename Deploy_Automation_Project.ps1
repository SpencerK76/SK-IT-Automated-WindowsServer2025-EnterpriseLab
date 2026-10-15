<#
.SYNOPSIS
    Deploy_Automation_Project.ps1 - Root launcher.

.DESCRIPTION
    This is the main entry-point script located at the very root of the repository.
    Its job is to make sure the Orchestrator file (The One Ring!) are where they belong, find the
    script inside the 'SK-Automation-Scripts' folder, and launch it.

    In future updates, this script will feature an interactive menu allowing you to:

      1. Enter custom settings directly in the PowerShell console (e.g., Domain Name, Server Roles, vSwitch names etc..).
      2. Fill out a simple guided web form that feeds the settings into the build.
      3. Automatically open all relevant configuration files so you can tweak them manually.
      4. Run the Default Deployment without prompts (a one-click build using tested defaults).
    
    Future revisions of this project will also add Linux based OS automation.
#>

[CmdletBinding()]
param()

# -------------------------------------------------------------------------
# Environment Setup: Ensure Project Root is in PATH for child scripts
# -------------------------------------------------------------------------
$ProjectRoot = $PSScriptRoot
if ($env:PATH -notlike "*$ProjectRoot*") {
    $env:PATH = "$ProjectRoot;$env:PATH"
}

# --- Step 1: Discover where this script lives on your computer ---
# $PSScriptRoot automatically detects the folder this script is running from,
# so the project works on any drive letter (C:\, D:\, etc.) without hardcoded paths.
$ScriptRoot = $PSScriptRoot

# --- Step 2: Build the path to the Master Orchestrator script ---
# Join-Path safely combines folder names using proper Windows backslashes.
$Orchestrator = Join-Path -Path $ScriptRoot -ChildPath "SK-Automation-Scripts\SK_Automation-host_The-One-Ring.ps1"

# --- Step 3: Check if the Orchestrator file actually exists before running ---
if (-not (Test-Path -Path $Orchestrator)) {
    Write-Error "CRITICAL: Could not find orchestrator at '$Orchestrator'. Please verify your repository structure and file names."
    exit 1
}

# --- Step 4: Display clean status information in the console ---
Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       SK Automation Enterprise Deployment Pipeline        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Orchestrator: $Orchestrator" -ForegroundColor DarkGray
Write-Host ""

<#
# --- FUTURE INTERACTIVE MENU PLACEHOLDER ---
# Write-Host "[1] Run Default Deployment (Standard Lab Configuration)"
# Write-Host "[2] Custom Deployment (Interactive Prompts)"
# Write-Host "[3] Dry-Run / Validate Environment Pre-chcks"
# $Choice = Read-Host "Select deployment mode [1-3]"
#>

# --- Step 5: Start the Master Orchestrator ---
Write-Host "Launching The One Ring Orchestrator..." -ForegroundColor Green
Write-Host ""

# The '&' call operator tells PowerShell to run the script stored in the variable.
& $Orchestrator