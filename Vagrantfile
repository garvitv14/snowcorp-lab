# SnowCorp Lab — Vagrantfile
# Supports VirtualBox and VMware Workstation/Fusion
#
# VirtualBox (default):  vagrant up
# VMware:                vagrant up --provider vmware_desktop

Vagrant.configure("2") do |config|

  # Windows guests booting after a forced/unclean halt (e.g. a resumed
  # `vagrant up` after the host rebooted) have been observed taking longer
  # than the default 300s to become WinRM-reachable, even though the box
  # itself boots fine — give it more headroom.
  config.vm.boot_timeout = 1200

  # Windows boxes here may be added directly (not from a Vagrant Cloud
  # catalog listing) — the per-`up` update check crashes in that case
  # (Vagrant tries to query catalog metadata that doesn't exist for a
  # directly-added box). Skip it; nothing here needs auto-update checks.
  config.vm.box_check_update = false

  # Applies to every VM below. VirtualBox's own remote-display server
  # (VRDE) is unused here — Ansible/WinRM/SSH handle all remote access —
  # but boxes can ship with it enabled and pre-configured with TLS
  # certificate paths baked in from the box author's own build machine
  # (observed: /Users/<box-author>/VirtualBox VMs/... on a box built on
  # macOS), which don't exist here. VRDE then fails to start (port bind
  # failure and/or missing certificate files). On UEFI-firmware boxes
  # (Windows 11) this has been observed to leave the video output with no
  # resolution ever set — VBoxManage screenshotpng permanently reports
  # "Unsupported resolution: 0x0" and the VM never becomes reachable, even
  # though it's technically "running" and burning CPU. Since nothing here
  # ever uses VRDE, turning it off entirely avoids the whole class of
  # failure instead of trying to make it work.
  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--vrde", "off"]
  end

  # ── DC01 — lab.local Domain Controller ───────────────────────────────────
  config.vm.define "dc01" do |dc01|
    dc01.vm.box      = "StefanScherer/windows_2022"
    dc01.vm.hostname = "DC01"
    dc01.vm.communicator = "winrm"

    # Host-only (not VirtualBox "intnet") — the Ansible provisioner runs
    # ansible-playbook on the WSL control machine, which connects to hosts
    # by their private-network IP directly (see ansible/inventory.yml). An
    # "intnet" is isolated from the host by design and would make that
    # unreachable regardless of any other networking fix.
    dc01.vm.network "private_network",
                    ip: "192.168.136.10"

    # Ansible (running on the WSL control machine) connects over this
    # stable NAT-forwarded port instead of the private-network IP above —
    # see ansible/inventory.yml. WSL's reachability into a VirtualBox
    # host-only/private network depends on WSL2 mirrored-networking mode
    # correctly mirroring that adapter, which has been unreliable in
    # practice (the adapter can report link-down inside WSL even though
    # the same address is reachable from Windows itself). NAT port
    # forwarding to 127.0.0.1 has been solid throughout — same path
    # Vagrant's own WinRM communicator already relies on for provisioning.
    dc01.vm.network "forwarded_port", guest: 5985, host: 15985, host_ip: "127.0.0.1", id: "winrm-ansible", auto_correct: false

    dc01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC01"
      # 2048 reliably left WinRM unresponsive under load (AD DS + ADCS +
      # DNS running together in 2GB, causing internal memory pressure
      # independent of host RAM headroom — confirmed by WinRM staying
      # slow/timing out even with several GB of host RAM free).
      v.memory = 3072
      v.cpus   = 2
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end

    dc01.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"]  = "SnowCorp-DC01"
      v.vmx["memsize"]      = "2048"
      v.vmx["numvcpus"]     = "2"
      v.vmx["ethernet1.virtualdev"] = "vmxnet3"
      v.vmx["ethernet1.connectiontype"] = "hostonly"
    end

    dc01.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── WS01 — Dual-homed pivot ───────────────────────────────────────────────
  config.vm.define "ws01" do |ws01|
    # Was "stromweld/windows-11" — that box reliably hung/crashed on boot
    # even under a fully manual, everything-configured-pre-boot VBoxManage
    # import (no vagrant automation involved at all), across multiple fresh
    # downloads and fresh VM instances. gusztavvargadr/windows-11 is an
    # actively maintained box (Packer-built, updated regularly) with both
    # virtualbox and vmware_desktop provider support, matching what this
    # Vagrantfile needs for both provider paths.
    ws01.vm.box      = "gusztavvargadr/windows-11"
    ws01.vm.hostname = "WS01"
    ws01.vm.communicator = "winrm"

    # Only one Vagrant-managed private_network here, not two. A second
    # private_network makes Vagrant attach a 3rd NIC to the VM — on this
    # box (stromweld/windows-11) that reliably crashes Windows itself on
    # boot: the guest lands in "Automatic Repair — Your PC did not start
    # correctly" instead of ever reaching a login screen. Confirmed via a
    # controlled A/B test (same VM instance, only difference was nic3
    # present vs. absent) — not an EFI/firmware issue, not a
    # resource/timing issue, a real guest-OS boot failure specific to a
    # 3rd NIC on this box. This isn't a rare edge case either: WS01's own
    # domain-join task (ansible/roles/ws01) always triggers a reboot, so a
    # 3rd NIC here would break the very first `vagrant up` for every user
    # at that reboot, not just recovery from an already-broken state. WS01
    # still needs to reach both the lab (192.168.136.x) and corp
    # (10.10.10.x) networks to act as a pivot — that's done by adding the
    # corp address as a *second IP on this same adapter* at the OS level
    # (see the "Add corp-network IP" task in ansible/roles/ws01), not via
    # a second VirtualBox NIC.
    ws01.vm.network "private_network",
                    ip: "192.168.136.11"

    # See dc01's comment above — same rationale.
    ws01.vm.network "forwarded_port", guest: 5985, host: 15986, host_ip: "127.0.0.1", id: "winrm-ansible", auto_correct: false

    ws01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-WS01"
      # Windows 11's own stated minimum is 4GB, and 2GB reliably OOMs
      # once domain-joined (observed: "System.OutOfMemoryException" during
      # fact-gathering under the extra GPO/Kerberos/Netlogon load). 4096
      # itself was tried and this host doesn't have headroom for it once
      # dc01+dc02+ubu01+ws01+ws02 are all running simultaneously (23.7GB
      # host RAM was down to <1GB free, causing WinRM to become
      # unresponsive under swap pressure even after a successful boot).
      # 3121 is the value confirmed working end-to-end on this lab's
      # actual host budget — see scripts/import_windows11.sh.
      v.memory = 3121
      v.cpus   = 2
    end

    ws01.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"] = "SnowCorp-WS01"
      v.vmx["memsize"]     = "4096"
      v.vmx["numvcpus"]    = "2"
      v.vmx["ethernet1.virtualdev"]      = "vmxnet3"
      v.vmx["ethernet1.connectiontype"]  = "hostonly"
      v.vmx["ethernet2.present"]         = "TRUE"
      v.vmx["ethernet2.virtualdev"]      = "vmxnet3"
      v.vmx["ethernet2.connectiontype"]  = "hostonly"
    end

    ws01.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── DC02 — corp.local Domain Controller ──────────────────────────────────
  config.vm.define "dc02" do |dc02|
    dc02.vm.box      = "StefanScherer/windows_2022"
    dc02.vm.hostname = "DC02"
    dc02.vm.communicator = "winrm"

    dc02.vm.network "private_network",
                    ip: "10.10.10.20"

    # See dc01's comment above — same rationale.
    dc02.vm.network "forwarded_port", guest: 5985, host: 15987, host_ip: "127.0.0.1", id: "winrm-ansible", auto_correct: false

    dc02.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC02"
      # See dc01's comment above — same rationale.
      v.memory = 3072
      v.cpus   = 2
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end

    dc02.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"]  = "SnowCorp-DC02"
      v.vmx["memsize"]      = "2048"
      v.vmx["numvcpus"]     = "2"
      v.vmx["ethernet1.virtualdev"]      = "vmxnet3"
      v.vmx["ethernet1.connectiontype"]  = "hostonly"
    end

    dc02.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── WS02 — corp.local workstation ────────────────────────────────────────
  config.vm.define "ws02" do |ws02|
    # See ws01's comment above — same box swap, same rationale.
    ws02.vm.box      = "gusztavvargadr/windows-11"
    ws02.vm.hostname = "WS02"
    ws02.vm.communicator = "winrm"

    ws02.vm.network "private_network",
                    ip: "10.10.10.21"

    # See dc01's comment above — same rationale.
    ws02.vm.network "forwarded_port", guest: 5985, host: 15988, host_ip: "127.0.0.1", id: "winrm-ansible", auto_correct: false

    ws02.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-WS02"
      # See ws01's comment above — same rationale.
      v.memory = 3121
      v.cpus   = 2
    end

    ws02.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"] = "SnowCorp-WS02"
      v.vmx["memsize"]     = "4096"
      v.vmx["numvcpus"]    = "2"
      v.vmx["ethernet1.virtualdev"]     = "vmxnet3"
      v.vmx["ethernet1.connectiontype"] = "hostonly"
    end

    ws02.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── UBU01 — Ubuntu 22.04 ─────────────────────────────────────────────────
  config.vm.define "ubu01" do |ubu01|
    ubu01.vm.box      = "ubuntu/jammy64"
    ubu01.vm.hostname = "UBU01"

    ubu01.vm.network "private_network",
                    ip: "10.10.10.31"

    # See dc01's comment above — same rationale (SSH here, not WinRM).
    ubu01.vm.network "forwarded_port", guest: 22, host: 15922, host_ip: "127.0.0.1", id: "ssh-ansible", auto_correct: false

    ubu01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-UBU01"
      v.memory = 1024
      v.cpus   = 1
      # The ubuntu/jammy64 box ships a serial port pointed at a Linux path
      # ("file,/dev/null") — harmless on a Linux/macOS host, but VBoxManage.exe
      # on Windows can't open that path (VERR_PATH_NOT_FOUND) and refuses to
      # boot the VM. Not needed for this lab; just turn it off.
      v.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
    end

    ubu01.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"] = "SnowCorp-UBU01"
      v.vmx["memsize"]     = "1024"
      v.vmx["numvcpus"]    = "1"
      v.vmx["ethernet1.virtualdev"]     = "vmxnet3"
      v.vmx["ethernet1.connectiontype"] = "hostonly"
    end

    ubu01.vm.provision "ansible" do |ansible|
      ansible.limit          = "all"
      ansible.playbook       = "ansible/site.yml"
      ansible.inventory_path = "ansible/inventory.yml"
      ansible.verbose        = "v"
    end
  end

end
