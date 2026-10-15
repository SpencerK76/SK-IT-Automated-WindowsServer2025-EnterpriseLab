![Project Status: In Development](https://img.shields.io/badge/status-active--development-orange?style=flat-square&logo=git)
> [!NOTE]
> **Work in Progress:** This automation lab is currently undergoing active development and testing.

---

# SK-IT Windows Server 2025 Automation Project 

## Description, Goal and the Future
* **Project Description:** This project automates the creation of a fully isolated Windows Server 2025 domain environment, including clients, member servers, and preconfigured server roles (AD DS, DNS, and DHCP), along with users and organisational units (OUs). The build pipeline uses Visual Studio Code, Hyper-V, pfSense (for network isolation), and PowerShell Direct. It provides a repeatable sandbox for lab testing, certification preparation, and practical hands-on administration.

* **The Goal:** Build a script-based, repeatable, isolated, end-to-end workflow that deploys or tears down the entire environment with minimal manual intervention. The configuration allows users to easily customise node counts (VMs), assigned roles (Root DC, Replica DC, Member Server, Client), and virtual hardware specifications (vCPU, dynamic/static memory, disk provisioning, etc.).

* **Future Roadmap:** Planned updates include an interactive setup mode where users can step through lab settings right in the VS Code terminal (via `Read-Host` prompts) or through a lightweight web form, alongside the existing automated defaults should they choose them.

## How This Project Was Accomplished
This project uses HashiCorp Packer to build two sysprepped golden VHDX images: Windows Server 2025 Datacenter and Windows 11. Both images are fully sysprepped and include bootstrap scripts that establish the initial communication channel, handing off control to PowerShell Direct. 

PowerShell Direct then executes a sequence of six automation scripts that read from a JSON configuration file to provision and customize the Hyper-V VMs. These scripts build the AD DS forest and domain, promote the domain controllers, join member servers and clients, and structure the organisational units (OUs) alongside initial user accounts.

All stages are coordinated by the One Ring Orchestrator script, which acts as a centralised pipeline controller and single source of authentication, execution and error handling.

It is recommended you read through the **[Technical Reference Guide](/docs/Technical-Reference.md)** before you read the Project Prerequisites & Deployment Guide. 

---

**Quick Links:** [Technical Reference](docs/Technical-Reference.md) | [Project Customisation](docs/Customise-your-Infrastructure.md) | [pfSense Configuration](docs/pfSense-configuration.md) | [Project Prerequisites & Deployment Guide](docs/Project-prerequisites-deployment.md) |


---

## Project Stages Overview
This automation project is divided into three major deployment stages, each orchestrated by the "One Ring Orchestrator":

💍 **The Master Orchestrator (`the-one-ring.ps1`):**
Acts as the centralised pipeline controller and single entry point of execution. It enforces strict fail-fast error handling (`$ErrorActionPreference = "Stop"`) across all sub-stages. If prerequisite validation, a Packer build phase, or a PowerShell Direct configuration throws an error, the orchestrator halts execution immediately. Once a stage finishes successfully, a "Stage completed" status is output and the pipeline proceeds to the next stage.

---

### 🟦 Stage 1 — Golden Image Creation Using Packer
- Uses [Packer](build.pkr.hcl) to build fully sysprepped Windows Server 2025 and Windows 11 golden VHDX images from raw ISO media.
- Employs [modular HCL](variables.pkr.hcl) and XML [answer file](templates/Autounattend.pkrtpl.hcl) templates (`Autounattend.pkrtpl.hcl`) to automate disk partitioning, OS edition selection, and regional/local (UK) settings.
- Executes [bootstrap](scripts/bootstrap-winrm-https.ps1) scripts to provision temporary credentials and configure WinRM over HTTPS so Packer can communicate with and sysprep the base OS images.
- Dynamically injects a single set of [administrative credentials](packer.auto.pkrvars.hcl) via `packer.auto.pkrvars.hcl`, eliminating hardcoded passwords across the entire build pipeline.

**Execution Handover:** With the golden VHDXs sealed, [the-one-ring.ps1](SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1) hands off control to the host automation suite to provision the VMs and configure the guest OS instances via PowerShell Direct.

---

### 🟩 Stage 2 — Hyper-V Infrastructure Deployment (Automation Scripts 01–03)
- **[Stage 2.1](SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1) (VM Compute Sizing):** Reads `$VMList` in `01_SK_Automation-Host_CreateVM.ps1` to clone VHDXs from the golden VHDX images, configures allocated vCPUs and RAM, attaches the virtual network adapter to the `lab-switch-lan` switch (connected to pfSense), and boots the VMs.
- **[Stage 2.2](SK-Automation-Scripts/02_SK_Automation-Host_VMConfigTest.ps1) (Readiness Check):** Uses `02_SK_Automation-Host_VMConfigTest.ps1` to verify that each guest OS has finished initial setup and responds over the Hyper-V VMBus via PowerShell Direct, confirming readiness for AD DS deployment.
- **[Stage 2.3](SK-Automation-Scripts/03_SK_Automation-Host_VMConfigDeploy.ps1) (Network & Identity Injection):** Ingests [`SK_Automation-VMConfig.json`](SK-Automation-Scripts/SK_Automation-VMConfig.json) in `03_SK_Automation-Host_VMConfigDeploy.ps1` to assign static IP addresses, default gateways, DNS resolvers, Active Directory site names, and computer hostnames.

---

### 🟪 Stage 3 — Active Directory & Enterprise Customisation (Automation Scripts 04–06)
- **[Stage 3.1](SK-Automation-Scripts/04_SK_Automation-Host_PromoteRootDC.ps1) (Forest Root Bootstrap):** Installs AD DS and DNS server binaries on `SRV-DC1` (dynamically targeted via `"Role": "RootDC"`), builds the customisable forest root (`internal.sk-it.com`), and promotes the local administrator account to Domain Administrator using the credentials defined in `packer.auto.pkrvars.hcl`.
- **[Stage 3.2](SK-Automation-Scripts/05_SK_Automation-Host_NodeJoin.ps1) (Site Topology, Replica DC & Fleet Joins):** Configures the Active Directory site (`Kent-DataCenter`), subnet (`10.0.0.0/24`), and reverse lookup zone on `SRV-DC1`; installs AD DS and promotes `SRV-DC2` (targeted via `"Role": "ReplicaDC"`) as a secondary domain controller for high availability; and joins all member servers (`SRV-EX01`, `SRV-MS01`) and the Windows 11 client (`CLI-WIN11-01`) to the domain.
- **[Stage 3.3](SK-Automation-Scripts/06_SK_Automation-Host_CustomConfigs.ps1) (Enterprise Services, Identity Seeding & Sanitisation):** Installs and authorises an Active Directory-integrated DHCP scope (`10.0.0.0/24`) on `SRV-DC1`, builds the tiered OU hierarchy (`Corp_OU` and `Corp_Accounts`), seeds 10 baseline departmental test users with security groups, and purges setup credential caches (`C:\Windows\Panther`) across all virtual machines.

---

## Background Music While You Build 🎵
How about some background ambience while working through this automation project? Here are a few of my recommended tracks:

- 🎵 <a href="https://www.youtube.com/watch?v=xAR6N9N8e6U" target="_blank" rel="noopener noreferrer">Deep focus Psy-chill mix</a>
- 🎵 <a href="https://www.youtube.com/watch?v=KFTZisIh_1Y" target="_blank" rel="noopener noreferrer">Relaxing Celtic ambient soundtrack</a>
- 🎵 <a href="https://www.youtube.com/watch?v=hXMbcBRS5Ik" target="_blank" rel="noopener noreferrer">Relaxing Cyber-punk soundtrack</a>
- 🎵 <a href="https://www.youtube.com/watch?v=3F0jjLfSfQo" target="_blank" rel="noopener noreferrer">Relaxing ambient soundtrack</a>
- 🎵 <a href="https://www.youtube.com/watch?v=8sxhug9byP4" target="_blank" rel="noopener noreferrer">Calming ambient soundtrack</a>
---

## Pipeline Architecture, Script Manifest & Outputs

1. **Order:** The execution sequence of the scripts.
2. **Script Name:** The filename of each automation script.
3. **Stage:** The associated project deployment phase.
4. **Description:** A concise breakdown of the actions performed during that stage.
5. **Output Capture:** Visual confirmation of Packer and PowerShell Direct terminal output.
6. **Guest Configurations:** Verified operational status of the provisioned Hyper-V guest VMs.

<table>
  <thead>
    <tr>
      <th width="6%" align="center">Order</th>
      <th width="28%" align="left">Script / File Name</th>
      <th width="10%" align="center">Stage</th>
      <th width="36%" align="left">Description</th>
      <th width="20%" align="left">Output Capture</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center"><strong>00</strong></td>
      <td><nobr><a href="Deploy_Automation_Project.ps1"><code>Deploy_Automation_Project.ps1</code></a></nobr></td>
      <td align="center">Entry Point</td>
      <td>Bootstrap launcher. Resolves repository root paths, validates build files, verifies orchestrator existence, and initiates execution.</td>
      <td><a href="images/Packer-execution/Deploy.png">Deploy</a></td>
    </tr>
    <tr>
      <td align="center"><strong>01</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1"><code>SK_Automation-host_The-One-Ring.ps1</code></a></nobr></td>
      <td align="center">Orchestrator</td>
      <td>Pipeline controller. Captures administrative credentials, sets environment variables, and executes Stages 1 through 6 sequentially with strict fail-fast error handling.</td>
      <td><em>Console output</em></td>
    </tr>
    <tr>
      <td align="center"><strong>02</strong></td>
      <td><nobr><a href="build.pkr.hcl"><code>build.pkr.hcl</code></a></nobr></td>
      <td align="center">Stage 1</td>
      <td>Invokes Packer to perform unattended OS installations, producing clean, sysprepped base VHDXs for Windows Server 2025 and Windows 11.</td>
      <td>
        <a href="images/Packer-execution/Stage1_validate-start.png">Validate Start</a> · 
        <a href="images/Packer-execution/Stage1a_validate-finish.png">Validate Finish</a> · 
        <a href="images/Packer-execution/Stage1b_Sysprep.png">Sysprep</a> · 
        <a href="images/Packer-execution/Stage1c_OS-installation.png">OS Install</a> · 
        <a href="images/Packer-execution/Stage1d_expectedOutput-WinRMSer2025-Connected.png">WinRM (Server 2025)</a> · 
        <a href="images/Stage1d_expectedOutput-WinRMWin11-Connected.png">WinRM (Win 11)</a> · 
        <a href="images/Packer-execution/Stage1e_cleanup-script-execution.png">Cleanup Script</a> · 
        <a href="images/Packer-execution/Stage1f_finished-successfully.png">Build Complete</a>
      </td>
    </tr>
    <tr>
      <td align="center"><strong>03</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1"><code>01_SK_Automation-Host_CreateVM.ps1</code></a></nobr></td>
      <td align="center">Stage 2.1</td>
      <td>Allocates Hyper-V compute resources from the <code>$VMList</code> array, generates cloned VHDXs linked to the golden images, and boots all guest VMs.</td>
      <td><a href="images/Automation-stages/Stage2_1-completed.png">Stage 2.1 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>04</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/02_SK_Automation-Host_VMConfigTest.ps1"><code>02_SK_Automation-Host_VMConfigTest.ps1</code></a></nobr></td>
      <td align="center">Stage 2.2</td>
      <td>Executes pre-flight checks across all VMs to verify guest OS initialisation and ensure healthy PowerShell Direct communication over the VMBus.</td>
      <td><a href="images/Automation-stages/Stage2_2-completed.png">Stage 2.2 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>05</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/03_SK_Automation-Host_VMConfigDeploy.ps1"><code>03_SK_Automation-Host_VMConfigDeploy.ps1</code></a></nobr></td>
      <td align="center">Stage 2.3</td>
      <td>Ingests <code>SK_Automation-VMConfig.json</code> via PowerShell Direct to configure static networking, DNS resolvers, and computer hostnames.</td>
      <td><a href="images/Automation-stages/Stage2_3-completed.png">Stage 2.3 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>06</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/04_SK_Automation-Host_PromoteRootDC.ps1"><code>04_SK_Automation-Host_PromoteRootDC.ps1</code></a></nobr></td>
      <td align="center">Stage 3.1</td>
      <td>Connects to <code>SRV-DC1</code> via VMBus, installs AD DS and DNS roles, and promotes the server to Root Domain Controller for the new forest.</td>
      <td><a href="images/Automation-stages/Stage3_1-completed.png">Stage 3.1 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>07</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/05_SK_Automation-Host_NodeJoin.ps1"><code>05_SK_Automation-Host_NodeJoin.ps1</code></a></nobr></td>
      <td align="center">Stage 3.2</td>
      <td>Defines AD replication sites/subnets, promotes <code>SRV-DC2</code> as a replica domain controller, and joins member servers and clients to the domain.</td>
      <td><a href="images/Automation-stages/Stage3_2-completed.png">Stage 3.2 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>08</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/06_SK_Automation-Host_CustomConfigs.ps1"><code>06_SK_Automation-Host_CustomConfigs.ps1</code></a></nobr></td>
      <td align="center">Stage 3.3</td>
      <td>Installs and authorizes AD-integrated DHCP on the root DC, builds organisational units (<code>OU=Corp_OU</code>, <code>OU=Corp_Accounts</code>), seeds 10 department test users, and purges setup caches.</td>
      <td><a href="images/Automation-stages/Stage3_3-completed.png">Stage 3.3 Completed</a></td>
    </tr>
    <tr>
      <td align="center"><strong>Config</strong></td>
      <td><nobr><a href="SK-Automation-Scripts/SK_Automation-VMConfig.json"><code>SK_Automation-VMConfig.json</code></a></nobr></td>
      <td align="center">Configuration</td>
      <td>Central JSON configuration file defining hostnames, static IPs, subnet masks, DNS forwarders, and domain roles consumed across all automation stages.</td>
      <td><em>Configuration file</em></td>
    </tr>
  </tbody>
</table>

---

#### Verified Guest Configurations

<table>
  <thead>
    <tr align="center">
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_AD-computer-accounts.png">AD Computer Accounts</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_AD-users.png">AD Users</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DCs.png">Domain Controllers</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DHCP.png">DHCP Scope</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DNS.png">DNS Records</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DNS-Forwarders.png">DNS Forwarders</a></th>
    </tr>
  </thead>
</table>

---

**Author's Note:** AI assistants were utilised during the development of this project to accelerate troubleshooting, refine PowerShell automation and produce documentation.
<br>
You can now go directly to the Prerequisites & Deployment Guide](docs/Project-prerequisites-deployment.md), or you can read through the **[Technical Reference Guide](docs/Technical-Reference.md).

