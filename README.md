> [!NOTE]
> **Work in Progress:** Please report any bugs (broken links) or issues via a support ticket at: [SK-IT Support Portal](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portals).

---

# SK-IT Windows Server 2025 Automation Project 

**Quick Links:** | [Technical Reference](docs/Technical-Reference.md) | [Project Deployment Guide](docs/Project-prerequisites-deployment.md) | [Project Customisation](docs/Customise-your-Infrastructure.md) | [pfSense Configuration](/docs/PfSense-configuration.md) |

---
Welcome to the my Windows Server 2025 automation project.  I hope you find this project helpful.

## Description, Goal and the Future
- **Project Description:** This project provisions, automates, and creates a fully isolated Windows Server 2025 domain environment, including clients, member servers and Domain Controllers. It provisions and builds preconfigured server roles: RootDC, Replica DC and Windows 11 clients. It installs roles, such AD DS, DNS, and DHCP, along with users and organisational units (OUs). The build pipeline uses HashCorps Packer, Visual Studio Code, Hyper-V, pfSense (for network isolation), and PowerShell Direct. It provides a repeatable sandbox for lab testing, certification preparation, and practical hands-on administration.

- **The Goal:** Build a script-based, repeatable, isolated, end-to-end automation pipeline that deploys a Windows Server environment with minimal manual intervention (e.g., executing one line of code and that's it!). The configuration allows users to create multiple forests and domains, customize VM nodes (add and domain join), assign roles (Root DC, Replica DC, Member Server, and Client), and specify Hyper-V VM hardware specifications (vCPUs, dynamic memory, and disk provisioning).

- **Future Roadmap:** Planned updates include an interactive setup mode where users can step through lab settings right in the VS Code terminal (via `Read-Host` prompts) or through a lightweight web form. Linux-based OS automation will also be added to the pipeline.

## How This Project Was Accomplished
I built this project using HashiCorp Packer, which was used create two golden VHDX images: A Windows Server 2025 Datacenter and Windows 11 Enterprise. Both images are fully sysprepped (via pre-configured UK-based unattended.xml files) and include bootstrap scripts that establish the initial communication channels, which pass control to PowerShell Direct after the Packer VHDX stage completes.

PowerShell Direct then executes a sequence of six automation scripts, that continually read from a JSON configuration file, to provision and customize the Hyper-V VMs. These scripts build the AD DS forest and domain, promote the domain controllers, join member servers and clients, and structure the organisational units (OUs) alongside test user accounts.

All stages are coordinated by the One Ring Orchestrator script, which acts as a centralized pipeline controller and single source of authentication, execution, and error handling. Once execution finishes, you have a fully functional Active Directory domain environment running across your Hyper-V host, completely configured and ready for administrative testing, group policy design, and security labs.

---
> [!NOTE]
> For a comprehensive understanding of this automation project, follow the recommended reading path:
> 1. **README** (Overview and project roadmap)
> 2. **Technical Reference Guide** (Architecture, design decisions, and baseline information)
> 3. **Prerequisites & Deployment Guide** (Step-by-step build and project execution that branches out to the pfSense and Customisation guides, at the required stages)
>
> *Short on time? You can skip straight to the Quick Start or Beginner walkthrough in the [Prerequisites & Deployment Guide](docs/Project-prerequisites-deployment.md).*

---

## Project Stages Overview
This automation project is divided into three major deployment stages, coordinated by the master orchestration engine:

🚀 **Deployment Launcher Script (`Deploy_Automation_Project.ps1`):**
This is the script that you run to start the automation. This is executed in PowerShell. It verifies that the orchestrator script exists, and boots the master pipeline orchestrator - The One Ring!

💍 **The Master Orchestrator (`the-one-ring.ps1`):**
Acts as the centralised pipeline controller executed by the deployment script above. It enforces strict fail-fast error handling (`$ErrorActionPreference = "Stop"`) across 3 stages. If the prerequisites,  validation, a Packer build phase, or a PowerShell Direct configuration throws an error, execution halts immediately. Once each stage completes successfully, the pipeline advances automatically to the next stage (script).  The 3 main stages are listed below.

---

### 🟦 Stage 1 — Golden Image Creation Using Packer
- Uses [Packer](build.pkr.hcl) to build fully sysprepped Windows Server 2025 and Windows 11 golden VHDX images from raw ISO media.
- Employs [Packer Variable](variables.pkr.hcl) and XML [Sysprep answer files](templates/Autounattend.pkrtpl.hcl) templates (`Autounattend.pkrtpl.hcl`) to automate disk partitioning, OS edition selection, and regional/local (UK) settings.
- Executes [bootstrap](scripts/bootstrap-winrm-https.ps1) scripts to provision temporary credentials and configure WinRM over HTTPS so Packer can communicate with and sysprep the base OS images.
- Dynamically injects a single set of [administrative credentials](packer.auto.pkrvars.hcl) via `packer.auto.pkrvars.hcl`, eliminating hardcoded passwords across the entire build pipeline.  This one-time injection, of administrative credentials, serves as the main administrative account password for the local and domain account.

**Execution Handover:** With the golden VHDXs sealed and exported into the dynamically created folders, [SK_Automation-host_The-One-Ring.ps1)](SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1) redirects control to the host automation stage to provision the VMs and configure the guest OS instances via PowerShell Direct.

---

### 🟩 Stage 2 — Hyper-V Infrastructure Deployment (Automation Scripts 01–03)
- **[Stage 2.1](SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1) (VM Compute Sizing):** Reads `$VMList` in `01_SK_Automation-Host_CreateVM.ps1` to clone golden VHDX images and create the VM, it configures and allocated vCPUs and RAM, attaches the virtual network adapter to the `lab-switch-lan` switch (connected to pfSense), and boots the VMs.
- **[Stage 2.2](SK-Automation-Scripts/02_SK_Automation-Host_VMConfigTest.ps1) (Readiness Check):** Uses `02_SK_Automation-Host_VMConfigTest.ps1` to verify that each guest OS has finished initial setup and responds over the Hyper-V VMBus via PowerShell Direct, confirming readiness for AD DS deployment.
- **[Stage 2.3](SK-Automation-Scripts/03_SK_Automation-Host_VMConfigDeploy.ps1) (Network & Identity Injection):** Ingests [`SK_Automation-VMConfig.json`](SK-Automation-Scripts/SK_Automation-VMConfig.json) in `03_SK_Automation-Host_VMConfigDeploy.ps1` to assign static IP addresses, default gateways, DNS resolvers, Active Directory site names, and computer hostnames.

---

### 🟪 Stage 3 — Active Directory & Enterprise Customisation (Automation Scripts 04–06)
- **[Stage 3.1](SK-Automation-Scripts/04_SK_Automation-Host_PromoteRootDC.ps1) (Forest Root Bootstrap):** Installs AD DS and DNS server binaries on `SRV-DC1` (dynamically targeted via `"Role": "RootDC"`), builds the customisable forest root (`internal.sk-it.com`), and promotes the local administrator account to Domain Administrator using the credentials defined in `packer.auto.pkrvars.hcl`, which resides in the root directory.
- **[Stage 3.2](SK-Automation-Scripts/05_SK_Automation-Host_NodeJoin.ps1) (Site Topology, Replica DC & Fleet Joins):** Configures the Active Directory site (`Kent-DataCenter`), subnet (`10.0.0.0/24`), and reverse lookup zone on `SRV-DC1`; installs AD DS and promotes `SRV-DC2` (targeted via `"Role": "ReplicaDC"`) as a secondary domain controller for high availability; and joins all member servers (`SRV-EX01`, `SRV-MS01`) and the Windows 11 client (`CLI-WIN11-01`) to the domain.
- **[Stage 3.3](SK-Automation-Scripts/06_SK_Automation-Host_CustomConfigs.ps1) (Enterprise Services, Identity Seeding & Sanitisation):** Installs and authorises an Active Directory-integrated DHCP scope (`10.0.0.0/24`) on `SRV-DC1`, builds the tiered OU hierarchy (`Corp_OU` and `Corp_Accounts`), seeds 10 baseline departmental test users with security groups, and purges setup credential caches (`C:\Windows\Panther`) across all virtual machines.

---

## Background Music While You Build 🎵
How about some background ambience while working through this automation project? Here are a few of my recommended tracks:

<ul>
  <li>🎵 <a href="https://www.youtube.com/watch?v=xAR6N9N8e6U">Deep focus Psy-chill mix</a></li>
  <li>🎵 <a href="https://www.youtube.com/watch?v=KFTZisIh_1Y">Relaxing Celtic ambient soundtrack</a></li>
  <li>🎵 <a href="https://www.youtube.com/watch?v=hXMbcBRS5Ik">Relaxing Cyber-punk soundtrack</a></li>
  <li>🎵 <a href="https://www.youtube.com/watch?v=3F0jjLfSfQo">Relaxing ambient soundtrack</a></li>
  <li>🎵 <a href="https://www.youtube.com/watch?v=8sxhug9byP4">Calming ambient soundtrack</a></li>
</ul>
---

## Pipeline Architecture, Script Manifest & Outputs

   * **Order:** The execution sequence of the scripts.
   * **Script Name:** The filename of each automation script.
   * **Stage:** The associated project deployment phase.
   * **Description:** A concise breakdown of the actions performed during that stage.
   * **Output Capture:** Visual confirmation of Packer and PowerShell Direct terminal output.
   
   **Automation Completed - the finished product:** Images showing the completed Hyper-V environment.

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
      <td> <a href="images/Packer-execution/Stage1_validate-start.png">The One Ring</a></td>
    </tr>
    <tr>
      <td align="center"><strong>02</strong></td>
      <td><nobr><a href="build.pkr.hcl"><code>build.pkr.hcl</code></a></nobr></td>
      <td align="center">Stage 1</td>
      <td>Invokes Packer to perform unattended OS installations, producing clean, sysprepped base VHDXs for Windows Server 2025 and Windows 11.</td>
      <td>
        <a href="images/Packer-execution/Stage1_validate-start.png">Validate Packer Start</a> · 
        <a href="images/Packer-execution/Stage1a_validate-finish.png">Validated</a> · 
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

#### The finished product!

<table>
  <thead>
    <tr align="center">
      <th><a href="href="images/Guest-configuration-validation/Guest-Confirmation_DCs.png">Domain Controllers</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_AD-users.png">AD Users</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_AD-computer-accounts.png">AD Computer Accounts</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DHCP.png">DHCP Installed</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DNS.png">DNS Records</a></th>
      <th>-</th>
      <th><a href="images/Guest-configuration-validation/Guest-Confirmation_DNS-Forwarders.png">DNS Forwarders</a></th>
    </tr>
  </thead>
</table>

---

**Author's Note:** AI assistants were utilised during the development of this project to accelerate troubleshooting, refine PowerShell automation and produce, edit, documentation.
<br>

> [!Note]
> **Environment & Testing:** This automation pipeline was developed and verified in my personal Hyper-V lab environment. While it works reliably in this specific configuration, results may vary depending on local host hardware and virtualization setups. Feedback and issue reports are always welcome!

If you plan to run this automation project, please now have a quick read through the **[Technical Reference Guide](docs/Technical-Reference.md)**, thank you. 

