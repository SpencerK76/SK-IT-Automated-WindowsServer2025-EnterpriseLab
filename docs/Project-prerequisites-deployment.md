# SK-IT Windows Server 2025 Automation Project :- Project Prerequisites & Deployment Guide

# 🚀 Project Prerequisites & Deployment Guide

This guide consolidates all prerequisite checks, system dependencies, hypervisor settings, and execution steps into a single walkthrough. Once the prerequisites are configured, you
will have a fully automated Windows Server 2025 domain, enabelling you to join clients/servers to your forest with a few lines of code.

See the **[Technical Reference Manual](Technical-Reference.md)** for architecture explantions and additional configurations.

---

### Table of Contents

## Quick Start Guide
1. [🟩 **STEP 1 — Git Clone the Repository**](#qs-step1-git-clone)
2. [🟩 **STEP 2 — Download the ISOs & HashCorp Packer**](#qs-step2-isos)
3. [🟩 **STEP 3 — Configure Administrator Credentials & Validate Checksums**](#qs-step3-admin-creds)
4. [🟩 **STEP 4 — Create the pfSense Isolated Network**](#qs-step4-pfsense)
5. [🟩 **STEP 5 — Customise Your Lab VMs**](#qs-step5-customise)
6. [🟩 **STEP 6 — Execute Deployment Orchestrator**](#qs-step6-orchestrator)

## Beginner Start Guide

1. [🟪 **STEP 1 — Map Hardware & Storage Capacity**](#bg-step1-map-hardware)
2. [🟪 **STEP 2 — Install Development Tools & Console**](#bg-step2-dev-tools)
3. [🟪 **STEP 3 — Install Hyper‑V**](#bg-step3-hyperv)
4. [🟪 **STEP 4 — Setup the pfSense Isolated Network**](#bg-step4-pfsense)
5. [🟪 **STEP 5 — Git‑clone the Repository & Download HashCorp Packer**](#bg-step5-git-clone)
6. [🟪 **STEP 6 — Customise Your Project**](#bg-step6-customise)
7. [🟪 **STEP 7 — Install the Windows ISOs + Checksums**](#bg-step7-isos)
8. [🟪 **STEP 8 — Set Your Administrator Credentials**](#bg-step8-admin-creds)
9. [🟪 **STEP 9 — Execute Deployment Orchestrator**](#bg-step9-orchestrator)
10. [⛔ **STEP 10 — Project Troubleshooting**](#bg-project-troubleshooting)


<br>

---

**Quick Links:** | [Read Me](../README.md) | [Technical Reference](Technical-Reference.md) | [Project Customisation](Customise-your-Infrastructure.md) | [pfSense Configuration](pfSense-configuration.md) | 

---
<br>

## 🟩 Quick Start Guide  <a id="qs-step1-git-clone"></a>
For users who are familiar with Packer, PowerShell Direct, and just want to get the lab up and running. It is assumed you have Hyper-v / VS Code installed and you are familiar to cloning a repository.

### 🟩 STEP 1. Git Clone the Repository:
It is assumed you are cloneing the Repositiory to a folder which has enough hard drive space to host (ISOs/Packer VHDs/Hyper-v nodes) your entire Lab. [Map Hardware & Storage Capacity](#bg-step1-map-hardware)

   ```powershell
   git clone [https://github.com/SpencerK76/SK-IT-Automated-WindowsServer2025-EnterpriseLab](https://github.com/SpencerK76/SK-IT-Automated-WindowsServer2025-EnterpriseLab)

   cd Automated-WindowsServer2025-EnterpriseLab
   ```
   This automation framework is fully self-contained. All evaluation ISOs, temporary Packer builds, golden master images, and cloned VHDXs are stored directly inside the repository tree. Ensure the host drive, partition, or folder hosting the repository has enough free space (350 GB+ for the default config) to accommodate the entire lab.
   
---

### 🟩 STEP 2. Download the ISO's and place them into the /ISO's folder: <a id="qs-step2-isos"></a>
  
Place both evaluation ISO files directly into the root ISOs/ folder using these default names:

   * WinServer2025Eval.iso - [Windows Server 2025 Datacenter (Desktop Experience) Evaluation](https://www.microsoft.com/en-gb/evalcenter/download-windows-server-2025)

   * Win11ClientEntEval.iso - [Windows 11 Enterprise Evaluation (English - Great Britain)](https://www.microsoft.com/en-gb/evalcenter/download-windows-11-enterprise)


If you need to customize paths or filenames, update them in **[variables.pkr.hcl](../variables.pkr.hcl)**. View the [Technical Reference](docs/Technical-Reference.md) for more information.

---

### 🟩 STEP 2a. Download HashCorp Packer and add it to the Repository folder: <a id="qs-step2-isos"></a>

Option 1: Automated Download to Repository Root - run this single command inside your VS Code terminal at the root of the project. It fetches the official 64-bit release from HashiCorp and extracts packer.exe directly into your repository folder:

```PowerShell
$ver = (Invoke-RestMethod "https://checkpoint-api.hashicorp.com/v1/check/packer").current_version
Invoke-WebRequest "https://releases.hashicorp.com/packer/$ver/packer_${ver}_windows_amd64.zip" -OutFile "$env:TEMP\packer.zip" -UseBasicParsing
Expand-Archive "$env:TEMP\packer.zip" -DestinationPath . -Force
Remove-Item "$env:TEMP\packer.zip" -Force
Write-Host "Packer v$ver ready in project root." -ForegroundColor Green
```
Option 2: Install via Windows Package Manager (winget) If your host system has winget installed:
```Powershell
if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
    Write-Host "Packer not detected. Installing via winget..." -ForegroundColor Yellow
    winget install HashiCorp.Packer --silent --accept-source-agreements --accept-package-agreements
}
```
Option 3: Manual Direct Download. Download the 64-bit Windows binary zip directly from the HashiCorp Packer Portal.
```Powershell
Invoke-WebRequest "https://developer.hashicorp.com/packer/install" -OutFile "$env:TEMP\packer.zip" -UseBasicParsing
```

Extract packer.exe from the archive and place it into the root repository folder.

---

### 🟩 STEP 3. Configure Administrator Credentials & Validate ISO Checksums: <a id="qs-step3-admin-creds"></a>

   * Open **[packer.auto.pkrvars.hcl](../packer.auto.pkrvars.hcl)** to set your administrative password and verify/enter the ISO checksums.

   * This automation pipeline uses a single injection point: you declare your administrator password once, and the master orchestrator **[The One Ring](../SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1)** carries it securely through every stage of the build.

---

### 🟩 STEP 4. Create the pfSense Isolated Network - then return to STEP 5 <a id="qs-step4-pfsense"></a>

This architecture creates a direct 1:1 mapping between your Hyper-V virtual switches and pfSense logical interfaces.  Please follow this quick guide: **[How to setup an isolated Hyper-V lab with internet access](https://www.youtube.com/watch?v=eEZZQT8T4xY&t=690s)**.  My configuration mirrors the configurations in that guide. Please make sure your configurations match.  For a more indepth analysis of pfSesne and why it was used, go here - [pfSense Configuration](PfSense-configuration.md). 

Basic setup:

* **`lab-switch-wan` $\rightarrow$ `hn0` $\rightarrow$ WAN (`192.168.0.#`):** Binds directly to your physical host network adapter to receive an IP via DHCP from your home or office router, providing outbound internet access.
* **`lab-switch-lan` $\rightarrow$ `hn1` $\rightarrow$ LAN (`10.0.0.254`):** Placed on a Private Hyper-V switch completely isolated from your physical network. All automated lab VMs attach exclusively here.

   * Ensure Hyper-V virtual switch names match the configuration files (`$VMList: 01_SK_Automation-Host_CreateVM.ps1`) and (`variable "switch_name": variables.pkr.hcl`) exactly, no spaces or trailing characters.
   * Obviously test network isolation / outbound connectivity before running the deployment script.

---

### 🟩 STEP 5. Customize Your Lab VMs - then return to STEP 6. <a id="qs-step5-customise"></a>
Review and adjust configuration parameters in the **[Project Customisation](Customise-your-Infrastructure.md)** if you need to alter settings (server names, domain and forest names) from the defaults defined in the project files:

* **[`build.pkr.hcl`](../build.pkr.hcl)** — Default Sysprep disk sizing, guest software provisioners, and unattended XML staging.
* **[`variables.pkr.hcl`](../variables.pkr.hcl)** — ISO relative paths, filenames, and default `lab-switch-wan` binding.
* **[`packer.auto.pkrvars.hcl`](../packer.auto.pkrvars.hcl)** — Root administrator credentials and pre-populated evaluation ISO checksums.
* **[`SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** — Hyper-V VM generation, hardware profiles (`$VMList` array), and vSwitch assignments.
* **[`SK-Automation-Scripts/SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)** — Static IP addresses, subnets, gateway configurations, domain name, and Active Directory roles for each node.

> **Adding Servers Post-Deployment:** You can scale your environment after the initial infrastructure has been deployed. Simply add a new VM definition to the `$VMList` array in `01_SK_Automation-Host_CreateVM.ps1` and specify its network parameters in `SK_Automation-VMConfig.json`. Every node must be assigned one of three supported roles:
> * **`Replica DC`** — Secondary domain controller for forest redundancy.
> * **`Member Server`** — Joined to the Active Directory domain for workload testing.
> * **`Client`** — Windows 11 enterprise workstation joined to the domain.

---

### 🟩 STEP 6. Execute Deployment Orchestrator: <a id="qs-step6-orchestrator"></a>
Before launching the full automation pipeline, make sure Hyper‑V and PowerShell are set up correctly.

1. **Disable Enhanced Session Mode in Hyper‑V**  
   Enhanced Session Mode can interfere with automated VM boots, so switch it off:
   - Open **Hyper‑V Manager** as Administrator  
   - Right‑click your Hyper‑V host → **Hyper‑V Settings**  
   - Select **Enhanced Session Mode**  
   - Untick **Allow enhanced session mode**

2. **Open an Elevated PowerShell 7 Terminal**  
   Use Visual Studio Code or Windows Terminal — just make sure you’re running **as Administrator**.

3. **Set the Execution Policy**  
   Your automation scripts require PowerShell to allow local script execution. Set the system‑level policy to `RemoteSigned`:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
   ```

Run the Orchestrator Script:
```powershell  
 # Validate Your Packer Configuration to confirm that your Packer templates are valid:
./packer validate .

# To start the automation, run `./Deploy_Automation_Project.ps1` script, from the Packer root directory.  
# Its job is to make sure the Orchestrator file (The One Ring!) are where they belong, find the 
# script inside the 'SK-Automation-Scripts' folder, and launch it.    

      .\Deploy_Automation_Project.ps1
 
 ```
This will now create, deploy and configure your Lab infrastructure, which was configured in the * **[`SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** script.  There should not be any errors but different host setups may produce slightly different timings or warnings, but nothing should break the workflow. 

The deployment should run smoothly end‑to‑end. Different host setups may produce slightly different timings or warnings, but nothing should break the workflow.
If anything unexpected pops up:
   * AI can help troubleshoot quickly
   * You can open a support ticket [here](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portal/1/create/26)
   * Or leave feedback/suggestions to help improve the documentation, project [here](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portal/1/create/27) 

---
<br>

## 🟪 Beginner Start Guide (users starting from scratch) <a id="beginner-start"></a>

Here is a more indepth guide for users that are starting from the very begining.  Please use AI to supplement your learning and configurations.

---

### 🟪 STEP 1. Map Hardware & Storage Capacity  <a id="bg-step1-map-hardware"></a>
Map out your host resources before deploying. If you plan to customize this automation project beyond the default settings, calculate your physical hardware requirements first:

* **Node Count & Roles:** How many Domain Controllers, member servers, and client workstations do you plan to provision?
* **Resource Allocation:** What are their individual static/dynamic RAM limits and vCPU allocations?
* **Storage Footprint:** Does your target drive have sufficient SSD/NVMe space to host the raw ISOs, golden images, and dynamically expanding VHDX clones?

* **Default Topology Baseline:** If you stick with the default configuration, ensure your host system has at least **32 GB of RAM** and **350 GB of free SSD space**. If this is the case, you can leave all hardware resource values as they are and simply customize computer hostnames and domain names.

* **Storage Requirements:** The default five-node lab requires at least **350 GB of free space** on a high-speed SSD or NVMe drive. If tailoring the deployment for fewer nodes, calculate your required storage and adjust the values in the [Infrastructure Customization Guide](Customise-your-Infrastructure.md).

* **Storage Rules:** This automation project operates as a completely self-contained directory tree. Always clone and run the repository directly from the root or dedicated folder of your target high-capacity drive; try not split ISOs, VHDXs, or scripts across different drive letters. You can do this, it just means adjusting the scripts.
See [Technical Reference](docs/Technical-Reference.md) for more information.

* **Supported Host Operating Systems:** Windows 11 (Pro, Enterprise, or Education) or Windows Server (2022 / 2025 with Desktop Experience) with Hyper-V enabled.

> As previously discussed each virtual machine receives a clone of the Packer VHDX (60 GB) drive that expands dynamically, by default. You can customise your lab to reduce the hardware requirements a number of ways. 

> You can customise your lab significantly: for example, say you only have 90 GB of space, you can create one Root DC and one Windows 11 client.  When you git-clone the automation repository (Step 5), to a specific folder, please make sure the drive that folder is located on has enough HD space for your entire automation project, leaving room for additonal nodes and future upgrades.

---
<br>

### 🟪 STEP 2. Install Development Tools & Console  <a id="bg-step2-dev-tools"></a>
* Download and install the latest [Visual Studio Code](https://code.visualstudio.com/Download).
* Download and install the latest [PowerShell 7 (PS7)](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) *(Restart VS Code after installing PS7)*.

### VS Code Extensions
Open VS Code, press `Ctrl+Shift+X` (or click the Extensions icon in the Activity Bar), and install:

**Required (Critical):**
* **PowerShell** (`ms-vscode.PowerShell`) — **Required.** Provides the core PowerShell execution engine inside VS Code, along with IntelliSense, debugging, and code navigation needed to run the automation scripts.

**Optional (Recommended):**
* **HashiCorp HCL** (`HashiCorp.HCL`) — Syntax highlighting and linting for `.pkr.hcl` template files.
* **Markdown All in One** (`yzhang.markdown-all-in-one`) — Live preview, shortcuts, and table of contents generation for project documentation.
* **GitHub Copilot** (`GitHub.copilot`) — AI code completion and script suggestions.
* **GitHub Copilot Chat** (`GitHub.copilot-chat`) — In-editor architectural and scripting assistant.

### Set PowerShell 7 as Your Default Terminal
1. In VS Code, press `Ctrl+Shift+P` to open the Command Palette.
2. Type **`Terminal: Select Default Profile`** and press **Enter**.
3. Select **PowerShell 7 (pwsh)**.

### Helpful Git & VS Code Guides
If you are new to working with Git repositories in VS Code, these tutorials provide a quick orientation:
* 🎥 [Learn Visual Studio Code in 15 Minutes](https://www.youtube.com/watch?v=B-s71n0dHUk)
* 🎥 [How to Clone a GitHub Repository in VS Code](https://www.youtube.com/watch?v=FQqlTFf_y-U)

### . Configure PowerShell Script Execution Policy
Windows restricts unsigned script execution by default. To allow the automation orchestrator and child scripts to run inside the integrated VS Code terminal, set the execution policy to `RemoteSigned`:
```powershell
# Run inside your elevated VS Code PowerShell 7 terminal:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```
---
<br>

### 🟪 STEP 3. Install Hyper-V on your Windows Client <a id="bg-step3-hyperv"></a>
In Visual Studio Code, run the following, or install via Windows 11 GUI.

To install Hyper-v you must:
   * Ensure your hardware supports virtualization
   * Enable virtualization in BIOS/UEFI
   * Enable the Hyper‑V Windows feature and restart your machine

`Open Start > type “systeminfo” > Run Command Prompt > systeminfo.` Scroll to the bottom of the output 
Ensure the following all say Yes:

   * VM Monitor Mode Extensions
   * Virtualization Enabled in Firmware
   * Second Level Address Translation (SLAT)
   * Data Execution Prevention Available

Install via GUI:
`Open Start → type “Turn Windows features on or off”`:
   * Tick Hyper‑V
   * Tick Hyper‑V Management Tools
   * Tick Hyper‑V Platform
   * Click OK to install
   * Restart when prompted

Install via Powershell: 

```powershell
# 1. Check Hyper-V hardware requirements (scroll to the bottom of the output):
systeminfo

# 2. Install Hyper-V (requires an elevated Administrator terminal): Windows 11 / Windows 10:
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Windows Server (2022/2025):
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```
>Important: On Windows 11/10 client operating systems, restart your host computer after running this command to initialize the hypervisor kernel.

>Privilege Rule: Always launch the Hyper-V Manager console with elevated Administrator privileges.

>Enhanced Session Mode: Please disable Enhanced Session Mode in Hyper-V Settings until after the automation run completes, preventing interactive session prompts from interrupting unattended provisioning.

---
<br>

### 🟪 STEP 4. Setup the pfSense Isolated Network in Hyper-V <a id="bg-step4-pfsense"></a>
Deploy your isolated Hyper-V network by following the **[pfSense Configuration Guide](PfSense-configuration.md)**. This guide explains why pfSense was chosen for perimeter isolation, provides a step-by-step walkthrough for virtual switch and network adapter configurations, and includes a link to a video tutorial that mirrors the exact network settings used throughout this automation project. A brief summary of the network architecture can also be viewed below in [🛡️ pfSense Network Isolation Guide](#pfsense-network-isolation-guide).

---
<br>

### 🟪 STEP 5.  Git-clone the repository <a id="bg-step5-git-clone"></a>
After you have installed Visual Studio Code, and have finished all the previous prerequisites (and have run tests to make sure you have isolated and outbound connectivity), it's time for you to git-clone the SK-IT Windows Server 2025 Automation Project and install the repository files.

To prevent path fragmentation and avoid Hyper-V permission issues (`NT VIRTUAL MACHINE\Virtual Machines` ACL errors etc..), **do not split repository paths across multiple drives**. Clone the entire project repository directly onto the root or a dedicated folder, drive or partition that has enough capacity for your entire lab. A high-capacity SSD/NVMe drive is recommended. Please read section 2, 3 of the Technical Reference, and sections 1, 2 of the Project Customisations for more information.

### Instructions on how to clone to a specific drive/folder.  

Open an elevated PowerShell terminal and navigate to your target storage drive (e.g., `D:`, `E:`, or `X:`):

```powershell
# 1. Switch to your high-capacity storage drive
Set-Location -Path "D:\"

# 2. Clone the repository into a dedicated folder
git clone [https://github.com/YourUsername/Your-Repo-Name.git](https://github.com/YourUsername/Your-Repo-Name.git) "D:\HyperV-Automation-Lab"

# 3. Enter the repository root directory
Set-Location -Path "D:\HyperV-Automation-Lab".
```
After completing this, you should be able to view all the files in this automation project. [📁 Repository Structure](#repository-structure)

---
<br>

### 🟪 STEP 5b. Download HashCorp Packer and add it to the Repository folder: <a id="qs-step2-isos"></a>

Option 1: Automated Download to Repository Root - run this single command inside your VS Code terminal at the root of the project. It fetches the official 64-bit release from HashiCorp and extracts packer.exe directly into your repository folder:

```PowerShell
$ver = (Invoke-RestMethod "https://checkpoint-api.hashicorp.com/v1/check/packer").current_version
Invoke-WebRequest "https://releases.hashicorp.com/packer/$ver/packer_${ver}_windows_amd64.zip" -OutFile "$env:TEMP\packer.zip" -UseBasicParsing
Expand-Archive "$env:TEMP\packer.zip" -DestinationPath . -Force
Remove-Item "$env:TEMP\packer.zip" -Force
Write-Host "Packer v$ver ready in project root." -ForegroundColor Green
```
Option 2: Install via Windows Package Manager (winget) If your host system has winget installed:
```Powershell
if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
    Write-Host "Packer not detected. Installing via winget..." -ForegroundColor Yellow
    winget install HashiCorp.Packer --silent --accept-source-agreements --accept-package-agreements
}
```
Option 3: Manual Direct Download. Download the 64-bit Windows binary zip directly from the HashiCorp Packer Portal.
```Powershell
Invoke-WebRequest "https://developer.hashicorp.com/packer/install" -OutFile "$env:TEMP\packer.zip" -UseBasicParsing
```
Extract packer.exe from the archive and place it into the root repository folder.

---
<br>

### 🟪 STEP 6.  Customise your project then return to STEP 7<a id="bg-step6-customise"></a>
Please view the customisation guide here, [Project Customisation](Customise-your-Infrastructure.md) and return after it has been completed.

---
<br>

### 🟪 STEP 7 Install the Windows ISOs + Checksums <a id="bg-step7-isos"></a>
Required Evaluation Media. Download these ISOs.
* [Windows Server 2025 Datacenter (Desktop Experience) Evaluation](https://www.microsoft.com/en-gb/evalcenter/download-windows-server-2025)
* [Windows 11 Enterprise Evaluation (English - Great Britain)](https://www.microsoft.com/en-gb/evalcenter/download-windows-11-enterprise)

Once downloaded, place both ISO images into the `/ISOs` repository directory using these exact filenames:
* `WinServer2025Eval.iso`
* `Win11ClientEntEval.iso`

**Note:** This project operates as a **completely self-contained repository**. All raw evaluation ISOs, temporary Packer builds, master golden VHDXs, and cloned virtual machines live directly inside the repository tree. I strongly recommend sticking to the default directory paths, which can be found in **[variables.pkr.hcl](../variables.pkr.hcl)**.

---
<br>

### 🟪 STEP 8. Set your Administrator credentials <a id="bg-step8-admin-creds"></a>
### Where to Declare Your Credentials
Open `packer.auto.pkrvars.hcl` in the repository root and declare your desired local administrator username and password:

```text
# The credentials declared here serve as the root identity across the entire pipeline:
admin_username = "Administrator"
admin_password = "YourSecurePassword123!"

# Windows Evaluation ISO Checksums (Pre-populated) - please see ISO for more information regarding the ISO's.
iso_checksum       = "sha256:7B052573BA7894C9924E3E87BA732CCD354D18CB75A883EFA9B900EA125BFD51"
win11_iso_checksum = "6E861B93EB9501182AD2E4DC3FA8C411AFB6D7ED86A8CCBE37CA67D75470B95F"
```
---
<br>

### 🟪 STEP 9 — Run the Deployment Orchestrator  <a id="bg-step9-orchestrator"></a>                
Before launching the full automation pipeline, make sure Hyper‑V and PowerShell are set up correctly.

1. **Disable Enhanced Session Mode in Hyper‑V**  
   Enhanced Session Mode can interfere with automated VM boots, so switch it off:
   - Open **Hyper‑V Manager** as Administrator  
   - Right‑click your Hyper‑V host → **Hyper‑V Settings**  
   - Select **Enhanced Session Mode**  
   - Untick **Allow enhanced session mode**

2. **Open an Elevated PowerShell 7 Terminal**  
   Use Visual Studio Code or Windows Terminal — just make sure you’re running **as Administrator**.

3. **Set the Execution Policy**  
   Your automation scripts require PowerShell to allow local script execution. Set the system‑level policy to `RemoteSigned`:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
   ```

Run the Orchestrator Script:
```powershell  
 # Validate Your Packer Configuration to confirm that your Packer templates are valid:
./packer validate .

# To start the automation, run `./Deploy_Automation_Project.ps1` script, from the Packer root directory.  
# Its job is to make sure the Orchestrator file (The One Ring!) are where they belong, find the 
# script inside the 'SK-Automation-Scripts' folder, and launch it.    
# You can stop the automation at any time by: Ctrl + C in the terminal window.  Packer deletes the output folders, only if it has not reached stage 2.
# After you have built the nodes in Hyper-v, if you want to wipe the entire automated kab, use lab-wipe.ps1. 

      .\Deploy_Automation_Project.ps1
 
  ```
This will now create, deploy and configure your Lab infrastructure, which was configured in the * **[`SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** script.  There should not be any errors but different host setups may produce slightly different timings or warnings, but nothing should break the workflow. 

The deployment should run smoothly end‑to‑end. Different host setups may produce slightly different timings or warnings, but nothing should break the workflow.
If anything unexpected pops up:
   * AI can help troubleshoot quickly
   * You can open a support ticket [here](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portal/1/create/26)
   * Or leave feedback/suggestions to help improve the documentation, project [here](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portal/1/create/27) 

<br>

---

## ⛔ Project Troubleshooting - this section will be updated when, if, more errors are reported <a id="bg-project-troubleshooting"></a>      


### ⛔ Error 1: VS code output - if Packer outputs this error:
```Powershell

2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin: 2026/10/16 08:39:16 [DEBUG] Unable to get address during connection step: PowerShell error: Hyper-V\Get-VM : Hyper-V encountered an error trying to access an object on computer 'MAINADMIN' because the object was not found. The object might have been deleted, or you might not have permission to perform the task. Verify that
2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin: the Virtual Machine Management service on the computer is running. If the service is running, try to perform the task again by using Run as Administrator.
2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin: +   $vm = Hyper-V\Get-VM | ?{$_.NetworkAdapters.MacAddress -eq $mac}
2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin: +         ~~~~~~~~~~~~~~
2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin:     + CategoryInfo          : ObjectNotFound: (:) [Get-VM], VirtualizationException
2026/10/16 08:39:16 packer-plugin-hyperv_v1.1.5_x5.0_windows_amd64.exe plugin:     + FullyQualifiedErrorId : ObjectNotFound,Microsoft.HyperV.PowerShell.Commands.GetVM
```

```text
This usually occures when Packer queries the Hyper-V host VM inventory, via Get-VM, and encounters permission issues or broken virtual machine state.

   * Missing Administrator Privileges: Both VS Code and Hyper-V Manager must be launched using Run as Administrator.
   * Orphaned or Broken VMs: Any VM in a Saved-Critical or hung Stopping state will cause Get-VM to throw an exception across the entire host. 
```
---
Debugging tip: If you do run into an halt-error, you can run each script independantly without having to recreate the PackerVHDx's again.
```powershell

#Set this to $true in the SK_Automation-host_The-One-Ring.ps1.  This skips the entire Packer build process and runs automation scripts
[CmdletBinding()]
param(
    [switch]$SkipPackerBuild = $true
)

#You can also run each script independantly outside the OneRing Orchestrator. 
#1. Execute these credential variables first in your VSC PowerShell console one time.

   $secPass = ConvertTo-SecureString "EnterYourPasswordYouSetInPacker" -AsPlainText -Force
   $cred    = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

#2. Then execute the script passing the credential object:
 .\01_SK_Automation-Host_CreateVM.ps1 -Credential $cred
```

<br>
---
