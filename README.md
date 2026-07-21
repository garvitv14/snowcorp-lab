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
| RAM | 16 GB | 24 GB |
| Disk | 60 GB free | 80 GB free |
| CPU | 4 cores + VT-x/AMD-V | 6+ cores |

Your CPU must have hardware virtualisation enabled. Check your BIOS if VMs fail to start — the setting is often called "Intel VT-x", "AMD-V", or "SVM Mode" and may be off by default.

**Software**

| Tool | Version | Notes |
|------|---------|-------|
| VirtualBox | 7.2+ | [virtualbox.org](https://www.virtualbox.org/wiki/Downloads) — versions below 7.2 fail to import the Windows 11 (UEFI) boxes this lab uses |
| Vagrant | 2.4.9+ | [vagrantup.com](https://developer.hashicorp.com/vagrant/downloads) |
| Ansible | 8.0+ | `pip install ansible` |

VMware Workstation 17+ / Fusion 13+ can be used instead of VirtualBox — see [VMware setup](#vmware-workstation--fusion) below.

**Host OS:** Linux (Ubuntu, Debian, Kali) or macOS. Windows requires WSL2 — see [Troubleshooting](#troubleshooting).

> The hypervisor (VirtualBox/VMware) must run on a **bare-metal machine**, or a VM with nested virtualisation explicitly enabled. On Windows, install the hypervisor on Windows itself and drive it from WSL2 rather than nesting — see [Troubleshooting → Running on Windows (WSL2 setup)](#troubleshooting).

---

## Setup

> **On Windows?** Do not run the commands below in PowerShell, cmd, or Git Bash — none of
> them can run this lab. Ansible doesn't run natively on Windows, and even where a
> command appears to work, `vagrant.exe` run directly on Windows is explicitly broken for
> this repo's setup (see [HashiCorp's own docs](https://developer.hashicorp.com/vagrant/docs/other/wsl)).
> Install the hypervisor on Windows itself, but run every command below **inside WSL2**.
> Jump straight to [Running on Windows (WSL2 setup)](#troubleshooting) before doing
> anything else.

### Option A: VirtualBox

Run these commands on your **host machine** — a native Linux/macOS terminal, or a WSL2
shell if you're on Windows (see the warning above). VirtualBox itself is the hypervisor
these commands install and drive; you don't run anything *inside* a VirtualBox VM here.

```bash
git clone https://github.com/garvitv14/snowcorp-lab
cd snowcorp-lab
make install      # installs VirtualBox, Vagrant, Ansible, and collections
make check        # verify everything is ready
make up           # start the lab
```

### Option B: VMware Workstation / Fusion

> **Untested path.** Only Option A (above) has been run end-to-end. This VMware path is implemented but not yet verified against a real Workstation/Fusion install — expect to hit and report issues.

Same as Option A — run these on your host machine (or WSL2 on Windows), never inside a
guest VM. VMware Workstation or Fusion must be installed manually first — it cannot be
automated. `make install-vmware` installs Vagrant, the `vagrant-vmware-desktop` plugin,
and the Vagrant VMware Utility service.

```bash
git clone https://github.com/garvitv14/snowcorp-lab
cd snowcorp-lab
make install-vmware   # installs Vagrant, plugin, and VMware Utility
make check-vmware     # verify everything is ready
make up-vmware        # start the lab
```

### What to expect

First run downloads the base VM images (~19 GB total — Windows 11 is ~13 GB,
Windows Server 2022 ~6 GB, Ubuntu ~0.6 GB; each is downloaded once and reused
for both VMs that need it) then runs Ansible across all five machines. Expect
**45–90 minutes** depending on connection speed, plus first-boot time for two
Windows Server and two Windows 11 guests.

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

The Vagrantfile already uses host-only (not VirtualBox "intnet") networking for
`192.168.136.0/24` and `10.10.10.0/24` — required for the Ansible provisioner
itself, which runs from WSL2 and connects to every host by its private-network
IP (see `ansible/inventory.yml`), so this isn't optional setup, it's load-bearing
for `make up` to work at all. With WSL2's mirrored networking mode (see
[Troubleshooting](#troubleshooting)) this is reachable from inside WSL2 as-is —
no separate adapter or manual IP assignment needed. If your WSL2 Kali still
can't reach it, assign `192.168.136.30` inside WSL2 manually as a fallback. See
[Troubleshooting](#troubleshooting) for the full WSL2 setup.

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

1. Install VirtualBox (or VMware Workstation) **on Windows**, not inside WSL2.
2. Clone this repo onto a **Windows-mounted drive** (needed for synced folders). Most WSL2
   installs mount `C:\` at `/mnt/c`, but this isn't guaranteed — some distros (or a
   customized `/etc/wsl.conf` `[automount]` root) mount it elsewhere, e.g. `/c`. Confirm
   yours first:
   ```bash
   wslpath -u 'C:\'   # prints the real mount point — use this, not an assumed /mnt/c
   ```
   ```bash
   cd /mnt/c/Users/YourName/   # or whatever the command above printed
   git clone https://github.com/garvitv14/snowcorp-lab
   cd snowcorp-lab
   ```
   This matters beyond just this `cd` step: any script that hardcodes `/mnt/c/...` or
   `/c/...` instead of resolving the mount point at runtime will silently build a wrong
   path on a non-default mount — this repo's own `scripts/import_windows11.sh` hit exactly
   this bug (see git history) before switching to `wslpath -w` for every path it hands to
   a Windows binary.
3. Run the installer and lab from inside WSL2:
   ```bash
   make install          # or: make install-vmware
   make check            # or: make check-vmware
   make up                # or: make up-vmware
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

**Administrator rights.** Installing/upgrading the hypervisor on Windows
requires an elevated (Administrator) PowerShell or install session — this is
a normal Windows software-install requirement, not specific to this repo.
`install.sh` also tries to add Windows Defender exclusions for the
hypervisor's install dir, VM storage dir, and `.vagrant.d` box cache (real-time
scanning on these has been observed to cause intermittent hangs in the
WSL↔Windows calls Vagrant makes during `vagrant up` — see below). That step
also needs admin rights; if you don't have them, `install.sh` skips it with a
warning and the lab still works, just with a higher chance of the interop
hang described below. WSL2 itself must already be installed and enabled,
which also requires admin rights the first time (`wsl --install`) — this repo
assumes that's already done.

**Known WSL2 ↔ VirtualBox issues on Windows**, found running this setup:

- **VirtualBox < 7.2 fails to import any box with UEFI firmware** (`VBoxManage
  import` error: `Unknown resource type 32768 in hardware item`). This hits
  essentially all modern Windows 11 boxes, since Windows 11 requires UEFI —
  it's not specific to any one box publisher. Fix: upgrade to VirtualBox 7.2+
  (`VBoxManage --version` to check). If you hit this after an in-place
  upgrade attempt that partially failed (Defender or a driver lock mid-way),
  a full reboot is usually required before a clean reinstall will take.
- **`vagrant up` can crash on a manually-added (non-catalog) box** with "The
  box ... is not a versioned box" followed by a silent exit. Worked around in
  this repo's `Vagrantfile` via `config.vm.box_check_update = false`.
- **Windows guests resumed after a forced/unclean halt** (e.g. re-running
  `vagrant up` after the host itself rebooted) can take longer to become
  WinRM-reachable than Vagrant's default boot timeout, even though the VM
  boots fine — this repo sets `config.vm.boot_timeout = 900` to give it room.
- **Intermittent WSL↔Windows interop hangs**: an in-flight `VBoxManage.exe`
  call (invoked from WSL over the Windows interop bridge) can occasionally
  hang indefinitely even though the Windows-side process has already exited
  — `Get-Process VBoxManage` from PowerShell shows nothing, but the WSL-side
  wrapper is still blocked. If `vagrant up` seems stuck with no new output
  for several minutes, check for this (`ps aux | grep VBoxManage` inside
  WSL vs. `Get-Process VBoxManage` on Windows); kill the stuck WSL-side
  process tree and re-run `vagrant up` — Vagrant/VirtualBox state isn't lost,
  only that one call needs retrying. The Defender exclusions above reduce how
  often this happens but don't eliminate it entirely.
- **WSL can't reach any Windows-forwarded port at all** (every VM's
  WinRM/SSH connection fails/times out, `Test-NetConnection 127.0.0.1 -Port
  <port>` succeeds from PowerShell but the equivalent from WSL — e.g.
  `bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/<port>"` — fails). This is
  WSL2's NAT-based loopback relay itself being broken, not anything in this
  repo, and `make up`'s automatic retries won't fix it since it's not
  transient. Confirm first with `Get-Service NlaSvc` on Windows — if
  Network Location Awareness is stopped, new networks (including WSL's own
  virtual adapter) never get classified, which can break the relay; starting
  it (needs a genuinely elevated PowerShell — being in the Administrators
  group isn't sufficient, check `whoami /groups` for "High Mandatory Level")
  may resolve it after a `wsl --shutdown`. If that doesn't help, switching
  WSL2 to mirrored networking sidesteps the NAT relay entirely: add
  `networkingMode=mirrored` under `[wsl2]` in `%UserProfile%\.wslconfig`,
  then `wsl --shutdown` and reconnect. This is a fallback, not something
  `install.sh` sets by default — it's a newer WSL2 mode with its own
  behavior differences, and a normal Windows install's default (NAT +
  relay) works fine, as it did for most of this setup.
- **VMs that should share a private network end up isolated from each
  other** (e.g. `dc01` and `ws01` can't reach `192.168.136.x` addresses on
  each other despite both declaring a `private_network` in that subnet) —
  check with `VBoxManage list hostonlyifs` (`make check` also flags this):
  if you see more host-only adapters than expected, each stuck on a
  `169.254.x.x` (APIPA) address instead of the `.1`/`.2` address VirtualBox
  should have assigned, this is the same root cause as the NlaSvc issue
  above — a host-only adapter that never got properly configured looks
  "subnet-less" to Vagrant, so instead of reusing it for the next VM on
  that subnet, Vagrant creates a new, separate adapter. Fixing the
  underlying NlaSvc/network-classification issue and running `vagrant
  reload` (not `destroy`) lets Vagrant reconfigure the existing adapters
  correctly. As a manual last resort, `VBoxManage modifyvm <vm> --hostonlyadapter2
  <adapter-name>` can reattach a VM's NIC to a specific already-configured
  adapter (power the VM off first).

</details>

<details>
<summary><strong>One specific host keeps failing WinRM at the same point on every retry</strong></summary>

`make up`/`make provision`'s automatic retries assume the failure is transient and will
clear on its own. If instead the **same host** fails at the **same task** across several
consecutive retries (not different hosts/tasks each time — that's ordinary flakiness),
the host's WinRM listener itself has likely gotten into a stuck state rather than
anything being wrong with the task. A plain reset clears it without losing any
provisioning progress already made:

```bash
VBoxManage controlvm <vm-name> reset   # e.g. dc02, ws01
```

Give it a minute or two to fully reboot, then re-run `make provision` (or let the
in-flight retry loop pick it back up). This was the single most common cause of
stalled runs found while building this lab — a specific DC's WinRM would stop
responding to any connection at all (not just slow, genuinely unresponsive) after
extended AD DS/domain-promotion activity, and nothing short of a reset brought it back.

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
- [evil-winrm](https://github.com/Hackplayers/evil-winrm) — WinRM remote shell access
- [John the Ripper](https://github.com/openwall/john) / [Hashcat](https://hashcat.net/hashcat/) — offline password cracking

Responder, BloodHound CE, Certipy, Ligolo-ng, Impacket, and NetExec are all
pre-installed on a standard Kali Linux image and run directly from your
attacker box. **Rubeus is different** — it's a Windows (.NET) tool, not a
Kali package, and Kali doesn't ship a prebuilt binary for it (only
`Rubeus`'s C# source, e.g. under `/usr/share/powershell-empire/...`, which
needs MSBuild/.NET Framework tooling to compile). You'll need to source a
compiled `Rubeus.exe` yourself (compile it, or get a prebuilt release from a
trusted mirror) and transfer it onto the Windows host you're operating from
— it runs on the target, not on Kali.

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
