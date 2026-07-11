```
   _____ _   ______ _       ____________  ____  ____ 
  / ___// | / / __ \ |     / / ____/ __ \/ __ \/ __ \
  \__ \/  |/ / / / / | /| / / /   / / / / /_/ / /_/ /
 ___/ / /|  / /_/ /| |/ |/ / /___/ /_/ / _, _/ ____/ 
/____/_/ |_/\____/ |__/|__/\____/\____/_/ |_/_/      

                         L A B
```

![Stars](https://img.shields.io/github/stars/garvitv14/snowcorp-lab?style=flat-square&color=yellow)
![Forks](https://img.shields.io/github/forks/garvitv14/snowcorp-lab?style=flat-square&color=blue)
![License](https://img.shields.io/github/license/garvitv14/snowcorp-lab?style=flat-square&color=green)
![Machines](https://img.shields.io/badge/machines-5-red?style=flat-square)
![Domains](https://img.shields.io/badge/domains-2-purple?style=flat-square)
![Flags](https://img.shields.io/badge/flags-3-orange?style=flat-square)

> A two-domain Active Directory lab built from scratch to practice real-world attack techniques.
> Spin it up locally, hack it, and submit your writeup.

**No cloud. No subscriptions. Runs entirely on your own machine.**

---

## Overview

SnowCorp is a fictional company with two Active Directory domains — `lab.local` and `corp.local` — connected by a forest trust. Five machines, two isolated networks, one dual-homed pivot host as the only bridge between them.

**Difficulty:** Hard

---

## Network

```
┌─────────────────────────────────────────────────────┐
│                  192.168.136.0/24                   │
│                                                     │
│   ┌──────────────┐           ┌──────────────┐       │
│   │   Attacker   │           │     DC01     │       │
│   │192.168.136.30│           │192.168.136.10│       │
│   │    (Kali)    │           │  lab.local   │       │
│   └──────────────┘           └──────┬───────┘       │
│                                     │ forest trust  │
│   ┌────────────────────────┐        │               │
│   │          WS01          │        │               │
│   │  192.168.136.11 (lab)  │◄───────┘               │
│   │  10.10.10.11   (corp)  │                        │
│   │   ★ Dual-Homed Pivot   │                        │
└───┴──────────┬─────────────┴────────────────────────┘
               │ Ligolo-ng tunnel
┌──────────────▼─────────────────────────────────────┐
│                   10.10.10.0/24                    │
│                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │
│  │     DC02     │  │     WS02     │  │  UBU01   │  │
│  │ 10.10.10.20  │  │ 10.10.10.21  │  │10.10.10.31│ │
│  │  corp.local  │  │  corp.local  │  │  Ubuntu  │  │
│  └──────────────┘  └──────────────┘  └──────────┘  │
└────────────────────────────────────────────────────┘
```

| Host | OS | IP | Role |
|------|----|----|------|
| DC01 | Windows Server 2022 | 192.168.136.10 | lab.local Domain Controller |
| WS01 | Windows 11 | 192.168.136.11 / 10.10.10.11 | Dual-homed pivot |
| DC02 | Windows Server 2022 | 10.10.10.20 | corp.local Domain Controller |
| WS02 | Windows 11 | 10.10.10.21 | corp.local Workstation |
| UBU01 | Ubuntu 22.04 | 10.10.10.31 | Linux server |

---

## Flags

| # | Host | Path |
|---|------|------|
| 1 | DC01 | `C:\Users\Administrator\Desktop\flag.txt` |
| 2 | DC02 | `C:\Users\Administrator\Desktop\flag.txt` |
| 3 | UBU01 | `/root/flag.txt` |

---

## Requirements

**Hardware**

| | Minimum | Recommended |
|-|---------|-------------|
| RAM | 12 GB | 16 GB |
| Disk | 60 GB free | 80 GB free |
| CPU | 4 cores + VT-x/AMD-V | 6+ cores |

Your CPU must have hardware virtualisation enabled. Check your BIOS if VMs fail to start — the setting is often called "Intel VT-x", "AMD-V", or "SVM Mode" and may be off by default.

**Software**

| Tool | Version | Notes |
|------|---------|-------|
| VirtualBox | 7.0+ | [virtualbox.org](https://www.virtualbox.org/wiki/Downloads) |
| Vagrant | 2.4.9+ | [vagrantup.com](https://developer.hashicorp.com/vagrant/downloads) |
| Ansible | 8.0+ | `pip install ansible` |

VMware Workstation 17+ / Fusion 13+ can be used instead of VirtualBox — see [VMware setup](#vmware-workstation--fusion) below.

**Host OS:** Linux (Ubuntu, Debian, Kali) or macOS. Windows requires WSL2 — see [Troubleshooting](#troubleshooting).

> Must run on a **bare-metal machine** or a VM with nested virtualisation explicitly enabled. See [Troubleshooting](#troubleshooting) if you are running inside VMware or VirtualBox.

---

## Setup

### VirtualBox

```bash
git clone https://github.com/garvitv14/snowcorp-lab
cd snowcorp-lab
make install      # installs VirtualBox, Vagrant, Ansible, and collections
make check        # verify everything is ready
make up           # start the lab
```

### VMware Workstation / Fusion

VMware Workstation or Fusion must be installed manually first — it cannot be automated.
`make install-vmware` installs Vagrant, the `vagrant-vmware-desktop` plugin, and the Vagrant VMware Utility service.

```bash
git clone https://github.com/garvitv14/snowcorp-lab
cd snowcorp-lab
make install-vmware   # installs Vagrant, plugin, and VMware Utility
make check-vmware     # verify everything is ready
make up-vmware        # start the lab
```

### What to expect

First run downloads the base VM images (~8 GB total) then runs Ansible across all five machines. Expect **45–60 minutes** on a reasonable connection.

A clean run ends with:

```
PLAY RECAP
dc01  : ok=8   changed=6   unreachable=0  failed=0
dc02  : ok=6   changed=5   unreachable=0  failed=0
ws01  : ok=7   changed=5   unreachable=0  failed=0
ws02  : ok=5   changed=4   unreachable=0  failed=0
ubu01 : ok=12  changed=10  unreachable=0  failed=0
```

`failed=0` on all five machines means the lab is ready.

---

## Connecting Your Attacker Machine

The lab VMs run on isolated internal networks. Your Kali machine needs to join the `192.168.136.0/24` network at IP `192.168.136.30` to reach the lab. This is the most commonly missed step.

### Kali as a VirtualBox VM (recommended)

1. Import or create a Kali VM in VirtualBox
2. Open Kali VM **Settings → Network → Adapter 2**
   - Enable the adapter
   - Attached to: **Internal Network**
   - Name: `snowcorp_lab` (case-sensitive)
3. Boot Kali and assign the static IP:

```bash
# Find the new interface (no IP, usually eth1 or ens4)
ip a

# Set IP temporarily
sudo ip addr add 192.168.136.30/24 dev eth1
sudo ip link set eth1 up

# Make it permanent
sudo nmcli connection add type ethernet ifname eth1 con-name lab \
  ipv4.method manual ipv4.addresses 192.168.136.30/24 \
  connection.autoconnect yes
sudo nmcli connection up lab
```

4. Test connectivity:

```bash
ping 192.168.136.10   # DC01 — should reply
ping 192.168.136.11   # WS01 — should reply
```

Keep Adapter 1 (NAT) for internet access. Adapter 2 is lab-only.

### VMware users

In VMware, open **Edit → Virtual Network Editor**, find the host-only network in the `192.168.136.x` range. In your Kali VM settings, add a network adapter on that same network. Then follow the same `ip addr` / `nmcli` steps above to assign `192.168.136.30/24`.

### Windows host + WSL2 Kali

Add a Host-Only adapter in VirtualBox (File → Host Network Manager → Create, set range `192.168.136.0/24`). Change `virtualbox__intnet: "snowcorp_lab"` to `type: "private_network"` in the Vagrantfile. Assign `192.168.136.30` inside WSL2. See [Troubleshooting](#troubleshooting) for the full WSL2 setup.

---

## Commands

| Command | What it does |
|---------|--------------|
| `make up` | Start and provision all VMs (VirtualBox) |
| `make up-vmware` | Start and provision all VMs (VMware) |
| `make down` | Shut down all VMs — state preserved |
| `make destroy` | Delete all VMs |
| `make reset` | Full wipe and rebuild (VirtualBox) |
| `make reset-vmware` | Full wipe and rebuild (VMware) |
| `make provision` | Re-run Ansible without rebuilding VMs |
| `make status` | Show current state of each VM |
| `make check` | Verify VirtualBox setup |
| `make check-vmware` | Verify VMware setup |

Bring up machines individually (DC01 and DC02 must be fully provisioned before workstations join their domains):

```bash
vagrant up dc01    # first
vagrant up dc02    # second
vagrant up ws01    # after DC01
vagrant up ws02    # after DC02
vagrant up ubu01   # any time after DCs
```

---

## Troubleshooting

<details>
<summary><strong>VT-x is not available (VERR_VMX_NO_VMX)</strong></summary>

Hardware virtualisation is disabled. Two places to check:

1. **BIOS** — reboot and look for "Intel Virtualization Technology", "VT-x", or "AMD-V" and enable it
2. **Running inside a VM** — go to your hypervisor VM settings → Processors → enable "Virtualize Intel VT-x/EPT" (VMware) or "Nested VT-x/AMD-V" (VirtualBox), then fully power-cycle the guest

</details>

<details>
<summary><strong>Vagrant not compatible with VirtualBox version</strong></summary>

Vagrant 2.4.3 and older do not support VirtualBox 7.2. Upgrade Vagrant:

```bash
curl -fsSL https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9-1_amd64.deb -o /tmp/vagrant.deb
sudo dpkg -i /tmp/vagrant.deb
```

</details>

<details>
<summary><strong>WinRM timeout during provisioning</strong></summary>

Windows VMs take 5–10 minutes on first boot before WinRM is available. If Ansible times out, re-run — it skips tasks already completed:

```bash
make provision
# or for a single VM:
vagrant provision dc01
```

</details>

<details>
<summary><strong>No such file: /opt/vagrant-vmware-desktop/certificates/vagrant-utility.client.crt</strong></summary>

The Vagrant VMware Utility service is not installed. `make install-vmware` handles this automatically. If you installed the plugin manually, get the utility from [developer.hashicorp.com/vagrant/install/vmware](https://developer.hashicorp.com/vagrant/install/vmware).

If installed but still failing:

```bash
sudo systemctl start vagrant-vmware-utility
sudo systemctl enable vagrant-vmware-utility
```

</details>

<details>
<summary><strong>No usable default provider (VirtualBox not detected)</strong></summary>

The VirtualBox kernel module is not loaded:

```bash
sudo modprobe vboxdrv
# If that fails:
sudo apt-get install virtualbox-dkms linux-headers-$(uname -r)
```

</details>

<details>
<summary><strong>Kali cannot ping DC01 or WS01</strong></summary>

1. Check the lab VMs are running: `vagrant status`
2. Check Kali has the right IP on the right adapter: `ip a` — should show `192.168.136.30/24`
3. In VirtualBox, confirm Kali's Adapter 2 is set to **Internal Network** → `snowcorp_lab` (case-sensitive)

</details>

<details>
<summary><strong>Domain join fails on WS01 or WS02</strong></summary>

The DCs must be fully provisioned before workstations try to join. If you brought them up out of order:

```bash
vagrant provision dc01
vagrant provision ws01
```

</details>

<details>
<summary><strong>Running on Windows (WSL2 setup)</strong></summary>

Ansible does not run on Windows natively. Use WSL2:

```bash
# Inside WSL2 (Ubuntu)
sudo apt-get update && sudo apt-get install -y ansible
ansible-galaxy collection install ansible.windows microsoft.ad community.windows

# Let WSL2 Vagrant talk to Windows VirtualBox
export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
export PATH="$PATH:/mnt/c/Program Files/Oracle/VirtualBox"

cd /mnt/c/Users/YourName/snowcorp-lab
make up
```

VirtualBox and Vagrant must be installed on Windows, not inside WSL2.

</details>

---

## Recommended Tools

Install these on your Kali machine before starting:

- [Responder](https://github.com/lgandx/Responder) — LLMNR/NBT-NS poisoning
- [BloodHound CE](https://github.com/SpecterOps/BloodHound) — AD attack path mapping
- [Certipy](https://github.com/ly4k/Certipy) — ADCS enumeration and exploitation
- [Ligolo-ng](https://github.com/nicocha30/ligolo-ng) — tunnelling into the corp network
- [Impacket](https://github.com/fortra/impacket) — Kerberos, SMB, DCSync
- [NetExec](https://github.com/Pennyw0rth/NetExec) — lateral movement and spraying
- [Rubeus](https://github.com/GhostPack/Rubeus) — Kerberos ticket manipulation

All pre-installed on a standard Kali Linux image.

---

## Walkthroughs

Owned all three flags? Got stuck on one? Both are worth writing up.

Submit a PR with your writeup at `walkthroughs/your-username.md` — no template, write it however you want.

---

## Author

**Garvit Verma** — Associate at Alvarez & Marsal, penetration tester based in Maharashtra, India.

CPTS · CRTP · DCAPT · Bug Bounty · CTF Player

I built this lab to practice Active Directory attack chains end-to-end — the same techniques I use in real engagements. If you play it, I'd love to see your writeup.

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Garvit%20Verma-blue?style=flat-square&logo=linkedin)](https://www.linkedin.com/in/garvit-verma-29298225a/)

For educational use only. Do not expose to public networks.
