# Windows Server 2025 Automation Project:- Customising Your Infrastructure

**Quick Links:** | [Read Me](../README.md) | [pfSense Configuration](PfSense-configuration.md) | [Project Deployment Guide](Project-prerequisites-deployment.md) | [Technical Reference](Technical-Reference.md) |

---

# Customising Your Hyper-V Infrastructure

The deployment pipeline defaults to provisioning five isolated Hyper-V virtual machine nodes: two Domain Controllers, two Member Servers, and one Windows 11 Enterprise Client. These are defined and instantiated via **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)**. 

At initial deployment, this topology requires approximately **100–120 GB** of free disk space, expanding dynamically up to a recommended operational ceiling of **350+ GB** as services and lab data grow.

If you are deploying the default topology, you only need to adjust hardware resource allocations (such as RAM and vCPU count), Active Directory domain/forest names, and IP addressing parameters. Before launching the deployment orchestrator, ensure your Hyper-V virtual switches are created and their IP address assignments match the pfSense configuration and the names are correct in the match in the `01_SK_Automation-Host_CreateVM.ps1` and the `SK_Automation-VMConfig.json` configuration scripts.

---

### Table of Contents
1. [🖥️ Customise the Packer VHDX Master Image Size](#customise-the-packer-vhdx-master-image-size)
2. [🐈‍⬛ Customising ISO Names, VHDX Paths, Output Folders and Admin Credentials](#custom-iso-paths)
3. [📦 Customise VM Node Counts & Hardware Sizing](#customise-vm-node-counts--hardware-sizing)
4. [🪟 Customise VM & Domain Networking Settings](#customise-vm--domain-networking-settings)
5. [🌲 Create Additional Forests & Domains](#create-additional-forests--domains)
6. [💾 Storage Planning & VM Disk Placement](#storage-planning--dedicated-drive-placement)
7. [🚫 Common Mistakes to Avoid](#common-mistakes-to-avoid)

<br>

---

### Pre-Customisation Checklist
Before modifying configuration scripts or launching a customized build, verify the following baseline requirements:

* **Host Prerequisites:** Hyper-V and PowerShell 7 are configured with appropriate script execution policies.
* **Perimeter Routing:** The pfSense firewall VM is active and successfully routing outbound internet traffic for the internal isolated LAN.
* **Virtual Switches:** Both `lab-switch-wan` and `lab-switch-lan` exist in Hyper-V Virtual Switch Manager with exact casing, and are tied to the pfSense VM via vNICs.
* **Topology Planning:** You have mapped your planned node hostnames, IP schemes, AD roles, and forest/domain namespaces - making sure you have the host resources.
* **Storage Allocation:** At least **350 GB** of free solid-state storage is available on the target deployment drive if you plan to run the default automation (only changing the host/forest/domain names).

---
<br>

## 1. 🖥️ Customise the Packer VHDX Master Image Size <a id="customise-the-packer-vhdx-master-image-size"></a>
The base virtual disk size for both the Windows Server 2025 and Windows 11 templates is declared inside build.pkr.hcl under the storage configuration block.

By default, the virtual disk maximum ceiling is configured to 60 GB (61440 MB). You can adjust the default sysprepped VHDX image size here, but ensure you account for minimum operating system requirements and future update headroom:

```HCL
# --- Virtual Hard Disk (Storage) ---
  disk_size               = 61440  # 60 GB vDisk maximum capacity
  disk_block_size         = 1      # 1 MB block size
```
>[!NOTE]
>Dynamic Disk Expansion: This setting defines the maximum capacity ceiling, not the upfront storage footprint. Because Packer outputs dynamically expanding VHDX files, the resulting base images only consume approximately 15–18 GB of physical disk space after creation.

---
<br>

## 2. 👩‍💻 Customizing ISO Names, Golden VHDX Paths & Output Folders <a id="custom-iso-paths"></a>
If you use differently named Windows ISO files or need to redirect Packer outputs to another storage volume (not recommended), update the media variable declarations and the downstream VM provisioning script.

### ➡️ 2a. Update Media & Output Variables
By default, the Packer build templates expect specific evaluation ISO filenames located in the `ISOs/` directory and export the finalized master VHDX images into local project, dynamically created, subfolders (`default="./output-ws2025-master-vhd"`). 

If your ISO files use different names, if you are sourcing retail or volume-licensed media, or if you need to direct the final master images to an alternate high-capacity drive, update the media paths and destination directories.

These variables are declared in **[`variables.pkr.hcl`](../variables.pkr.hcl)** and can be cleanly overridden without modifying core templates inside **[`packer.auto.pkrvars.hcl`](../packer.auto.pkrvars.hcl)**:

```hcl
# ------------------------------------------------------------------------------
# Windows Server 2025 Media & Output
# ------------------------------------------------------------------------------
variable "iso_url" {
  type        = string
  description = "Path to the Windows Server 2025 installation ISO"
  default     = "ISOs/WinServer2025Eval.iso" # Change ISO path/filenames here!
}

variable "output_directory" {
  type        = string
  description = "Destination folder for finalized Server 2025 master VHDX"
  default     = "./output-ws2025-master-vhd" # Change Sysprep output directory
}

# ------------------------------------------------------------------------------
# Windows 11 Media & Output
# ------------------------------------------------------------------------------
variable "iso_url_win11" {
  type        = string
  description = "Path to the Windows 11 installation ISO"
  default     = "ISOs/Win11ClientEntEval.iso" # Change ISO path/filename
}

variable "output_directory_win11" {
  type        = string
  description = "Destination folder for finalized Windows 11 master VHDX"
  default     = "./output-win11-master-vhd"  # Change output directory
}
``` 
* `ISOs/WinServer2025Eval.iso`  # Please rename your Windows 2025 ISO to this, or change the variable value above
* `ISOs/Win11ClientEntEval.iso` # Please rename your Windows 11 client ISO to this, or change the variable value above

> [!WARNING]
> The Packer build templates reference these relative paths and file names directly. Renaming these files requires updating the corresponding `iso_url` variables inside the (`variables.pkr.hcl`): configuration file.

<br>

### ➡️ 2b. Custom ISO Checksums
If you use custom or updated ISO images, calculate their SHA-256 hash and update the corresponding variables in **[`packer.auto.pkrvars.hcl`](../packer.auto.pkrvars.hcl)**:

```hcl
iso_checksum        = "sha256:YOUR_SERVER_2025_SHA256_HASH_HERE"
iso_checksum_win11  = "sha256:YOUR_WIN11_SHA256_HASH_HERE"
```

```Powershell
# Check your Windows Server 2025 ISO Hash
Get-FileHash -Path .\ISOs\WinServer2025Eval.iso -Algorithm SHA256 | Select-Object -ExpandProperty Hash
# Check Windows 11 Enterprise ISO Hash
Get-FileHash -Path .\ISOs\Win11ClientEntEval.iso -Algorithm SHA256 | Select-Object -ExpandProperty Hash
```
>[!NOTE]
>If you are testing media and do not want strict hash enforcement during experimental runs, Packer allows iso_checksum = "none", though specifying a valid SHA-256 hash is strongly recommended for production consistency.

<br>

### ➡️ 2c. Update Host Provisioning Paths
If you altered the Packer output directories or target VHDX filenames in Step 2a, you must synchronize those changes with the Hyper-V host deployment script. During the deployment phase, the host provisioning engine references this hashtable to locate the sysprepped golden templates and clone them into individual virtual machines.

Found in **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)**:

```powershell
# Explicit VHDX mappings — using OS tags — to actual Packer output VHDX filenames
$GoldenImages = @{
    "Win2025" = Join-Path $ProjectRoot "output-ws2025-master-vhd\Virtual Hard Disks\Win2025-GoldenImage-Build.vhdx"
    "Win11"   = Join-Path $ProjectRoot "output-win11-master-vhd\Virtual Hard Disks\Win11-GoldenImage-Build.vhdx"
}
```
>[!NOTE]
>Changing where the master disks are generated means you must update these child paths so the cloning engine can find them. Leaving the default, self-contained project paths intact is recommended. The hashtable keys ("Win2025" and "Win11") are hardcoded references mapped to the $VMList deployment array; modify only the destination paths on the right, never the keys themselves.

<br>

### ➡️ 2d. 👩‍💻 Change the Hyper-V VM Output Location
By default, the deployment script stores all provisioned virtual machines and their cloned runtime VHDX disks in a local project folder (in the root repository) named `Hyper-V_VMs`. 

If your primary OS drive has limited storage and you want to host running virtual machines on a separate high-speed NVMe, SSD, or dedicated lab volume (for example, `D:\Hyper-V_VMs`), update the target base directory.

Found in **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)**:

```powershell
# Target directory where individual VM configuration folders and cloned VHDXs reside
$VMPath = Join-Path -Path $ProjectRoot -ChildPath "Hyper-V_VMs" # variable stating root directory Hyper-V_VMs
if (-not (Test-Path -Path $VMPath)) {
    New-Item -ItemType Directory -Path $VMPath -Force | Out-Null # if directory is not there, create it. 
    #However, I added a .gitkeep to this directory, so the gitignore will not push any files inside this directory!
}
```
> [!TIP]
> To route virtual machines to an absolute storage path on a dedicated drive, replace the `Join-Path` assignment directly with your target drive path (for example, `$VMPath = "D:\Hyper-V_VMs"`). The script will automatically verify the folder and create it if it does not already exist.

<br>

### ➡️ 2e. 🔐 Customise Root Administrator Credentials
The credentials configured in **[`packer.auto.pkrvars.hcl`](../packer.auto.pkrvars.hcl)** establish the baseline identity across the entire automated deployment pipeline. 

Packer injects these values into the unattend files during guest operating system setup. Later, when **[`04_SK_Automation-Host_PromoteRootDC.ps1`](../SK-Automation-Scripts/04_SK_Automation-Host_PromoteRootDC.ps1)** bootstraps the root domain, this account is elevated to the Domain Administrator for the forest:

```hcl
# ------------------------------------------------------------------------------
# Root Automation Credentials
# ------------------------------------------------------------------------------
admin_username = "Administrator"
admin_password = "YourSecurePassword123!"
```

> [!IMPORTANT]
> Windows Server 2025 enforces default Active Directory password complexity policies during domain controller promotion. If you modify `admin_password`, please ensure it contains at least 8 characters with a mix of uppercase letters, lowercase letters, numerals, and special characters. Avoid quotation marks (`"`) or backslashes (`\`) inside the string to prevent parsing and unescape errors across PowerShell Direct sessions.

**The Master Orchestrator's [`The One Ring`](../SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1)**. When you launch the automated build via **`SK_Automation-host_The-One-Ring.ps1`**, the orchestrator parses `admin_username` and `admin_password` directly from `packer.auto.pkrvars.hcl` at runtime. It constructs secure credential objects in memory and injects them across the deployment pipeline (each scripts execution) to authenticate PowerShell Direct sessions, bootstrap the forest root DC, promote replica domain controllers, and join member servers without ever prompting you for a manual login.

**Active Directory DSRM & Recovery Services:** In addtion to becoming the local/domain password, this password also becomes the default Directory Services Restore Mode (**DSRM**) password during AD DS forest promotion in `04_SK_Automation-Host_PromoteRootDC.ps1`. If Active Directory database maintenance, offline repair, or disaster recovery boots are required in the future, use this credential to log in locally to the recovery environment.

---
<br>

## 3. 📦 Customise the Number of VM Nodes Created <a id="customise-the-number-of-vm-nodes-created"></a>

If you want to scale the VM node count up or down (adding or removing servers and client VMs) or adjust memory to match your workstation's capacity, you must update TWO synchronised files. This is where you add or remove hashtable entries from the `$VMList` array and plan your forest and domain topology.

**File 1:** Open **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** and edit the `$VMList` array to define your Hyper-V VM names, memory limits (`MemStart`, `MemMin`, `MemMax`), virtual CPU count (`VCPU`), and assigned Hyper-V vSwitch (`lab-switch-lan`). For details on switch assignments, see the **[pfSense Configuration Guide](PfSense-configuration.md)**. Base these settings on the lab blueprint you mapped out.  You can add to the hashtable, or comment out "#".  

**File 2:** Open [`SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)** and define, replicate, the entries in File 1.

The downstream domain deployment scripts, such as `03_SK_Automation-Host_VMConfigDeploy.ps1`, read and query these exact domain definitions to orchestrate and promote your forest roots, child domains, and trust topologies.

```Powershell
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers - used for replication / HA etc..
    @{Name = "SRV-DC1"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "RootDC"; Forest = "internal.sk-it.com" },
    @{Name = "SRV-DC2"; OS = "Win2025"; Switch = "lab-switch-lan"; MemStart = 4GB; MemMin = 2GB; MemMax = 6GB; VCPU = 4; Role = "ReplicaDC"; Forest = "internal.sk-it.com" },
``` 
```JSON
"VMs": [
    {
            "HyperVName": "SRV-DC1",
            "OSHostName": "SRV-DC1",
            "Role": "RootDC",
            "Forest": "internal.sk-it.com",
            "DomainName": "internal.sk-it.com",
            "Site": "Kent-DataCenter",
            "Subnet": "10.0.0.0/24",
            "IP": "10.0.0.1",
            "Prefix": 24,
            "Gateway": "10.0.0.254",
            "DNS": ["127.0.0.1","8.8.8.8"],
            "NetBIOSName": "INTERNAL"
        },
        {
            "HyperVName": "SRV-DC2",
            "OSHostName": "SRV-DC2",
            "Role": "ReplicaDC",
            "Forest": "internal.sk-it.com",
            "DomainName": "internal.sk-it.com",
            "Site": "Kent-DataCenter",
            "Subnet": "10.0.0.0/24",
            "IP": "10.0.0.2",
            "Prefix": 24,
            "Gateway": "10.0.0.254",
            "DNS": ["10.0.0.1","8.8.8.8"],
            "NetBIOSName": "INTERNAL"
        },

```

>[!NOTE]
>**Role Attribute Note:** The `Role` attribute inside each VM hash table entry is critical to the automation pipeline. It determines what configuration tasks each node will execute during deployment. These values must remain consistent across both configuration files (`Host_CreateVM.ps1` & `VMConfig.json`)  because they define the server roles being provisioned. 

For example, `RootDC` identifies the Forest Root Domain Controller, `ReplicaDC` identifies secondary domain controllers, and `MS` identifies member servers. The automation scripts query these `Role` values dynamically rather than relying on a hardcoded list of server names. 

This allows you to add or remove VM entries(server nodes) freely without breaking or halting the pipeline, as the workflow adapts automatically based on the roles present. This allows you to easily add a server/client to the domain after you have created your infrastructure.

You can run the automation pipeline again at any time to scale your lab by appending additional nodes to the `$VMList` array. 

* **Scale-Out Roles (`ReplicaDC`, `MemberServer`, `Win11`):** You can add as many replica domain controllers, member servers, and client workstations as your physical host hardware can support. Each new entry must have a unique `VMName`, dedicated IP address, and appropriate subnet assignment.
* **Singleton Role (`RootDC`):** You **cannot** declare more than one `RootDC` per forest. Active Directory permits only one forest root domain controller to bootstrap the root namespace and host the foundational forest-wide FSMO roles; every subsequent domain controller in that domain must be declared as a `ReplicaDC`. But, you already knew this!

### 📦 Example: Scaling Out Existing Topology

Open **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** and edit the `$VMList` array:
```powershell
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers (e.g., RootDC and secondary ReplicaDC)
    @{Name="SRV-DC3";   OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="ReplicaDC"; Forest="internal.sk-it.com"},
    @{Name="CLI-WIN11-02"; OS="Win11"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=4GB; VCPU=2; Role="Client"; Forest="internal.sk-it.com"}
)
```
Then run the deployment again. In this scenario, you are adding another ReplicaDC server and a Windows client to the existing Forest/Domain (internal.sk-it.com).

> [!WARNING]
> **Keep Array and Configuration in Sync:** After you have changed the array list, those changes **MUST** be reflected in **[`SK_Automation-VMConfig.json`](../SK_Automation-VMConfig.json)** as well. The guest configuration and provisioning stages rely on this JSON file to map network interfaces, IP addresses, DNS settings, and domain join operations.

This is all based on your lab blueprint and the amount of host resources you have. You could run the automation project just once provisioning a minimal footprint (such as 1 DC and 1 Windows client), or scale up to 1 RootDC, 3 Replica DCs, and 5 Windows clients if you have the hardware space and resources.

> [!NOTE]
> **Console Warnings During Incremental Runs:** If you re-run the automation scripts to append new nodes to an existing forest, the host terminal may display non-terminating warnings or skipped notices as the scripts iterate over already provisioned virtual machines. This is expected behavior—the automation detects that existing VMs, disks, and domain records are already present and skips them. **Do not remove existing nodes from `$VMList` or `SK_Automation-VMConfig.json`**, as subsequent join and replication steps still require the full inventory to resolve upstream domain controllers.

<br>

### 📦 Adding Servers & Clients Without Rebuilding Packer Images
Re-running the entire Packer build phase just to scale out nodes is unnecessary if you already have valid golden master images available. 

To bypass the time-consuming OS installation and Sysprep stages, use the `$SkipPackerBuild` switch parameter in **[`SK_Automation-host_The-One-Ring.ps1`](../SK-Automation-Scripts/SK_Automation-host_The-One-Ring.ps1)**:

```powershell
param(
    [switch]$SkipPackerBuild = $true
)
```
This bypasses the Packer build phase entirely and jumps straight to the Hyper-V cloning and PowerShell Direct automation steps using your existing master VHDXs. 

### 📦 Adding your own Sysprepped VHDX
You can drop your own pre-built, Sysprepped VHDX images directly into the project output directories to bypass the Packer generation phase entirely:

```text
# Target destination directories (as declared in variables.pkr.hcl):
./output-ws2025-master-vhd/Virtual Hard Disks/Win2025-GoldenImage-Build.vhdx
./output-win11-master-vhd/Virtual Hard Disks/Win11-GoldenImage-Build.vhdx

# variables.pkr.hcl
variable "output_directory" {
  type        = string
  description = "Target destination folder where the finalised Windows Server 2025 master VHDX is exported."
  default     = "./output-ws2025-master-vhd" # output folder is automatically created in the root.
}

variable "win11_output_directory" {
  type        = string
  description = "Target destination folder where the finalized Windows 11 master VHDX is exported."
  default     = "./output-win11-master-vhd"
}
```
If bringing custom images, they must meet these requirements to work with downstream automation:

   * Generation 2 (UEFI): Must use GPT partition layouts compatible with Hyper-V Gen 2 VMs.
   * Generalised via Sysprep: Sealed using /generalize /oobe /shutdown to ensure clean identity regeneration upon boot.
   * Matching Local Administrator: The local Administrator account must match the credentials declared in packer.auto.pkrvars.hcl.
   * WinRM & PowerShell Direct Enabled: Remote management services must be running so the host scripts can connect.

> [!TIP]
> Instead of manually importing external VHDX files, it is usually much easier to customize the existing Packer pipeline. You can add extra applications directly to the `provisioner` blocks in the Packer templates, or edit the setup scripts in `scripts/` (just ensure you preserve the initial bootstrap commands so PowerShell Direct and WinRM stay functional).

<br>

---

## 4. 🪟 Customise VM & Domain Networking Settings <a id="customise-vm--domain-networking-settings"></a>
Both the Forest and Domain names are mapped directly inside the configuration file 1, 2 detailed below. The IPv4 addressing scheme you configure for your virtual machines **MUST** strictly align with the subnet definitions and interface gateways established inside pfSense:

* **Default Gateway Alignment:** The gateway IP assigned to any VM must match the static interface IP configured on the pfSense virtual firewall for that network segment.
* **Hyper-V vSwitch Association:** For VMs connected to `"lab-switch-lan"`, the gateway points directly to the pfSense LAN interface IP bound to the underlying Hyper-V synthetic network adapter (`hn1`).

> [!WARNING]
> **Subnet & Gateway Mismatch:** If a VM's assigned static IP or default gateway does not match the subnet configured on its associated pfSense vNIC, the node will lose routing to the firewall. This breaks internet access for package updates, prevents inter-VLAN routing, and stops cross-forest domain trusts from establishing.

```powershell
# File 1: SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1 ($VMList Entry)
@{Name="SRV-DC1"; OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="internal.sk-it.com"},

#File 2 .SK_Automation-VMConfig.json
  "Environment": "VM Guest Configuration",
  "GlobalAdmin": "Administrator",
  "VMs": [
    {
      "HyperVName": "SRV-DC1",  
      "OSHostName": "SRV-DC1",
      "Role": "RootDC",
      "Forest": "internal.sk-it.com",
      "DomainName": "internal.sk-it.com",
      "Site": "Kent-DataCenter",
      "Subnet": "10.0.0.0/24",
      "IP": "10.0.0.1",
      "Prefix": 24,
      "Gateway": "10.0.0.254",  #this is the default gateway IP for each VM in the Forest 
      "DNS": ["127.0.0.1", "8.8.8.8"],
      "NetBIOSName": "INTERNAL"
    }

#  Attributes Explained
#When customising your lab's IP addressing, keep these rules in mind:

- HyperVName & OSHostName: Must match the Name property in $VMList. The scripts use this identity to locate the VM over Hyper-V VMBus and rename the internal Windows computer name.
- Role: Must match the $VMList role (RootDC, ReplicaDC, MS, or Client). This controls which Stage 3 bootstrap script executes inside the guest.
- Subnet & Prefix: Must align with the isolated subnet managed by your pfSense LAN interface (10.0.0.0/24).
- Gateway: Must point directly to the pfSense LAN interface IP address (10.0.0.254) so lab VMs have outbound internet routing through your firewall.
- DNS: On the RootDC, this points to 127.0.0.1 (loopback) with an external forwarder (8.8.8.8) #As this is a DC, this external forwarder is useless, but
#the scripts provision a forwarder in DNS for outbound queries..
```

You can add your own upstream forwarder in `06_SK_Automation-Host_CustomConfigs.ps1`.

```text 
    # 5. Upstream DNS Forwarders Configuration
    Import-Module DNSServer -ErrorAction SilentlyContinue
    $UpstreamDNS = @("8.8.8.8", "1.1.1.1")
    Write-Host "  -> Configuring DNS Upstream Forwarders ($($UpstreamDNS -join ', '))..." -ForegroundColor Gray
    Set-DnsServerForwarder -IPAddress $UpstreamDNS -ErrorAction SilentlyContinue
    Write-Host "  -> DNS Upstream Forwarders successfully applied." -ForegroundColor Green
```
For replica DCs, member servers, and clients, ensure the primary DNS entry points to your RootDC IP (10.0.0.1) (in the .JSON file) so Active Directory domain lookups resolve immediately during domain join.

<br>

---

## 5. 🌲 Create Additional Forests & Domains <a id="create-additional-forests--domains"></a>

You can expand your lab beyond a single forest to simulate multi-site enterprise environments, test cross-forest trusts, configure conditional DNS forwarders, and analyze inter-site Active Directory replication topologies.

Adding an independent forest requires four coordinated configuration steps:

1. **Provision an Isolated Hyper-V Virtual Switch:** Create a dedicated private/internal vSwitch in Hyper-V for the new forest's broadcast domain.
2. **Add a Dedicated Gateway Interface in pfSense:** Attach a new synthetic network adapter (`hnX`) to the pfSense virtual appliance, bind it to your new vSwitch, and assign its static gateway IPv4 interface. For detailed walkthroughs, refer to the **[pfSense Configuration Guide](PfSense-configuration.md)**.
3. **Register the Switch in Automation Variables:** Add the new vSwitch name to the `$RequiredSwitches` validation check inside **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** so the pre-run checks pass.
4. **Declare the New Forest Nodes:** Add the new domain controller and member server hashtables to the `$VMList` array, binding each node to the new `Switch` and distinct `Forest` namespace, then mirror those network definitions inside **[`SK_Automation-VMConfig.json`](../SK_Automation-VMConfig.json)**.

---

### Step 1: Provision a New Hyper-V Switch & pfSense Interface

1. In Hyper-V Virtual Switch Manager, create a new **Private** switch named `lab-switch-lan2`.
2. Add a new network adapter (`hn2`) to your pfSense VM bound to `lab-switch-lan2`.
3. In the pfSense console (or web GUI), assign this interface as `OPT1`, configure a static IPv4 address (e.g., `172.32.0.254/24`), and enable firewall pass rules between your lab subnets.

Your pfSense interface configuration will look like this:

```text
WAN  (wan) hn0 -> v4: 192.168.0.#/24   (Host DHCP assigned interface - Internet access)
LAN  (lan) hn1 -> v4: 10.0.0.254/24    (Gateway for Forest 1: internal.sk-it.com  - Private vSwitch: lab-switch-lan)
OPT1 (lan) hn2 -> v4: 172.32.0.254/24   (Gateway for Forest 2: Brazil.sk-it.com    - Private vSwitch: lab-switch-lan2)
```
### Step 2: Define New Nodes
Define New Nodes in $VMList `(01_SK_Automation-Host_CreateVM.ps1)`.

Add your second forest root domain controller to the `$VMList array`. Notice that Switch points to lab-switch-lan2 and Forest points to the new domain namespace:

```PowerShell
$VMList = @(
    # Forest 1: Primary Lab Infrastructure
    @{Name="SRV-DC1";  OS="Win2025"; Switch="lab-switch-lan";  MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="internal.sk-it.com"},

    # Forest 2: Secondary Forest Infrastructure (Bound to new isolated switch and subnet)
    @{Name="SRV-DC1b"; OS="Win2025"; Switch="lab-switch-lan2"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="Brazil.sk-it.com"}
)
```
### Step 3: Update SK_Automation-VMConfig.json
Mirror the new node definition inside `SK_Automation-VMConfig.json`, ensuring the subnet, gateway, and primary DNS match the new network segment:

```JSON
Then update the .JSON file with the new DC/Forest information.
  "Environment": "VM Guest Configuration",
  "GlobalAdmin": "Administrator",
  "VMs": [
    { #Forest 2
      "HyperVName": "SRV-DC1b", ># New Hyper-v name
      "OSHostName": "SRV-DCb", ># New OS name
      "Role": "ReplicaDC",
      "Forest": "Brazil.sk-it.com",   ># New forest name
      "DomainName": "Brazil.sk-it.com", ># New Domain name
      "Site": "Brazil-DataCenter", ># New site name
      "Subnet": "172.32.0.0/24",  #New IP Range
      "IP": "172.32.0.1",
      "Prefix": 24,
      "Gateway": "172.32.0.254",
      "DNS": ["127.0.0.1"],
      "NetBIOSName": "BRAZIL" 
    }
    
```
>[!NOTE]
>DNS for Multiple Forests: The new forest root DC (SRV-DC1b) initialises its primary DNS pointing to 127.0.0.1 so it can host its own active directory integrated zone. To enable cross-forest name resolution for trusts, configure Conditional Forwarders inside DNS Manager on each DC pointing to the opposite domain controller's IP address.

---

### Step 4: Add the new vSwitch to the Host Pre-Flight Check

To prevent provisioning failures halfway through the deployment, **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** validates that all required virtual switches exist in Hyper-V before creating any virtual machines.

Add your new Vswitch name (`lab-switch-lan2`) to the `$RequiredSwitches` array near the top of `01_SK_Automation-Host_CreateVM.ps1`:

```powershell
# Validate required Hyper-V Virtual Switches before provisioning
$RequiredSwitches = @("lab-switch-lan", "lab-switch-lan2") # Add your secondary forest isolated switch here

foreach ($sw in $RequiredSwitches) {
    $existingSwitch = Get-VMSwitch -Name $sw -ErrorAction SilentlyContinue
    if (-not $existingSwitch) {
        Write-Error "CRITICAL: Virtual Switch [$sw] was not found in Hyper-V."
        Write-Host "Ensure your pfSense LAN switch exists and matches the exact name before deploying VMs." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Verified Virtual Switch: [$($existingSwitch.Name)] (Type: $($existingSwitch.SwitchType))" -ForegroundColor Green
}
```
### 🌲 Multi-Forest Expansion: Configuration Summary

You can deploy an entirely separate Active Directory forest without modifying the core PowerShell orchestration scripts. The environment relies on a declarative model driven solely by updating `$VMList` and `SK_Automation-VMConfig.json`.

---

#### 1. Update the Host Inventory (`01_SK_Automation-Host_CreateVM.ps1`)
Add an entry for the new Forest Root Domain Controller inside the `$VMList` array
* Set `Role = "RootDC"` to trigger forest installation routines.
* Define a unique `VMName` (e.g., `BR-DC01`).
* Specify the target `Forest` namespace (e.g., `brazil.sk-it.com`).
* Bind the adapter to the dedicated private switch (e.g., `Switch = "lab-switch-lan2"`).

---

#### 2. Mirror Network Settings (`SK_Automation-VMConfig.json`)
Add a matching node definition inside the JSON configuration file:
* Assign a unique static `IPAddress` within the secondary subnet (e.g., `172.32.0.1`).
* Configure the subnet mask and pfSense interface gateway (e.g., `172.32.0.254`).
* Set `DNS` to loopback (`127.0.0.1`) for the RootDC role.

---

#### 3. Attach Additional Nodes
To place additional servers or workstations into the secondary forest:
* Duplicate a standard node block in both `$VMList` and the JSON configuration.
* Set `Role` to `MemberServer` or `Client`.
* Match the `Forest` value to `brazil.sk-it.com`.
* Point the node's `DNS` setting to the IP address of the new RootDC (`172.32.0.1`).

---

#### 4. Execution Workflow
When executing the pipeline via `SK_Automation-host_The-One-Ring.ps1`:
* **`01`** provisions VM hardware shells and attaches them to their designated virtual switches.
* **`02` & `03`** test and inject static IP configurations across both subnets.
* **`04`** iterates over all nodes with `Role = "RootDC"`, running `Install-ADDSForest` sequentially for each declared forest root.
* **`05`** joins replica domain controllers, member servers, and clients to their respective domains dynamically.


---
<br>

## 6. 💾 Storage Planning & Dedicated Drive Placement <a id="storage-planning--dedicated-drive-placement"></a>
Deploying the full multi-node lab, default environment (laid out as hashtables in the $VMList array) requires roughly **350+ GB ** of available solid-state storage. By default, the entire pipeline is self-contained directly within your repository directory. 

If your primary OS drive has limited capacity, or if you prefer running your virtual disks on a dedicated, high-speed NVMe or SSD partition (such as `D:\` or `E:\`), you can adjust the master disk expansion ceilings or redirect active VM storage entirely.  

---
### 💾 6a. Customise Master Disk Ceilings in Packer (`build.pkr.hcl`)

The maximum virtual disk size allocated during unattended OS installation is defined inside each builder source block in **[`build.pkr.hcl`](../build.pkr.hcl)**:

```hcl
# Windows Server 2025 builder block:
source "hyperv-iso" "vm-server2025" {
  disk_size       = 61440   # 60 GB default dynamic VHDX ceiling
  disk_block_size = "1"
  # ...
}

# Windows 11 Enterprise builder block:
source "hyperv-iso" "vm-win11" {
  disk_size       = 61440   # 60 GB default dynamic VHDX ceiling
  disk_block_size = "1"
  # ...
}
```
To adjust capacity, change the disk_size integer (specified in megabytes). Because these are dynamically expanding VHDX files, they only consume what the operating system uses initially (around 15–20 GB), but this setting sets the maximum volume size exposed to the guest OS partition table.


### 💾 6b. Redirect Active Lab VM Storage to a Dedicated Drive (01_SK_Automation-Host_CreateVM.ps1)
By default, the active lab VMs, their cloned VHDX disks, and their Hyper-V runtime state files reside inside the repository folder under Hyper-V_VMs/. 
To direct all cloned virtual machines and their execution metadata to a separate fast drive or partition (e.g., D:\LabStorage): 

Open SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1. Locate the $vmStorageDir variable near the top of the script and change it to your dedicated storage target:
```powershell
$vmStorageDir = "D:\LabStorage"
```
The script automatically creates the destination directory structure (e.g., D:\LabStorage\SRV-DC1\SRV-DC1.vhdx), clones the golden images, and registers the virtual machines directly to that volume.

[!NOTE]Storage Permissions Notice: If you redirect $vmStorageDir to an external partition or separate physical volume, verify that the local Hyper-V Administrators group and the Virtual Machines special identity (NT VIRTUAL MACHINE\VIRTUAL MACHINES) retain Modify/Read/Write permissions on the root folder.

markdown

<br>
---

## 7. 🚫 Common Mistakes to Avoid <a id="common-mistakes-to-avoid"></a>

If you find any bugs, or want to leave a suggestion, please feel free to use my ticketing system.
[SK-IT Support Portal](https://sk-it-helpdesk.atlassian.net/servicedesk/customer/portals)

*This section documents critical pitfalls and troubleshooting checkpoints across the pipeline:*

* **Mismatched vSwitch Names:** Typing Hyper-V switch names with extra spaces, inconsistent casing, or trailing characters. Ensure string names match your virtual switch definitions exactly across both PowerShell and pfSense.
* **Mismatched or Unrecognised `Role` Values:** Assigning invalid or unsupported roles in `$VMList` or the configuration files. Stick strictly to supported automation roles: `RootDC`, `ReplicaDC`, `MemberServer` (or `MS`), and `Client`.
* **Out-of-Sync Active Directory Forest Names:** Changing your Active Directory forest root namespace inside `01_SK_Automation-Host_CreateVM.ps1` but neglecting to mirror the identical domain string in `SK_Automation-VMConfig.json`.
* **Subnet & Gateway Misalignment:** Configuring static guest IP addresses or default gateways in the JSON file that do not match the assigned pfSense interface subnet (e.g., assigning a host address outside `10.0.0.0/24` or using an incorrect gateway IP).
* **Updating Only One Configuration File:** Modifying node counts, memory, or roles in **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** without mirroring those updates inside **[`SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)**.
* **Leaving Enhanced Session Mode Enabled in Hyper-V:** Having Enhanced Session Mode globally enabled on the Hyper-V host triggers interactive credential and display prompts during guest console viewing. While PowerShell Direct bypasses this, it blocks unattended console monitoring.
* **Insufficient Storage Headroom:** Initiating deployments on host volumes with less than **350 GB** of free capacity. Running out of disk space halts dynamic VHDX expansion and Hyper-V VM state (`.bin`/`.vsv`) creation mid-provisioning.
* **Incorrect NTFS Permissions on Custom Storage Drives:** Redirecting `$vmStorageDir` to a secondary drive (e.g., `D:\LabStorage`) without granting **Modify** permissions to `NT VIRTUAL MACHINE\Virtual Machines` and `NT SERVICE\VMMS`. For initial deployments, keeping the default repository paths is strongly recommended.

<br>

---

### 🚀 Next Steps 
After you have completed your customisations, return to your deployment workflow STEP to finish off and trigger your build.

* **Quick Start Track:** Return to **[STEP 6: Execute Deployment Orchestrator](Project-prerequisites-deployment.md#quick-step-6)**.
* **Beginner Track:** Return to **[STEP 7: Download Windows ISOs & HashiCorp Packer](Project-prerequisites-deployment.md#beginner-step-7)**.