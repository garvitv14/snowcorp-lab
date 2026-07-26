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
| RAM | 16 GB | 24 GB+ |
| Disk | 60 GB free | 80 GB free |
| CPU | 4 cores + VT-x/AMD-V | 6+ cores |

All 5 VMs run simultaneously once the lab is up, and the Windows guests alone can use 8–12 GB combined. 16 GB is workable but leaves little headroom for anything else running on the host at the same time — 24 GB+ is a noticeably smoother experience.

Your CPU must have hardware virtualisation enabled. Check your BIOS if VMs fail to start — the setting is often called "Intel VT-x", "AMD-V", or "SVM Mode" and may be off by default.

**Software**

| Tool | Version | Notes |
|------|---------|-------|
| VirtualBox | 7.0+ | [virtualbox.org](https://www.virtualbox.org/wiki/Downloads) |
| Vagrant | 2.4.9+ | [vagrantup.com](https://developer.hashicorp.com/vagrant/downloads) |
| Ansible | 8.0+ | `pip install ansible` |

> **VMware Workstation/Fusion support is still in development** and not yet validated end-to-end. VirtualBox is the only fully tested and supported hypervisor right now — use that unless you're specifically helping test the VMware path.

**Host OS:** Linux (Ubuntu, Debian, Kali) or macOS. Windows requires WSL2 — see [Troubleshooting](#troubleshooting).

> The hypervisor (VirtualBox) must run on a **bare-metal machine**, or a VM with nested virtualisation explicitly enabled. On Windows, install VirtualBox on Windows itself and drive it from WSL2 rather than nesting — see [Troubleshooting → Running on Windows (WSL2 setup)](#troubleshooting).

---

## Setup

```bash
git clone https://github.com/garvitv14/snowcorp-lab
cd snowcorp-lab
make install      # installs VirtualBox, Vagrant, Ansible, and collections
make check        # verify everything is ready
make up           # start the lab
make orchestrate  # run the Active Directory / domain provisioning
```

### What to expect

`make up` downloads the base VM images (~8 GB total) on first run, boots all five machines, and applies each one's baseline network configuration. Expect **20–40 minutes**, more on a slow connection or a memory-constrained host.

`make orchestrate` then runs the actual Ansible playbook that promotes the domain controllers, joins the workstations, and sets up the forest trust. Run it **after** `make up` finishes, even if `make up` itself reported success — Vagrant's own built-in Ansible step can fail once on a transient WinRM/AD hiccup and then silently skip retrying it on a later `vagrant up` retry, so `make up` succeeding is not proof the domain setup actually completed. `make orchestrate` re-runs the playbook per host, is safe to re-run, and automatically resets any host that gets genuinely stuck (as opposed to just slow).

A clean `make orchestrate` run ends with something like:

```
PLAY RECAP
dc01  : ok=8   changed=6   unreachable=0  failed=0
dc02  : ok=6   changed=5   unreachable=0  failed=0
ws01  : ok=7   changed=5   unreachable=0  failed=0
ws02  : ok=5   changed=4   unreachable=0  failed=0
ubu01 : ok=12  changed=10  unreachable=0  failed=0
```

`failed=0` on all five machines means the lab is ready.

### Things worth knowing before you start

- **First boot is slower than it looks.** Fresh Windows VMs sit on a "This might take a few minutes, don't turn off your PC" screen during their first-ever login — that's normal Windows behaviour, not a stuck VM. Give it time before assuming something's wrong.
- **Memory pressure slows everything down.** With all 5 VMs running at once, a host near its RAM limit will make Windows boots and WinRM/SSH connections noticeably flakier. If things seem oddly slow or intermittent, check your host's free memory before troubleshooting further.
- **`make orchestrate` is the reliable way to (re-)run provisioning.** If a run gets interrupted, or you're not sure whether the domain setup fully completed, run `make orchestrate` again rather than tearing anything down — it skips hosts that are already done and only touches what still needs work.

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

### Windows host + WSL2 Kali

Add a Host-Only adapter in VirtualBox (File → Host Network Manager → Create, set range `192.168.136.0/24`). Change `virtualbox__intnet: "snowcorp_lab"` to `type: "private_network"` in the Vagrantfile. Assign `192.168.136.30` inside WSL2. See [Troubleshooting](#troubleshooting) for the full WSL2 setup.

---

## Commands

| Command | What it does |
|---------|--------------|
| `make up` | Boot and network-configure all VMs |
| `make orchestrate` | Run the Ansible domain/AD provisioning (self-healing, safe to re-run) |
| `make down` | Shut down all VMs — state preserved |
| `make destroy` | Delete all VMs |
| `make reset` | Full wipe and rebuild |
| `make provision` | Re-run Ansible without rebuilding VMs (single pass, no self-healing) |
| `make status` | Show current state of each VM |
| `make check` | Verify everything is ready |

VMware equivalents (`make up-vmware`, `make check-vmware`, etc.) exist in the Makefile but are experimental and not yet fully validated — see the note under [Requirements](#requirements).

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
<summary><strong>`vagrant up` hangs forever at "Waiting for machine to boot" (WSL2)</strong></summary>

This happens on WSL2 when `.wslconfig` has `networkingMode=mirrored` (needed so WSL can see the lab's VirtualBox host-only adapters at all). `vagrant up`'s own boot-readiness check connects through the NAT-forwarded port on `127.0.0.1`, and that specific loopback path can become unreachable from inside WSL even though the VM is fully booted and reachable on its real host-only IP the whole time.

If this happens on a VM that's already been created before (e.g. you powered the lab off and are bringing it back up), skip `vagrant up` for the boot step and use:

```bash
make up-resume
```

This starts VMs directly via `VBoxManage` and verifies real readiness over the host-only network instead of the broken loopback path, then you can run `make provision` as normal. For brand-new VM creation, keep using `make up`.

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

Ansible does not run on Windows natively, and nesting a hypervisor inside a VM
(e.g. enabling "Virtualize Intel VT-x/EPT" on a Kali VM) is unreliable once
Hyper-V is active — which it is by default if you use WSL2 or the Android
emulator. So don't nest: install the **hypervisor** on Windows itself (one
level under Hyper-V, which works fine), but run **Vagrant and Ansible inside
WSL2**. Per [HashiCorp's own docs](https://developer.hashicorp.com/vagrant/docs/other/wsl),
`vagrant.exe` invoked from inside WSL "won't function correctly" — Vagrant
has to be the Linux binary. That also matters here specifically: this repo's
Vagrantfile uses Vagrant's built-in `ansible` provisioner, which shells out
to `ansible-playbook` on whatever machine runs `vagrant` — so vagrant has to
run where Ansible lives (WSL2), not as a Windows process.

1. Install VirtualBox **on Windows**, not inside WSL2.
2. Clone this repo onto a **Windows-mounted drive** (needed for synced folders):
   ```bash
   cd /mnt/c/Users/YourName/
   git clone https://github.com/garvitv14/snowcorp-lab
   cd snowcorp-lab
   ```
3. Run the installer and lab from inside WSL2:
   ```bash
   make install
   make check
   make up
   ```

`install.sh` auto-detects WSL2 and installs Vagrant + Ansible as native Linux
binaries inside WSL2 (not on Windows). It also appends to `~/.bashrc`:
`VAGRANT_WSL_ENABLE_WINDOWS_ACCESS=1` (grants WSL-side Vagrant access to
Windows resources — HashiCorp calls this "required for proper
functionality") and the Windows hypervisor's install directory on `PATH`, so
Vagrant can shell out to `VBoxManage.exe`/`vmrun.exe`. Open a new shell (or
`source ~/.bashrc`) after the first `make install` for these to take effect.
The `Makefile` picks the right hypervisor CLI name automatically — `make up`
behaves the same as on native Linux/macOS from there.

If you'd rather not put `VAGRANT_HOME` on a Windows-mounted (DrvFs) path —
DrvFs is noticeably slower for the many small files Vagrant/box caches
write — set `VAGRANT_HOME` to a native WSL ext4 path (e.g.
`export VAGRANT_HOME=~/.vagrant.d` before `VAGRANT_WSL_ENABLE_WINDOWS_ACCESS`
normally auto-relocates it) and keep only the project checkout itself on
`/mnt/c`.

Your Kali attacker VM is unaffected by any of this — it doesn't need nested
virtualisation either, it just needs a NIC on the lab's internal network (see
[Connecting Your Attacker Machine](#connecting-your-attacker-machine)).

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
