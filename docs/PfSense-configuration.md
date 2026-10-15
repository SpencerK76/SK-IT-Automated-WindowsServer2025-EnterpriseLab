# Windows Server 2025 Automation Project:- pfSense Configuration
## PfSense configuration for my SK‑IT Hyper‑V Automation Project!

* **Quick Step:** If you want to configure pfSense immediately without reading through the technical background and architectural decisions, watch this step-by-step video walkthrough: **[How to set up an isolated Hyper-V lab with internet access](https://www.youtube.com/watch?v=eEZZQT8T4xY&t=690s)**.  

* The pfSense configuration demonstrated in the video mirrors the exact network settings used throughout this automation project. Just ensure your Hyper-V virtual switch names match your scripts without any spaces (`lab-switch-wan` and `lab-switch-lan`). Visual references are available in the **[`images/`](../images/Hyper-v)** folder.  

* Download the official installation media directly from the [Netgate pfSense Community Edition Download Portal](https://www.pfsense.org/download/) (select **AMD64 (64-bit)** and the **DVD Image (ISO) Installer**).

---
**Quick Links:** | [Read Me](../README.md) | [Technical Reference](docs/Technical-Reference.md) | [Project Customisation](Customise-your-Infrastructure.md) | [Project Prerequisites & Deployment Guide](Project-prerequisites-deployment.md) |

---
<br>


## Why We Use pfSense to Create an Isolated Network Boundary

In my Hyper-V environments, **Private Virtual Switches** isolate virtual machines at Layer 2 (the data link layer). This successfully keeps project VMs from physically touching my host network. However, because they are purely isolated at Layer 2, the Hyper-V switches cannot provide the foundational Layer 3+ services (such as routing, NAT, firewall filtering and VPN termination) required for this automation project to succeed. They also fall short of supporting my forward-looking lab roadmap, which includes Microsoft Entra ID integration, single sign-on (SSO), isolated VLANs and hybrid Azure VPN tunnels.

Deploying **pfSense** as a virtual perimeter firewall delivers these essential services for the Hyper-V Automation Project while laying the groundwork for advanced hybrid cloud scenarios:

1. **Controlled Internet Access via Outbound NAT:**  
   The lab nodes live on an isolated private subnet (`10.0.0.0/24`) with no direct route to the home or office network. pfSense performs Source Network Address Translation (SNAT) over the `lab-switch-wan` interface. This allows my virtual machines to download package updates and access the internet without exposing my physical network.

2. **Preventing Network Collisions & DHCP Bleed:**  
   Deploying my enterprise Active Directory forest introduces domain-integrated DHCP servers and authoritative DNS zones. Without a stateful perimeter boundary, rogue DHCP leases and dynamic DNS registrations could leak onto your physical home network, knocking personal devices offline (and more importantly, keeping my partner's connection stable and drama-free!). pfSense guarantees that all internal broadcast traffic stays strictly confined to the virtual lab.

3. **Enterprise & Hybrid Cloud Extensibility:**  
   Hyper-V switches alone cannot establish secure site-to-site tunnels. By using pfSense as the default gateway (`10.0.0.254`), the lab is ready for test enterprise scenarios, such as routing between multi-subnet VLANs, standing up IPsec Site-to-Site tunnels to an Azure Virtual Network Gateway and connecting to Azure Arc-enabled infrastructure.

---

### Media Download & Supported Versions

Download the official installation media directly from the **[Netgate pfSense Community Edition Download Portal](https://www.pfsense.org/download/)** (choose **AMD64 (64-bit)** and the **DVD Image (ISO) Installer**).

 **Note on pfSense Versions:**  
 This lab was developed and validated on pfSense CE 2.6.0, but any modern release (such as 2.7.x or later) works identically. The setup requires only basic interface assignment (`hn0` for WAN, `hn1` for LAN), setting the LAN interface IPv4 address to `10.0.0.254/24`, and disabling the built-in pfSense DHCP service.

---
# How to Configure pfSense for this Automation Project

Watch this step-by-step video tutorial to configure pfSense for this isolation: **[How to set up an isolated Hyper-V lab with internet access](https://www.youtube.com/watch?v=eEZZQT8T4xY&t=690s)**. You only need to watch up to the **11:30** mark to get pfSense fully isolated and routing.  All credit to Danny Moran for creating this guide.

I originally planned to write out an extensive setup manual, but the video covers all aspects exceptionally well. Before running the automation pipeline, I strongly recommend spinning up a temporary test VM attached to `lab-switch-lan` to verify:

* **pfSense WAN Interface (`hn0`):** Successfully receives an IPv4 lease via DHCP from your physical host network.
* **pfSense LAN Interface (`hn1`):** Is assigned the static gateway address `10.0.0.254/24` with the built-in DHCP service disabled (Active Directory will handle leases later).
* **Outbound Routing:** Your test VM receives an IP in the `10.0.0.0/24` subnet and can resolve and browse external websites via pfSense NAT.

**CRITICAL — Virtual Switch Naming:** Hyper-V switch names must match the configuration files **exactly** with no trailing characters or spaces (`lab-switch-wan` and `lab-switch-lan`). Mismatched names will cause the pre-run checks in `01_SK_Automation-Host_CreateVM.ps1` to halt immediately. Reference screenshots of the working Hyper-V Virtual Switch Manager setup can be found in **[`images/`](../images/)** (these only mirror the guide!)

---

### How Switch Names Bind to the Automation Pipeline

The isolated switch name (Switch="lab-switch-lan") declared in Hyper-V Switch Manager (and then added to the pfSense VM, which displays as hn1 in pfSense) binds directly to the `$VMList` array inside (Step 2) **[`01_SK_Automation-Host_CreateVM.ps1`](../SK-Automation-Scripts/01_SK_Automation-Host_CreateVM.ps1)**

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

```powershell
### pfSense Interface Mapping & Architecture
```text
WAN  (wan) hn0 -> v4: 192.168.0.#/24   (Host DHCP-assigned interface - Internet access)
LAN  (lan) hn1 -> v4: 10.0.0.254/24    (Gateway for Forest 1: internal.sk-it.com - Private vSwitch: lab-switch-lan)
OPT1 (lan) hn2 -> v4: 172.32.0.254/24   (Gateway for Forest 2: Brazil.sk-it.com   - Private vSwitch: lab-switch-lan2)
```
Here is my pfSense configuration: you can see an additional pfSense interface (`OPT1 - LAN`) with the new forest vSwitch IP and subnet range (`172.32.0.254/24`) and switch name (`lab-switch-lan2`) for my second forest and domain, Brazil. This allows you to create an additional forest. For more information on configuring multiple forests and domains, please view the **[Infrastructure Customisation Guide](Customise-your-Infrastructure.md)**.

Essentially, the pfSense VM (created from the ISO) requires two virtual network adapters (vNICs), each attached to a specific Hyper-V virtual switch: the `-wan` switch for outbound external routing and the `-lan` switch for isolated internal traffic. Hyper-V presents these virtual adapters to the guest operating system, where pfSense (via FreeBSD) detects them sequentially as `hn0` (first NIC) and `hn1` (second NIC). 

It is crucial that you add these vNICs to the pfSense VM in the exact operational order:
1. **Network Adapter 1 (`hn0`):** Bound to `lab-switch-wan`. pfSense assigns the first detected interface (`hn0`) as the WAN interface, which requests an IPv4 lease via DHCP from your physical host network.
2. **Network Adapter 2 (`hn1`):** Bound to `lab-switch-lan`. pfSense assigns the second interface (`hn1`) as the LAN interface, which acts as the static default gateway (`10.0.0.254/24`) for your internal virtual machines.

Reversing this addition order causes pfSense to bind the WAN configuration to your isolated internal switch and the LAN configuration to your host network, breaking outbound routing and potentially leaking DHCP leases onto your home LAN.

Once mapped, pfSense handles stateful routing, outbound NAT, and firewall filtering between your external network and your isolated virtual lab.

**Important:** If you create an additional pfSense interface (for another forest or domain), you must create an outbound firewall pass rule on that interface to allow traffic out through `hn0` (your WAN interface), or your new machines will have no outbound internet access. This rule must be created in the pfSense WebGUI, so you will need at least one working VM connected to the internal network to log in and configure it.  You could create one forest in your first "loop" of the automation project, use a VM to connect to the pfSense Web-UI (on the default gateway IP 10.0.0.254), then create the additional interface / IP-Subnet / FW rules.