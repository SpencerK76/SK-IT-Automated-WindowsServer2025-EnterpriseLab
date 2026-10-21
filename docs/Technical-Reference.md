# SK-IT Windows Server 2025 Automation Project :- Technical Reference 


Quick Links: | [Read Me](../README.md) | [Project Customisation](Customise-your-Infrastructure.md) | [pfSense Configuration](PfSense-configuration.md) | [Project Deployment Guide](Project-prerequisites-deployment.md) |

---

# Technical Reference Guide
Welcome to the Technical Reference Guide for the SK-IT Windows Server 2025 Automation Project. This document details the configurable parameters, underlying architecture, and core technologies that drive the deployment pipeline and orchestrate workflows across the entire lab environment.

>[!NOTE] 
> If you want to get your lab operational as quickly as possible, head over to the quick-start or beginner walkthrough in the **[Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md)**. However, if you want a complete, under-the-hood understanding of how the pipeline builds, networks, and provisions these machines, taking the time to read through this technical reference is strongly recommended.


**Personal Note:** I hope you find this automated lab useful! Please feel free to open a support ticket at the [SK-IT Support Portal](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portals) to help with any issues you have or if you want to leave feedback. You could leave feedback on Linkedin as well, which would be much appreciated. You can email me directly with any questions or queries at [spencer@sk-it.co.uk](mailto:spencer@sk-it.co.uk).


### Table of Contents
1. [📁 Repository Structure](#repository-structure)
2. [🖥️ Host Environment & Hardware Sizing](#host-environment)
3. [💾 Storage Planning & Dedicated Drive Placement](#storage-planning)
4. [🛡️ pfSense Network Isolation Guide](#pfsense-network-isolation-guide)
5. [🧑‍💻 Visual Studio Code & Development Tools](#visual-studio-code)
6. [🔑 Administrator Credentials & Single-Injection](#administrator-credentials)
7. [🪟 Windows ISOs, Checksums](#windows-isos)
8. [⚙️ Packer Configuration & Output Customization](#packer-configuration)
9. [🤖 Sysprep and XML Injections ](#automation-pipeline)


## Quick Technology Overview
This section provides a brief technical snapshot of the core technologies, design choices, and architectural considerations implemented across this automation project. More information details information is covered in the sections below.

### 📁 Repository Structure & Storage Planning
The [📁 Repository Structure](#repository-structure) section outlines the complete directory layout for this repository. Review it to gain familiarity with all folders, files and scripts E.g. to check that the media (ISOs) are placed correctly prior to triggering execution.

### 🛡️ Network Isolation Using pfSense
pfSense handles all routing and perimeter isolation for the Hyper-V VMs, ensuring zero traffic, DHCP conflicts, or DNS leakage reach the physical host network. It also provides the capability to configure site-to-site IPsec VPN tunnels, VLAN segmentation, and hybrid cloud connectivity to Microsoft Azure should you need it in the future.

### 💾 Project Storage Requirements & Host Environment
A dedicated 400 GB SSD partition was provisioned specifically for the lab environment to host base VHDXs, raw installation ISOs, and active virtual machines. This allocation provides plenty of headroom for dynamic disk growth, additional node expansion, and multi-forest or multi-domain deployments. 

For detailed storage calculations and hardware breakdowns, see **[💾 Storage Planning & Dedicated Drive Placement](#storage-planning)** and **[🖥️ Host Environment & Hardware Sizing](#host-environment)**.

### ⚙️ Infrastructure Customization
You can tailor the virtual machine infrastructure to match your host hardware capacity:
* **Default 5-Node Topology:** Deploys **2× Domain Controllers** (to test Active Directory replication and high availability), **2× Member Servers** (allocated for Microsoft Exchange, Azure hybrid management, and Microsoft Entra Connect workloads), and **1× Windows 11 Enterprise Client** (for Windows Admin Center, FSLogix user profiles, and Group Policy validation).

* **Minimal Footprint Topology:** If host resources are constrained, you can easily scale down to a lightweight 2-node footprint consisting of a single Domain Controller and one Windows 11 workstation.

Forest and domain namespaces, isolated IP subnets, and Dynamic Memory thresholds are fully configurable to suit your specific testing requirements.

### 🧑‍💻 Visual Studio Code Integration
Visual Studio Code serves as the unified administrative operations console, providing a single code execution point across multiple environments (Windows, Linux, Azure, etc.). For recommended workspace configurations and required extensions, see [🧑‍💻 Visual Studio Code & Development Tools](#visual-studio-code) below.

### 🔑 Administrator Credentials & Windows ISOs
This pipeline has been engineered around a single credential injection point: you declare your administrative password once, and the orchestrator propagates it securely through each stage of the build. 

The evaluation ISOs (Windows Server 2025 and Windows 11) must be downloaded, renamed, and placed into the designated project directory. See [🔑 Administrator Credentials & Single-Injection](#administrator-credentials) and [🪟 Windows ISOs & Checksums](#windows-isos) for detailed setup instructions.

### 🤖 The Automation Pipeline & Sysprep Unattended Considerations
The **[Sysprep and Unattended Configuration Guide](#automation-pipeline)** details the unattended answer files driving automated OS installation and generalization across this project. This section explores how `Autounattend.pkrtpl.hcl` and `unattend.pkrtpl.hcl` orchestrate the initial Windows Setup pass, bypass interactive OOBE prompts, and inject the automation bootstrap scripts prior to VM specialization.

---
<br>

# 1. 📁 Repository Structure <a id="repository-structure"></a>

<details>
<summary><strong>📁 (Click to expand) Verify all files are placed into the correct directories. While folder paths can be customized, this framework operates as a self-contained project; keeping the existing layout is recommended.</strong></summary
<br>
<pre>
Automated-WindowsServer2025-EnterpriseLab/
├── <a href="../.gitignore">.gitignore</a>                                   # Excludes logs, caches, and ISOs
├── <a href="../build.pkr.hcl">build.pkr.hcl</a>                                # Packer VHD build parameters/
├── <a href="../Deploy_Automation_Project.ps1">Deploy_Automation_Project.ps1</a>                # Bootstrap 
├── <a href="../lab-wipe.ps1">lab-wipe.ps1</a>                                 # Teardown tool to delete all VMs 
├── <a href="../LICENSE.txt">LICENSE.txt</a>                                  # Open-source license declaration
├── <a href="../packer-debug.log">packer-debug.log</a>                             # Debug execution output and 
├── <a href="../packer.auto.pkrvars.hcl">packer.auto.pkrvars.hcl</a>                      # Automated variable 
├── <a href="../packer.exe">packer.exe</a>                                   # HashiCorp Packer execution binary
├── <a href="../README.md">README.md</a>                                    # Primary project overview and 
├── <a href="../variables.pkr.hcl">variables.pkr.hcl</a>                            # Custom Parameter 
│
├── docs/
│   ├── <a href="Customise-your-Infrastructure.md">Customise-your-Infrastructure.md</a>          # Guide for tailoring/customising Hyper-V VM 
│   ├── <a href="PfSense-configuration.md">PfSense-configuration.md</a>                  # How to build an isolated 
│   ├── <a href="Project-prerequisites-deployment.md">prerequisites and deployment.md</a>           # Explains the project prerequisites & give deployment instructions 
│   └── <a href="Technical-Reference.md">Technical-Reference.md</a>                    # Detailed architectural & technical manual/guide
│
├── images/
│   ├── Automation-stages                        # Terminal logs and completion captures for pipeline stages
│   ├── Guest-configuration-validation           # Verification screenshots of finished Active Directory services 
|   ├── Hyper-v                                  # Hyper-V Manager settings and virtual switch configurations  
|   ├── Packer-execution                         # Step-by-step console output captures during Packer builds
│
├── ISOs/
│   ├── Win11ClientEntEval.iso                   # Renamed (Win11ClientEntEval) Windows 11 Enterprise evaluation media ISO
│   └── WinServer2025Eval.iso                    # Renamed (WinServer2025Eval) Windows Server 2025 evaluation media ISO
│
├── hyper-VM_source/
│   ├── <a href="../hyper-VM_source/unattend-win11.pkrtpl.hcl">unattend-win11.pkrtpl.hcl</a>                 # Windows 11 automated response template (Sysprep)
│   └── <a href="../hyper-VM_source/unattend.pkrtpl.hcl">unattend.pkrtpl.hcl</a>                       # Server 2025 automated response template (Sysprep)
│
├── Hyper-V_VMs/                                  # Hyper-V VM storage folder - includes config files/VHDXs
│   ├── <a href="../hyper-VM_source/.gitkeep">.gitkeep</a>                                  # gitkeep - keeps the directory so the pipeline does not halt 
|

├── packer_cache/                                 # HashiCorp Packer download cache and temporary working files
│
├── scripts/
│   ├── <a href="../scripts/bootstrap-win11.ps1">bootstrap-win11.ps1</a>                       # Configures WinRM over HTTPS for Packer on Windows 11
│   ├── <a href="../scripts/bootstrap-winrm-https.ps1">bootstrap-winrm-https.ps1</a>                 # Configures WinRM over HTTPS for Packer, disables BL for (Sysprep)
│   ├── <a href="../scripts/cleanup-server2025.ps1">cleanup-server2025.ps1</a>                    # Sysprep cleanup tasks for Windows Server 2025
│   ├── <a href="../scripts/cleanup-win11.ps1">cleanup-win11.ps1</a>                         # Sysprep cleanup tasks for Windows 11
│   └── <a href="../scripts/Environment_Hardware_Specs.ps1">Environment_Hardware_Specs.ps1</a>            # Host hardware audit inspection script
│
├── SK-Automation-Scripts/
│   ├── <a href="../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1">01_SK_Automation-Host_CreateVM.ps1</a>        # Creates VMs based on array list + JSON configuration
│   ├── <a href="../SK-Automation-Scripts/02_SK_Automation-Host_VMConfigTest.ps1">02_SK_Automation-Host_VMConfigTest.ps1</a>    # Tests PowerShell Direct guest connectivity
│   ├── <a href="../SK-Automation-Scripts/03_SK_Automation-Host_VMConfigDeploy.ps1">03_SK_Automation-Host_VMConfigDeploy.ps1</a>  # Injects IPs, gateway, and hostnames via JSON
│   ├── <a href="../SK-Automation-Scripts/04_SK_Automation-Host_PromoteRootDC.ps1">04_SK_Automation-Host_PromoteRootDC.ps1</a>   # Promotes Forest Root DC (SRV-DC1)
│   ├── <a href="../SK-Automation-Scripts/05_SK_Automation-Host_NodeJoin.ps1">05_SK_Automation-Host_NodeJoin.ps1</a>        # Promotes Replica DC & joins member fleet
│   ├── <a href="../SK-Automation-Scripts/06_SK_Automation-Host_CustomConfigs.ps1">06_SK_Automation-Host_CustomConfigs.ps1</a>   # Sets DHCP, Corp OU/Users & purges caches
│   ├── <a href="../SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1">SK_Automation-host_The-One-Ring.ps1</a>       # Master orchestrator (single-click pipeline)
│   └── <a href="../SK-Automation-Scripts/SK_Automation-VMConfig.json">SK_Automation-VMConfig.json</a>               # Manifest defining IPs, hostnames, and AD roles etc
│
└── templates/
    ├── <a href="../templates/Autounattend-Win11.pkrtpl.hcl">Autounattend-Win11.pkrtpl.hcl</a>             # Answer file template for Windows 11
    └── <a href="../templates/Autounattend.pkrtpl.hcl">Autounattend.pkrtpl.hcl</a>                   # Answer file template for Windows Server 2025
</pre>
</details>

---
<br>

# 2. 🖥️ Host Environment & Hardware Sizing <a id="host-environment"></a>
This section outlines the physical host hardware, storage configuration, and core software tooling used to develop and execute this automation project.

### Host Hardware & Storage Baseline
* **Operating System:** Windows 11 Pro (with the Hyper-V role and PowerShell Direct dependencies enabled).
* **Primary Storage:** High-speed NVMe solid-state storage with a dedicated **500 GB partition** allocated exclusively to the project repository, base Packer ISOs, and active virtual hard disks. This provides ample headroom for multi-forest expansion and snapshot testing.

* **Orchestration Environment:** Visual Studio Code (utilising PowerShell 7) serves as the primary console for script execution, parameter adjustments, and pipeline monitoring.

The physical hardware baseline specifications are captured below (my workstation runs an RTX 5090—totally, unnecessary for this automation project, but a flex nonetheless!). 
![Host Environment Hardware Specs](../images/Win11_Client_Specs.png)

### Baseline Capacity & Sizing
The default baseline deployment provisions five virtual machines, consuming roughly **350 GB to 370 GB** of dedicated solid-state storage. Dynamic memory, virtual CPU allocations, and network targets (the pfSense guide will expand on the network aspects) are fully customizable to fit your host capabilities. 

I designed this specific five-node layout (the default layout) to mirror a small, hybrid-ready, enterprise environment topology:  

- **🖥️`SRV-DC1` (Root Domain Controller):** The forest root domain controller hosting Active Directory Domain Services (AD DS), authoritative DNS, and enterprise DHCP scopes.
  ```powershell
  @{Name = "SRV-DC1"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "RootDC"; Forest = "internal.sk-it.com"}
    ```

* **🖥️`SRV-DC2` (Replica Domain Controller):** Secondary domain controller providing directory redundancy, replication and failover testing.

```powershell
    @{Name = "SRV-DC2"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "ReplicaDC"; Forest = "internal.sk-it.com" },
```
* **🖥️`SRV-EX01` (Exchange / Mail Workload Server):** Dedicated member server staged for testing on-premises Microsoft Exchange administration, hybrid mail routing to Exchange Online/Microsoft 365, and recipient attribute management.
```powershell
    @{Name = "SRV-EX01"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "MS"; Forest = "internal.sk-it.com" },
```
* **🖥️`SRV-MS01` (Hybrid Member Server):** Staged for hybrid cloud workloads, Microsoft Entra Connect directory synchronization, Azure Arc agent onboarding, and centralized Windows Admin Center gateway management.
```powershell
    @{Name = "SRV-MS01"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "MS"; Forest = "internal.sk-it.com" }
```
* **🖥️`CLI-WIN11-01` (Windows 11 Enterprise Client):** Domain-joined workstation used to validate Group Policy Objects (GPOs), verify single sign-on (SSO), test software deployment pipelines, and evaluate FSLogix profile containers.
```powershell
    @{Name = "CLI-WIN11-01"; OS = "Win11"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 4GB; VCPU = 2; Role = "Client"; Forest = "internal.sk-it.com" }
```

This setup provides a realistic corporate simulation for day-to-day administration, hands-on lab experiments, certification prep, and hybrid cloud connectivity. It should give you a clear baseline of what this environment achieves and what host resources you need to allocate.

**Sizing Flexibility:** Your physical host does not need to match these exact resource allocations. The lab topology scales dynamically based on your available host RAM, vCPU cores, and disk capacity. If your host has at least **32 GB of RAM** and **350 GB of free NVMe/SSD storage** dedicated to the repository and virtual disks, you can retain all default sizing parameters and simply customize the hostnames, forest namespaces, and domain names to suit your needs.

---
<br>

# 3. 💾 Storage Planning & Dedicated Drive Placement <a id="storage-planning"></a>

This automation framework operates as a **completely self-contained project**. All raw evaluation ISO media, temporary Packer build artifacts, generated golden VHDX templates, and cloned Hyper-V virtual disks reside directly within the root repository structure.  These are listed in the repository folder structure above.

### Storage Capacity Planning (Full Independent Clones)
The pipeline uses **fully independent disk clones**. Each spawned virtual machine receives its own dedicated, dynamically expanding 60 GB generalized VHDX copied directly from the Packer golden image, ensuring complete isolation and independence across all guest nodes.

The default baseline storage footprint breaks down as follows:

* **Windows Server 2025 Golden VHDX:** ~16 GB base template (expands if custom software or cumulative updates are injected into `build.pkr.hcl`). Packer builds and stores the golden VHDX inside `output-ws2025-master-vhd/`.
* **Windows 11 Enterprise Golden VHDX:** ~18 GB base template. Packer builds and stores the golden VHDX inside `output-win11-master-vhd/`.
* **ISO Staging Folder (`ISOs/`):** ~12 GB (holding the official Windows Server 2025 and Windows 11 Enterprise evaluation media downloaded from Microsoft).
* **Provisioned Cloned VMs (`Hyper-V_VMs/`):** Each cloned VM starts around 16–18 GB on physical disk immediately after deployment. You can customize the base disk geometry in Packer as detailed in the **[Infrastructure Customization Guide](Customise-your-Infrastructure.md)**.
* **Default Dynamic Limit (60 GB Max):** Configured in Packer (`disk_size = 61440`, `disk_block_size = 1`), each node uses dynamically expanding VHDXs. While each virtual disk can expand up to a 60 GB ceiling as OS roles, logs, and applications are installed, it only consumes the physical disk space actively written to it.

 **Customization & Overhead:** While each cloned guest disk has a maximum expansion ceiling of 60 GB (350+ GB required by default), actual consumption begins at roughly 15–20 GB per VM upon initial boot. You can adjust this ceiling in the Packer configuration templates (e.g., down to 35–40 GB per node) if host drive capacity is tight. 
  
  The 60 GB default ensures sufficient headroom for Windows updates, Active Directory database growth, and test software. Additional secondary virtual data disks (VHDXs) can be attached via Hyper-V Manager or PowerShell after deployment, of course.
>[!NOTE] 
>**Total Storage Baseline:** This solely depends on what you want to provision for your environment.

**Storage Optimization Tip:** If your physical drive space is limited, you can comment out (`#`) the unneeded hashtables in the `$VMList` array to clone only a single Root DC (`SRV-DC1`) and one Windows 11 workstation (`CLI-WIN11-01`). This minimal setup requires roughly 70–90 GB of total storage (including base ISOs and master templates) while maintaining a fully functional Active Directory test lab.

---
<br>

# 4. 🛡️ pfSense Network Isolation Architecture <a id="pfsense-network-isolation-guide"></a>
Hyper-V virtual switches provide Layer 2 Ethernet frame delivery, while the pfSense appliance, in this automation project, acts as the authoritative Layer 3 perimeter gateway. PfSense runs on FreeBSD, which provisions Hyper-V synthetic network adapters sequentially as `hn0`, `hn1`, and `hn2`.

This framework establishes a strict 1:1 mapping between our Hyper-V virtual switches and pfSense logical interfaces:

| Hyper-V vSwitch | Switch Type | FreeBSD Interface | pfSense Role | Subnet / Addressing | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `lab-switch-wan` | External | `hn0` | WAN | Dynamic (Host DHCP) | Outbound NAT and internet routing via the host adapter. |
| `lab-switch-lan` | Private | `hn1` | LAN | `10.0.0.254/24` | Isolated internal gateway for the Forest (`internal.sk-it.com`). |

```powershell
#Hashtable in the $VMList array.
    @{Name = "SRV-DC1"; OS = "Win2025"; Switch="lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "RootDC"; Forest = "internal.sk-it.com" },
```

### Why Network Isolation Matters in this automation project:

* **DHCP Collision Prevention:** Placing `lab-switch-lan` on a **Private** Hyper-V virtual switch physically prevents Active Directory Domain Controllers (`SRV-DC1` and `SRV-DC2`) from broadcasting DHCP offers into my home local network.
* **Stateful Outbound Routing:** pfSense provides stateful firewall filtering and Network Address Translation (NAT), allowing lab virtual machines to pull updates and packages from the internet while remaining completely unreachable from your local physical LAN.
* **Script Dependency:** The switch names `lab-switch-wan` and `lab-switch-lan` are hard-coded into the pre-flight checks of `01_SK_Automation-Host_CreateVM.ps1`. While configurable, keeping these exact names avoids having to refactor the orchestration scripts.

*(A detailed, step-by-step setup of the pfSense ISO, FreeBSD interface bindings, and firewall rule configurations is covered in the dedicated pfSense Configuration Guide you will view later.

---
<br>

# 5. 🧑‍💻 Visual Studio Code & Project Orchestration <a id="visual-studio-code"></a>
In this automation framework, Visual Studio Code functions as the central operations console. Rather than switching between the Hyper-V Manager GUI, administrative PowerShell consoles, and text editors, all pipeline stages are monitored, configured, and triggered directly within the project’s root workspace.

### How VS Code Drives This Project Pipeline

* **Executing the Deployment Scripts:** The integrated terminal is where the host-level automation scripts (`01_SK_Automation-Host_CreateVM.ps1`, post-deployment tasks, and VM health checks) run. Because these scripts configure Hyper-V vSwitches, mount VHDXs, and push commands into guest VMs via PowerShell Direct, the VS Code process must run with elevated administrator privileges.

* **Real-Time Packer Build Monitoring & Orchestration:** When `Deploy_Automation_Project.ps1` executes, it performs pre-flight validation to verify that the orchestrator engine is active, sets `$env:PACKER_LOG=1`, and initiates the Packer build pipeline. Exposing the full trace log inside the console is critical during image baking to monitor:
  * **Ephemeral HTTP Server Binding:** Tracks the local HTTP listener as it serves the project's four tailored `Autounattend.xml` answer files directly to the initializing virtual machines.
  * **WinRM Handshake Polling:** Displays live connection retries over WinRM while the specialized guest operating system completes OOBE and initializes WinRM listeners for post-installation scripts.

 Please view the **Pipeline Architecture, Script Manifest & Outputs** section in the README page for images pertaining to the VS Code outputs during the Packer build stage 1. 

* **Workspace File & Variable Management:** The single VS Code workspace keeps the entire automation stack aligned in one tree. It allows instant cross-editing between the Packer templates (`build.pkr.hcl`), the unattended XML templates (`.pkrtpl.hcl`), the VM list array hashtables (`$VMList`), and the Active Directory bootstrap scripts without navigating detached file explorer paths.

#### (Step-by-step setup—including repository cloning, setting your PowerShell execution policy, downloading the Packer binary, and staging ISO files—is detailed in the **[Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md)**).
---
<br>

# 6. 🔑 Administrator Credentials <a id="administrator-credentials"></a>
To make this automation project seamless, I wanted to eliminate the frustration of re-typing passwords across multiple scripts. In a lab environment, repeatedly typing credentials invites typos, breaks unattended runs, and normally means hardcoding plain-text passwords.

Instead, this automation pipeline uses an single injection point: you declare your administrator password once, and the master orchestrator `(SK_Automation-host_The-One-Ring.ps1)` carries it securely through every stage of the build:

* **Stage 1:** Base golden image creation (Packer WinRM & initial local admin)
* **Stage 2.1:** Hyper-V VM provisioning & disk cloning
* **Stage 2.2:** Guest connectivity verification via PowerShell Direct
* **Stage 2.3:** Network identity & hostname injection
* **Stage 3.1:** Forest root bootstrap & promotion to Domain Admin
* **Stage 3.2:** Replica DC promotion & member fleet domain joins
* **Stage 3.3:** Enterprise service configuration, user account seeding & credential sanitization

>[!NOTE]
>Please make sure your password meets the complexity requirements of the AD DS password policy. Strong passwords require a combination of uppercase and lowercase letters, numbers, and symbols.
If you do not, the automation process will halt during the configuration of the Directory Services Restore Mode, which requires a password meet standard complexity requirements.

---
<br>

# 7. 🪟 Windows ISO Media & Checksum Verification <a id="windows-isos"></a>
Packer requires local access to official Microsoft evaluation media to build the golden VHDX templates. To ensure automated builds remain fully repeatable and protected against data corruption, the pipeline pairs fixed file path naming with checksum validation.

### Required Base Media
The deployment pipeline is built and validated against the following specific editions (download links provided in the deployment guide!):
- **Windows Server 2025 Datacenter (Desktop Experience):** Base operating system for domain controllers and member servers.
- **Windows 11 Enterprise (English - UK):** Base operating system for administrative workstations and client nodes.

### Standardized Naming Convention
Downloaded ISO files must be placed directly inside the `ISOs/` root directory using the exact filenames declared in `variables.pkr.hcl`:

- `ISOs/WinServer2025Eval.iso`
- `ISOs/Win11ClientEntEval.iso`

### Checksum Verification
Packer validates the integrity of each image against a known SHA-256 hash before provisioning the temporary Hyper-V virtual machine. You can verify your local file hashes prior to running the build using PowerShell:

```powershell
Get-FileHash -Path ".\ISOs\WinServer2025Eval.iso" -Algorithm SHA256
Get-FileHash -Path ".\ISOs\Win11ClientEntEval.iso" -Algorithm SHA256
```

> [!TIP]
> **Need to alter the default file names or storage targets?**
> If your environment requires non-standard ISO file names, external network shares, or alternative destination folders for the generated templates, see the **[Customizing ISO Names, Golden VHDX Paths & Output Folders](Customise-your-Infrastructure.md)** section in the Customisation Guide.

---

<br>

# 8. ⚙️ Packer Configuration <a id="packer-configuration"></a>
HashiCorp Packer automates the base operating system build pipeline, producing fully Sysprepped, generalized VHDX master images. Once a build completes, Packer exports the finalized virtual disks into their respective staging directories. From there, the host provisioning scripts clone these images to spawn the VM lab nodes, handing execution over to PowerShell Direct - via the Hyper-V VMBus, not the network - to orchestrate guest configuration completely hands-free.

To inspect or review the hardware sizing, boot command sequences, answer file injection, or Sysprep parameters, refer to **[`build.pkr.hcl`](../build.pkr.hcl)**. Like every script in this repository, it contains extensive inline documentation for each block. 

The core architectural sections of **[`build.pkr.hcl`](../build.pkr.hcl)** are detailed below:

---

### SECTION 1: PACKER ENGINE & PLUGIN SETUP
* Declares the minimum required Packer core engine version (`>= 1.10.0`) and pulls the official HashiCorp Hyper-V builder plugin (`hashicorp/hyperv`) required to interface with the local hypervisor.

### SECTION 2: BUILDER SOURCE (Windows Server 2025)
* Configures the automated generation of the Windows Server 2025 Datacenter (Desktop Experience) master VHDX.
* Defines the baseline Generation 2 virtual hardware profile (RAM, vCPUs, dynamic disk parameters).
* Attaches the unattended ISO installation media (`templates/Autounattend.pktrpl.hcl`) to automate disk partitioning and bypass initial setup screens.
* Establishes a temporary self-signed WinRM HTTPS listener (via `scripts/bootstrap-winrm-https.ps1`) for Packer communicator access.
* Executes Sysprep generalization (`sysprep.exe /generalize /oobe /shutdown`) to seal the master image.

### SECTION 3: BUILDER SOURCE (Windows 11 Enterprise)
* Mirrors Section 2 but targets Windows 11 Enterprise evaluation media, incorporating specific platform parameters:
* Configures vTPM and Secure Boot prerequisites required for Windows 11 Generation 2 VM deployment.
* Bypasses client-specific OOBE hardware gating and Microsoft Account (MSA) setup prompts via `templates/Autounattend-Win11.pkrtpl.hcl`.
* Configures the client WinRM provisioning channel via `scripts/bootstrap-win11.ps1`.

### SECTION 4: PROVISIONING PIPELINE
* Executes in-guest servicing, tooling injection, and pre-sealing tasks on both master images before final shutdown:
* **Tooling Injection:** Bakes administrative software (such as PowerShell 7) directly into the image so nodes boot ready for enterprise automation.
* **OS Sanitization:** Invokes `scripts/cleanup-server2025.ps1` and `scripts/cleanup-win11.ps1`. On Windows 11, this specifically decrypts pre-provisioned BitLocker volumes and strips provisioned AppX packages that commonly block Sysprep generalization.
* **Answer File Staging:** Injects credential-templated `unattend.xml` answer files directly into `C:\Windows\Panther\` on each master VHDX, readying them for instant specialization during Stage 2 cloning.

---

<br>

# 9. 🤖 Sysprep & Answer File Injection Architecture <a id="automation-pipeline"></a>
To achieve a completely hands-free build, this project uses dynamic Packer HCL templates (`.pkrtpl.hcl`) to automate Windows Setup across two distinct provisioning stages.

## The Unattended Automation (Sysprep & OOBE)
Unattended answer files handle OS setup and guest preparation across two key phases:

1. **Initial OS Installation ([`Autounattend.pkrtpl.hcl`](../templates/Autounattend.pkrtpl.hcl) and [`Autounattend-Win11.pkrtpl.hcl`](../templates/Autounattend-Win11.pkrtpl.hcl) via Packer):** Automates the setup directly from the downloaded evaluation ISOs. This stage formats the virtual disk, selects the target OS index, applies UK regional settings, and enables temporary WinRM access for Packer.

2. **First-Boot Customisation ([`unattend.pkrtpl.hcl`](../hyper-VM_source/unattend.pkrtpl.hcl) and [`unattend-win11.pkrtpl.hcl`](../hyper-VM_source/unattend-win11.pkrtpl.hcl) via Sysprep):** Runs during the Out-of-Box Experience (OOBE) when a cloned VM first boots in Hyper-V. It generates unique machine SIDs, configures the local administrator credentials, and readies the system for PowerShell Direct management.

### Project Template Files
- **[`Autounattend.pkrtpl.hcl`](../templates/Autounattend.pkrtpl.hcl)**
  * **Stage:** OS installation for Windows Server 2025 Datacenter (Desktop Experience - `IMAGE_INDEX 2`).
  * **Role:** Partitions the virtual disk, selects the Server 2025 image, applies UK regional settings, and configures WinRM for Packer provisioning.

- **[`Autounattend-Win11.pkrtpl.hcl`](../templates/Autounattend-Win11.pkrtpl.hcl)**
  * **Stage:** OS installation for Windows 11 Enterprise (`IMAGE_INDEX 3`).
  * **Role:** Partitions the virtual disk, bypasses consumer OOBE checks, applies UK regional settings, and configures WinRM for Packer provisioning.

- **[`unattend.pkrtpl.hcl`](../hyper-VM_source/unattend.pkrtpl.hcl)**
  * **Stage:** Sysprep & First Boot (Server Clones).
  * **Role:** Applied during server generalization to assign unique SIDs, set permanent local administrator credentials, and enable PowerShell Direct for post-deployment scripts.

- **[`unattend-win11.pkrtpl.hcl`](../hyper-VM_source/unattend-win11.pkrtpl.hcl)**
  * **Stage:** Sysprep & First Boot (Client Clones).
  * **Role:** Applied during client generalization to assign unique SIDs, configure local administrator credentials, bypass Microsoft account requirements, and enable PowerShell Direct.

>[!NOTE]
>The `.pkrtpl.hcl` extension designates these as Packer HCL templates rather than static XML files. This approach keeps the XML definitions modular, reusable, and free of plaintext secrets. Sensitive variables are populated dynamically at runtime from **[`packer.auto.pkrvars.hcl`](../packer.auto.pkrvars.hcl)**. You only define credentials once during setup, and these become your primary administrative login credentials across the domain. 

This pipeline enforces a multi-stage cleanup process that purges all traces of these setup answer files:

   * Stage 1 (Sysprep Image Sealing): Cleans initial Panther caches and unmounts the virtual media hosting the xml files.

   * Stage 2 (Hyper-V Specialization): Windows processes Sysprep specialization on first boot, temporarily generating local setup cache files.

   * Stage 3.3 (Node-Wide Sanitization): Explicitly purges remaining setup XML files and sanitizes C:\Windows\Panther\ across all provisioned virtual machines.  (`06_SK_Automation-Host_CustomConfigs.ps1 > Part C`) as the last stage in the automation process.
---

This concludes the Technical Reference Guide. You should now have a solid understanding of each architectural stage underpinning this automation project pipeline. 

Please proceed to the **[Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md)** to configure your environment and begin deploying your lab (finally!).