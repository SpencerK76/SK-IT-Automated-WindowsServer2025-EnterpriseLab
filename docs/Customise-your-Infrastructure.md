# Windows Server 2025 Automation Project:- Customising Your Infrastructure

## Customising Your Hyper-V Infrastructure

My automated lab defaults to five provisioned Hyper-V VM nodes: this **[script](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** creates two Domain Controllers, two Member Servers, and one Windows 11 Enterprise Client. This takes up roughly 350+ GB of hard drive space, inside one self-contained repository folder. 

If you're happy with this default layout and have enough storage available, the only values you need to customise are the hardware resources (such as VM memory allocation), along with your computer, forest, domain and networking configurations. Just make sure your Hyper-V vSwitches are set up and named correctly in your configuration files before starting.


### Table of Contents
1. [🖥️ Customise the Packer VHDX Master Image Size](#customise-the-packer-vhdx-master-image-size)
2. [📦 Customise the Number of VM Nodes Created](#customise-the-number-of-vm-nodes-created)
3. [🪟 Customise VM & Domain Networking Settings](#customise-vm--domain-networking-settings)
4. [🌲 Create Additional Forests & Domains](#create-additional-forests--domains)
5. [💾 Storage Planning & Dedicated Drive Placement](#storage-planning--dedicated-drive-placement)
6. [🚫 Common Mistakes to Avoid](#Common-Mistakes--to-Avoid)

---

**Quick Links:** [Read Me](../README.md) | [pfSense Configuration](PfSense-configuration.md) | [Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md) | | [Technical Reference](Technical-Reference.md) |

---

### Before You Begin Customising Your Lab, check:
* You have verified all base host dependencies in the **[Project Prerequisites Guide](Project-prerequisites-deployment.md)** (Hyper-V enabled, PowerShell 7 installed, execution policy set etc.).
* You have confirmed that pfSense is routing outbound internet traffic using a quick test VM connected to `lab-switch-lan` (walkthrough in the **[pfSense Configuration Guide](PfSense-configuration.md)**).
* You have created all required virtual switches in Hyper-V Virtual Switch Manager (`lab-switch-wan` and `lab-switch-lan`) with exact naming `/images/hyper-v`.
* You have mapped out your lab topology: total server count, hardware sizing (RAM/vCPU), Active Directory roles, site names, and forest/domain namespaces.
* You have confirmed at least **350 GB of free solid-state storage** on the target drive hosting your repository and virtual disks.

---


<br><br>
---


## 1. 🖥️ Customise the Packer VHDX Master Image Size <a id="customise-the-packer-vhdx-master-image-size"></a>

The Sysprep PackerVHDs are currently set to 60GB in the `build.pkr.hcl`.  **[build.pkr.hcl](../build.pkr.hcl)**.  This is the baseline
size for all VHDx images. You can change the default Sysprep VHD image size here, however please be aware each OS minimum HD space recommendations. 60GB is a reasonable HD size for a Lab environment OS VHDx.  I did not add any software installations to my GoldenPackerVHD via the provisioning block, although this is certainly possible.

```text
  # --- Virtual Hard Disk (Storage) ---
  disk_size             = 61440  # 60 GB vDisk size - change this for default VM vDisk size based on Windows OS recommendations and my personal Lab needs.
  disk_block_size       = 1      # 1 MB block size
```


---
<br><br>

## 2. 📦 Customise the Number of VM Nodes Created <a id="customise-the-number-of-vm-nodes-created"></a>

If you want to scale the VM node count up or down (adding or removing servers) or adjust memory to match your workstation's capacity, you must update TWO synchronised files. This is where you add or remove hash table entries from the `$VMList` array and plan your forest and domain topology.

**File 1:** Open **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** and edit the `$VMList` array to define your Hyper-V VM names, memory limits (`MemStart`, `MemMin`, `MemMax`), virtual CPU count (`VCPU`), and assigned Hyper-V vSwitch (`lab-switch-lan`). For details on switch assignments, see the **[pfSense Configuration Guide](PfSense-configuration.md)**. Base these settings on the lab blueprint you mapped out during the Map Hardware & Storage Capacity section in the project prerequisites and deployment.

You can also set your Active Directory Forest root domain name here (see below for details on creating multiple sites, forests and domains).

> **Role Attribute Note:** The `Role` attribute inside each VM hash table entry is critical to the automation pipeline. It determines what configuration tasks each node will execute during deployment. These values must remain consistent across both configuration files (`Host_CreateVM.ps1` & `VMConfig.json`)  because they define the server roles being provisioned. For example, `RootDC` identifies the Forest Root Domain Controller, `ReplicaDC` identifies secondary domain controllers, and `MS` identifies member servers. The automation scripts query these `Role` values dynamically rather than relying on a hardcoded list of server names. This allows you to add or remove VM entries(server nodes) freely without breaking or halting the pipeline, as the workflow adapts automatically based on the roles present. This allows you to easily add a server/client to the domain after you have created your infrastructure.


> **IMPORTANT — Virtual Switch Name:** The `Switch` property must match your pfSense internal switch (`lab-switch-lan`) created during the **[pfSense Configuration Guide](PfSense-configuration.md)**.
>
> **IMPORTANT — Active Directory Forest Root:** If you change the Forest Root name here, remember to update the corresponding Forest and Domain values inside **[`SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)** for each node.

Open **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** and edit the `$VMList` array:

```powershell
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers (e.g., RootDC and secondary ReplicaDC)
    @{Name="SRV-DC1";   OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="internal.sk-it.com"},
    @{Name="SRV-DC2";   OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="ReplicaDC"; Forest="internal.sk-it.com"},

    # Member Servers: MS Exchange, Azure Backup, Web Server Failover Clustering, etc.
    @{Name="SRV-EX01";  OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS"; Forest="internal.sk-it.com"},
    @{Name="SRV-MS01";  OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS"; Forest="internal.sk-it.com"},
   
    # Client Workstations: Windows 11 Enterprise
    @{Name="CLI-WIN11-01"; OS="Win11"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=4GB; VCPU=2; Role="Client"; Forest="internal.sk-it.com"}
)
```
After you have changed the array list (added another win11 client for example) - those changes MUST be reflected in the SK_Automation-VMConfig.json file. 

Quick Tip: If you have limited storage space on your host machine, you can simply comment out (#) the nodes you do not want created. For your initial pass of the automation, you will always need a RootDC to establish the forest root; future runs can provision any combination of the supported Roles.

```powershell
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers: eg RootDC and secondary ReplicaDC
    @{Name="SRV-DC1";  OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="internal.sk-it.com"},
    #@{Name="SRV-DC2";  OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="ReplicaDC"; Forest="internal.sk-it.com"},

    # Member Servers: MS Exchange, Azure Backup, Web-server Fail-over clustering etc.. 
    #@{Name="SRV-EX01"; OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS"; Forest="internal.sk-it.com"},
   # @{Name="SRV-MS01"; OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS"; Forest="internal.sk-it.com"},
   
    # Client Workstations: Windows 11 Enterprise
    @{Name="CLI-WIN11-01"; OS="Win11";   Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=4GB; VCPU=2; Role="Client"; Forest="internal.sk-it.com"}
)
```
With this minimal setup, the pipeline only provisions SRV-DC1 and CLI-WIN11-01. To go one step further, you can reduce disk_size in build.pkr.hcl to the OS minimum (around 30 GB to 40 GB), bringing your total active repository footprint down to roughly 75 GB (including the ISOs, which can be moved to another drive once the lab is running).

   

## Adding Servers and Clients Post-Deployment

Beyond trimming nodes down, you can expand your lab later by adding new `$VMList` entries and updating the corresponding `.json` configuration. Just ensure you assign the correct `Role` for each additional node, and avoid creating a second `RootDC` unless you are deploying a completely separate Active Directory forest. These new nodes will be provisioned, joined to your domain and configured with the network settings defined in `SK_Automation-VMConfig.json`. 

To prevent rebuilding existing golden images, set `$SkipPackerBuild` to `$true` in `The-One-Ring.ps1`:

```powershell
param(
    [switch]$SkipPackerBuild = $true
)

```
This bypasses the Packer build phase entirely and jumps straight to the Hyper-V cloning and PowerShell Direct automation steps using your existing master VHDXs. You will need to place your own .VHDX images into the Packer VHDX output folders obviously.  

```Text 
# variables.pkr.hcl
variable "output_directory" {
  type        = string
  description = "Target destination folder where the finalised Windows Server 2025 master VHDX is exported."
  default     = "./output-ws2025-master-vhd" # output folder is automatically created in the root.
}
```
Once you have added the new nodes to the $VMList array and updated SK_Automation-VMConfig.json, run the master deployment script:
```
.\Deploy_Automation_Project.ps1
```
>Note on Console Warnings: If you are adding nodes to an existing Forest, after you have run the initial automation project, the VS Code terminal output may display some non-terminating errors or warnings as the scripts loop through existing configuration entries (such as Active Directory detecting pre-existing domain controllers or network adapters already bound). This is expected behavior; the automation pipeline will ignore already pre-completed creations and continue provisioning your newly added nodes.
<br>

---

## 3. 🪟 Customise VM & Domain Networking Settings <a id="customise-vm--domain-networking-settings"></a>

**FILE 2:** The second file you must update, is **[`SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)**. This file configures and serves as the core parameter manifest across the Stage 3 automation pipeline. It instructs the in-guest scripts how to install Active Directory Domain Services (AD DS), promote the Forest Root DC, join replica domain controllers, bind member servers, and attach Windows 11 clients to the domain. It also establishes the static networking and IP address configurations for every node.

The VM names and roles defined here **must match** the corresponding entries in your `$VMList` hashtable array inside `01_SK_Automation-Host_CreateVM.ps1`.

---

### Cross-File Parameter Mapping

Compare how a single server node (`SRV-DC1`) is declared across both files:

```powershell
# File 1: SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1 ($VMList Entry)
@{Name="SRV-DC1"; OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC"; Forest="internal.sk-it.com"},

#File 2 .JSON attribute
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
      "Gateway": "10.0.0.254",
      "DNS": ["127.0.0.1", "8.8.8.8"],
      "NetBIOSName": "INTERNAL"
    }

#  Attributes Explained
#When customising your lab's IP addressing, keep these rules in mind:

- HyperVName & OSHostName: Must match the Name property in $VMList. The scripts use this identity to locate the VM over Hyper-V VMBus and rename the internal Windows computer name.
- Role: Must match the $VMList role (RootDC, ReplicaDC, MS, or Client). This controls which Stage 3 bootstrap script executes inside the guest.
- Subnet & Prefix: Must align with the isolated subnet managed by your pfSense LAN interface (10.0.0.0/24).
- Gateway: Must point directly to the pfSense LAN interface IP address (10.0.0.254) so lab VMs have outbound internet routing through your firewall.
- DNS: On the RootDC, this points to 127.0.0.1 (loopback) with an external forwarder (8.8.8.8).

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
```
For replica DCs, member servers, and clients, ensure the primary DNS entry points to your RootDC IP (10.0.0.1) so Active Directory domain lookups resolve immediately during domain join.

```

<br>

---

## 4. 🌲 Create Additional Forests & Domains <a id="create-additional-forests--domains"></a>

You can of course expand your lab beyond a single forest to simulate multi-site enterprise environments, test cross-forest trusts, configure conditional DNS forwarders and analyse inter-site Active Directory replication topologies.

Adding an independent forest requires four coordinated steps: 1) provisioning a dedicated isolated virtual switch in Hyper-V, 2) adding a new gateway interface in pfSense, 3) declaring the new forest nodes in your automation files, and 4) add the new vSwitch to the `$VMList` array and the `$RequiredSwitches` variable.

---

### Step 1: Provision a New Hyper-V Switch & pfSense Interface

1. In Hyper-V Virtual Switch Manager, create a new **Private** switch named `lab-switch-lan2`.
2. Add a new network adapter (`hn2`) to your pfSense virtual machine bound to `lab-switch-lan2`.
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
    { #Forest 1
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
      "DNS": ["127.0.0.1"],
      "NetBIOSName": "INTERNAL"
    },
    { #Forest 2
      "HyperVName": "SRV-DC1b",
      "OSHostName": "SRV-DCb",
      "Role": "ReplicaDC",
      "Forest": "Brazil.sk-it.com",
      "DomainName": "Brazil.sk-it.com",
      "Site": "Kent-DataCenter",
      "Subnet": "172.32.0.0/24",
      "IP": "172.32.0.1",
      "Prefix": 24,
      "Gateway": "172.32.0.254",
      "DNS": ["127.0.0.1"],
      "NetBIOSName": "BRAZIL"
    }
    
```
>Note: DNS Note for Multiple Forests: The new forest root DC (SRV-DC1b) initialises its primary DNS pointing to 127.0.0.1 so it can host its own active directory integrated zone. To enable cross-forest name resolution for trusts, configure Conditional Forwarders inside DNS Manager on each DC pointing to the opposite domain controller's IP address.

---

### Step 4: Add the new vSwitch to the Host Pre-Flight Check

To prevent provisioning failures halfway through the deployment, **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** validates that all required virtual switches exist in Hyper-V before creating any virtual machines.

Add your new switch name (`lab-switch-lan2`) to the `$RequiredSwitches` array near the top of `01_SK_Automation-Host_CreateVM.ps1`:

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

 ### Summary of adding an additional Forest
- Create the new Private virtual switch in Hyper-V Virtual Switch Manager and attach a new virtual network adapter to your pfSense VM bound to that switch. In pfSense, assign this interface (e.g., `OPT1`), set its static IP and subnet (e.g., `172.32.0.254/24`), and configure firewall pass rules on that interface so outbound internet and cross-forest Active Directory traffic can flow.
- $VMList Array: Define your new Domain Controller in 01_SK_Automation-Host_CreateVM.ps1 with its dedicated switch (lab-switch-lan2), Forest name, and RootDC role.
- JSON Blueprint: Update SK_Automation-VMConfig.json with the matching node name, static IP addressing, and gateway pointing to the new pfSense interface.
- Switch Validation: Add the new vSwitch name to the $RequiredSwitches array in 01_SK_Automation-Host_CreateVM.ps1 so the automation verifies it before building your VMs.

<br>

---

## 5. 💾 Storage Planning & Dedicated Drive Placement <a id="storage-planning--dedicated-drive-placement"></a>

Deploying the full 5-node environment requires roughly **300 GB to 350 GB** of available solid-state storage. By default, the entire pipeline is self-contained directly within your repository directory. 

If your primary drive has limited capacity, or if you prefer running your virtual disks on a dedicated, high-speed NVMe or SSD partition (such as `D:\` or `E:\`), you can customise the master image sizing, redirect the Packer build outputs, or move the active lab VM storage entirely.

---

### Step 1: Customise Master Disk Sizes in Packer (Stage 1)

The maximum capacity for the virtual hard disks created during the unattended OS installation is configured directly in **[`build.pkr.hcl`](../build.pkr.hcl)** inside each builder source block:

```hcl
# Inside build.pkr.hcl (Windows Server 2025):
source "hyperv-iso" "vm-server2025" {
  disk_size       = 61440   # 60 GB default dynamic VHDX
  disk_block_size = "1"
  # ...
}

# Inside build.pkr.hcl (Windows 11 Enterprise):
source "hyperv-iso" "vm-win11" {
  disk_size       = 81920   # 80 GB default dynamic VHDX
  disk_block_size = "1"
  # ...
}
```
To adjust capacity: Change the disk_size integer (defined in megabytes). Because these are dynamically expanding VHDXs, they only consume what the operating system uses initially (around 15–20 GB), but this setting defines their maximum expansion ceiling.

During Stage 2.1, `SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1` tells Hyper-V where to locate those base .vhdx files so it can clone them:


```Powershell
$GoldenImages = @{
    "Win2025" = Join-Path -Path $ProjectRoot -ChildPath "output-ws2025-master-vhd\Virtual Hard Disks\Win2025-GoldenImage-Build.vhdx"
    "Win11"   = Join-Path -Path $ProjectRoot -ChildPath "output-win11-master-vhd\Virtual Hard Disks\Win11-GoldenImage-Build.vhdx"
}
```
>Important: If you change the Packer output directory paths in variables.pkr.hcl, you must update the corresponding paths in the $GoldenImages hashtable (above!) inside 01_SK_Automation-Host_CreateVM.ps1 so the cloner knows where to find them.


### Step 3: Redirect Active Lab VM Storage to Another Drive (Stage 2)
By default, the active lab VMs, their cloned VHDX disks, and their Hyper-V runtime state files are stored in the root folder under `Hyper-V_VMs/`:

```Powershell
# Default path assembly logic in 01_SK_Automation-Host_CreateVM.ps1:
# 1. Base storage location:
$repoRoot     = (Get-Item $PSScriptRoot).Parent.FullName
$vmStorageDir = Join-Path -Path $repoRoot -ChildPath "Hyper-V_VMs"

# 2. Per-VM folder and disk path construction:
$targetVmDir   = Join-Path -Path $vmStorageDir -ChildPath $vm.VMName
$targetVhdPath = Join-Path -Path $targetVmDir -ChildPath "$($vm.VMName).vhdx"

# 3. Disk copy:
Copy-Item -Path $sourceVhdPath -Destination $targetVhdPath -Force

# 4. Hyper-V VM registration:
New-VM -Name $vm.VMName -Path $targetVmDir -VHDPath $targetVhdPath -Generation 2
```

To redirect all active virtual machines to another dedicated drive or volume (such as D:\LabStorage):

1. Open SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1.

2. Change the $vmStorageDir variable to your desired directory:

```Powershell
$vmStorageDir = "D:\LabStorage"
```
3. That script automatically handles creating the target VM folders (e.g., D:\LabStorage\SRV-DC1\SRV-DC1.vhdx) and registers the machines directly to that drive. 

Note: Storage Permissions Notice: If you redirect $vmStorageDir outside the repository tree or to a separate physical drive, verify that Hyper-V service accounts have read and write permissions to that target folder.


<br>

---

### 6. 🚫 Common Mistakes to Avoid <a id="Common-Mistakes--to-Avoid"></a>
This section will be updated as the project is streamlined and updated.

* **Mismatched vSwitch Names:** Typing switch names with spaces, inconsistent casing or trailing characters.
* **Mismatched `Role` Values:** Assigning unrecognised roles in `$VMList` or the JSON file (stick strictly to `RootDC`, `ReplicaDC`, `MS`, or `Client`).
* **Mismatched Forest or Domain Names:** Updating the Active Directory forest root in `01_SK_Automation-Host_CreateVM.ps1` but forgetting to mirror it inside `SK_Automation-VMConfig.json`.
* **Misaligned Subnets & Gateways:** Setting static VM IP addresses or default gateways in the JSON file that do not align with the pfSense LAN interface subnet (`10.0.0.0/24` with gateway `10.0.0.254`).
* **Updating Only One Configuration File:** Modifying node definitions in **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)** without mirroring those changes in **[`SK_Automation-VMConfig.json`](../SK-Automation-Scripts/SK_Automation-VMConfig.json)** (both files must remain synchronised).
* **Leaving Enhanced Session Mode Enabled:** Leaving Hyper-V Enhanced Session Mode turned on, which halts unattended OOBE provisioning with interactive RDP prompts - this does not halt the automation though!
* **Insufficient Storage Headroom:** Running the default build on a volume with less than 350 GB of free space, causing dynamic VHDX expansion or Hyper-V memory swap allocations to fail mid-deployment.
* **Incorrect NTFS Permissions on Custom Storage:** Redirecting `$vmStorageDir` to another drive (e.g. `D:\LabStorage`) without granting permissions to `NT VIRTUAL MACHINE\Virtual Machines` and `NT SERVICE\VMMS`.  Recommended, for beginners, to keep the default paths.

<br>

---
### After you have set your configurations, please return to STEP 6 - if you was following the quick guide, or STEP 7 if you was following the beginner guide in the [Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md).