# Windows Server 2025 Automation Project:- pfSense Configuration

**Quick Links:** | [Read Me](../README.md) | [Technical Reference](Technical-Reference.md) | [Project Customisation](Customise-your-Infrastructure.md) | [Project Deployment Guide](Project-prerequisites-deployment.md) |

---

# 🛡️ pfSense Network Configuration Guide


> [!TIP]
> **Quick Guide Walkthrough:** If you want to get the Isolated Hyper-V Environment setup ASAP (without understanding why), just replicate the configurations in this informative Youtube video: [How to set up an isolated Hyper-V lab with internet access](https://www.youtube.com/watch?v=eEZZQT8T4xY). After you have configured and tested pFSense, please go back to your deployment track step:
>  * **Quick Start Track:** Return to **[STEP 2: Git Clone the Repository](Project-prerequisites-deployment.md#quick-step-2)**.
>  * **Beginner Track:**    Return to **[STEP 5:  Git Clone Repository & Install HashiCorp Packer](Project-prerequisites-deployment.md#beginner-step-5)**.

This guide details the network topology, virtual switch design, and pfSense configurations to create an isolated, routed internet, automated Hyper-V lab.
* **Architecture Alignment:** The network topology demonstrated in the video aligns with the default parameters defined across this project's PowerShell scripts and Packer templates. Ensure your Hyper-V virtual switch names match your script definitions character-for-character without spaces (`lab-switch-wan` and `lab-switch-lan`). Visual references are located in the **[`images/Hyper-V/`](../images/Hyper-v)** directory.
* **Installation Media:** Download the official installer from the **[Netgate pfSense Community Edition Download Portal](https://www.pfsense.org/download/)** (choose **AMD64 (64-bit)** architecture with the **DVD Image (ISO) Installer**).

> [!IMPORTANT]
> **Switch Name Precision:** Hyper-V switch names must match the `$RequiredSwitches` check in `01_SK_Automation-Host_CreateVM.ps1` exactly. Any spelling discrepancy or accidental trailing whitespace will cause the pre-flight checks to halt VM deployment.

<br>

## Why We Use pfSense to Create an Isolated Network Boundary

In Hyper-V environments, **Private Virtual Switches** isolate virtual machines strictly at Layer 2 (Data Link layer). While this successfully keeps project VMs from touching the physical host network, Layer 2 isolation alone cannot provide the Layer 3+ network services—such as inter-VLAN routing (between forest, should you decide to create ), outbound NAT, packet inspection, and VPN termination—required for enterprise automation. It also falls short of supporting hybrid cloud capabilities like Microsoft Entra ID integration, hybrid single sign-on (SSO), and secure Azure connectivity.

Deploying **pfSense** as a virtual appliance in Hyper-v establishes a controlled, stateful network perimeter that provides foundational routing today while preparing the lab for future advanced hybrid workloads:

1. **Controlled Internet Access via Outbound NAT:**  
   Lab virtual machines reside on an isolated private subnet (`10.0.0.0/24`) with no bridge to the production or home network. pfSense performs Source Network Address Translation (SNAT) across the WAN uplink (`lab-switch-wan`), allowing guest VMs to pull OS packages, Windows updates, and PowerShell modules from the internet without exposing the lab inward.

2. **Preventing Broadcast Collisions & DHCP Bleed:**  
   Enterprise Active Directory deployments introduce domain-integrated DHCP scopes and authoritative DNS root zones. Without a strict perimeter boundary, broadcast DHCP discover requests and dynamic DNS registrations can leak onto your physical home or office network, causing IP conflicts and knocking personal devices offline. pfSense forms a hard broadcast barrier, ensuring all DHCP, ARP, and NetBIOS broadcasts remain contained within the virtual lab.

3. **Enterprise & Hybrid Cloud Extensibility:**  
   Hyper-V virtual switches cannot terminate VPN tunnels or route across virtual networks natively. Using pfSense as the authoritative default gateway (`10.0.0.254`) prepares the environment for production test topologies:
   * **Hybrid Azure Connectivity:** Establishing policy-based or route-based IPsec Site-to-Site VPN tunnels directly to an Azure Virtual Network Gateway.
   * **Hybrid Identity & Governance:** Securely syncing on-premises Active Directory Domain Services (AD DS) to Microsoft Entra ID and deploying Azure Arc agents to on-premises servers.

---
<br>

## Media Download & Supported Versions
Download the official installation media directly from the **[Netgate pfSense Community Edition Download Portal](https://www.pfsense.org/download/)** (choose **AMD64 (64-bit)** and the **DVD Image (ISO) Installer**).

> [!NOTE]
> **pfSense Version Compatibility & Interface Mapping:**  
> This automation project was developed and validated on pfSense CE 2.6.0, but any modern Community Edition release (such as 2.7.x or later) functions identically. The core setup requires:
> * **Interface Assignment:**
>   * `hn0` (WAN): The first synthetic virtual network adapter (vNIC) added to the pfSense VM, bound to `lab-switch-wan` and configured for **DHCP** to receive an IP from your host/external network.
>   * `hn1` (LAN): The second synthetic virtual network adapter (vNIC) added to the pfSense VM, bound to `lab-switch-lan` and assigned static IPv4 address `10.0.0.254/24`.
Make sure you do not enable DHCP from within pfSense.  
---
## How to Configure pfSense for this Automation Project

Watch this step-by-step video tutorial to configure pfSense for this isolation: **[How to set up an isolated Hyper-V lab with internet access](https://www.youtube.com/watch?v=eEZZQT8T4xY&t=690s)**. You only need to watch up to the **11:30** mark to get pfSense fully isolated and routing.  All credit to Danny Moran for creating this guide.  

The original plan was to write out an extensive setup manual, but the video covers all aspects exceptionally well. Before running the automation pipeline, I strongly recommend spinning up a temporary test VM attached to `lab-switch-lan` to verify:

* **pfSense WAN Interface (`hn0`):** Successfully receives an IPv4 lease via DHCP from your physical host network.
* **pfSense LAN Interface (`hn1`):** Is assigned the static gateway address `10.0.0.254/24` with the built-in DHCP service disabled (Active Directory will handle leases later).

* **Outbound Routing:** Your test VM is configured with an IP in the `10.0.0.0/24` subnet and can resolve and browse external websites.

**CRITICAL — Virtual Switch Naming:** Hyper-V switch names must match the configuration files **exactly** with no trailing characters or spaces (`lab-switch-wan` and `lab-switch-lan`). Mismatched names will cause the pre-run checks in `01_SK_Automation-Host_CreateVM.ps1` to halt immediately. Reference screenshots of the working Hyper-V Virtual Switch Manager setup can be found in **[`images/`](../images/)** (these only mirror the guide!)

---

### How Switch Names Bind to the Automation Pipeline

The isolated switch name (Switch="lab-switch-lan") declared in Hyper-V Switch Manager (and then added to the pfSense VM, which displays as hn1 in pfSense) binds directly to the `$VMList` array. **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)**

```powershell
$VMList = @(
    # Infrastructure Tier: Active Directory Domain Controllers (Forest Root & High Availability Replicas)
    @{Name="SRV-DC1";     OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="RootDC";    Forest="internal.sk-it.com"},
    @{Name="SRV-DC2";     OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=6GB; VCPU=4; Role="ReplicaDC"; Forest="internal.sk-it.com"},

    # Member Servers: MS Exchange, Azure Arc/Backup, Web Server Failover Clustering, etc.
    @{Name="SRV-EX01";    OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS";        Forest="internal.sk-it.com"},
    @{Name="SRV-MS01";    OS="Win2025"; Switch="lab-switch-lan"; MemStart=4GB; MemMin=1GB; MemMax=6GB; VCPU=4; Role="MS";        Forest="internal.sk-it.com"},
   
    # Client Workstations: Windows 11 Enterprise for Windows Admin Center, FSLogix testing, and SSO validation
    @{Name="CLI-WIN11-01"; OS="Win11";   Switch="lab-switch-lan"; MemStart=4GB; MemMin=2GB; MemMax=4GB; VCPU=2; Role="Client";    Forest="internal.sk-it.com"}
)
```

### 🖧 pfSense Interface Mapping

Below is the interface alignment pfSense vNics (`hnX`) to their respective Hyper-V switches, IP subnets, and Active Directory forest gateways:

```text
WAN  (wan)  hn0 -> v4/DHCP: 192.168.0.x/24  (Uplink to Host / External NAT - Internet Access)
LAN  (lan)  hn1 -> v4:10.0.0.254/24   (Gateway for Forest 1: internal.sk-it.com - vSwitch: lab-switch-lan)
OPT1 (opt1) hn2 -> v4: 172.32.0.254/24 (Gateway for Forest 2: brazil.sk-it.com   - vSwitch: lab-switch-lan2)
```
In this reference architecture (my setup), the optional interface (OPT1) binds to Hyper-V synthetic adapter hn2 and serves as the default gateway (172.32.0.254/24) for the secondary forest (brazil.sk-it.com) across the isolated lab-switch-lan2 private switch.

### 💡 In Short: How pfSense Sees Your Network
The pfSense VM simply needs two virtual network adapters (vNICs) connected in Hyper-V:

* **First vNIC (`hn0` / WAN):** Plugs into `lab-switch-wan` to receive external internet access.
* **Second vNIC (`hn1` / LAN):** Plugs into `lab-switch-lan` to act as the internal gateway (`10.0.0.254/24`) for your private lab servers.

Hyper-V passes these adapters to pfSense in the exact order you add them, which FreeBSD labels sequentially as `hn0` and then `hn1`.

It is crucial that you add these vNICs to the pfSense VM in the exact operational order:
1. **Network Adapter 1 (`hn0`):** Bound to `lab-switch-wan`. pfSense assigns the first detected interface (`hn0`) as the WAN interface, which requests an IPv4 lease via DHCP from your physical host network.

2. **Network Adapter 2 (`hn1`):** Bound to `lab-switch-lan`. pfSense assigns the second interface (`hn1`) as the LAN interface, which acts as the static default gateway (`10.0.0.254/24`) for your internal virtual machines.

Reversing this addition order causes pfSense to bind the WAN configuration to your isolated internal switch and the LAN configuration to your host network, breaking outbound routing and potentially leaking DHCP leases onto your home LAN.

Once mapped, pfSense handles stateful routing, outbound NAT, and firewall filtering between your external network and your isolated virtual lab.

**Important:** If you create an additional pfSense interface (for another forest or domain), you must create an outbound firewall pass rule on that interface to allow traffic out through `hn0` (your WAN interface), or your new machines will have no outbound internet access. 

This rule must be created in the pfSense WebGUI, so you will need at least one working VM connected to the internal network to log in and configure it.  You could create one forest in your first "loop" of the automation project, use a VM to connect to the pfSense Web-UI (on the default gateway IP 10.0.0.254), then create the additional interface / IP-Subnet / FW rules. Then run the next loop of the automation project to create the secondary forest. 

---
<br>

### 🚀 Next Steps 
After you have completed your customisations, return to your deployment workflow to finish off and trigger your build.


* **Quick Start Track:** Return to **[STEP 2: Git Clone the Repository](Project-prerequisites-deployment.md#quick-step-2)**.
* **Beginner Track:** Return to **[STEP 5:  Git Clone Repository & Install HashiCorp Packer](Project-prerequisites-deployment.md#beginner-step-5)**.