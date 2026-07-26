# SnowCorp Lab — Vagrantfile
# Supports VirtualBox and VMware Workstation/Fusion
#
# VirtualBox (default):  vagrant up
# VMware:                vagrant up --provider vmware_desktop

Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 1800

  # ── DC01 — lab.local Domain Controller ───────────────────────────────────
  config.vm.define "dc01" do |dc01|
    dc01.vm.box      = "StefanScherer/windows_2022"
    dc01.vm.hostname = "DC01"
    dc01.vm.communicator = "winrm"

    dc01.vm.network "private_network",
                    ip: "192.168.136.10"

    # Vagrant's own WinRM boot-readiness check defaults to the NAT-forwarded
    # port on 127.0.0.1. Under WSL2 with networkingMode=mirrored (needed so
    # WSL can see the lab's host-only adapters at all), that specific
    # loopback path is unreachable from inside WSL even when the guest is
    # fully booted and reachable on its real host-only IP the whole time -
    # `vagrant up` then hangs forever at "Waiting for machine to boot" even
    # on a brand-new VM, not just a resumed one. Pointing Vagrant's own check
    # at the real host-only IP instead (the same one Ansible already uses
    # successfully) avoids the broken path entirely.
    dc01.winrm.host = "192.168.136.10"

    dc01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC01"
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

    # Vagrant's own built-in private-network configuration for Windows
    # guests runs non-elevated over WinRM (confirmed in vagrant's own
    # guest_network.rb) and silently fails to apply the static IP on this
    # box, leaving the adapter on DHCP/APIPA. Re-apply it ourselves via a
    # provisioner, which Vagrant always runs elevated by default.
    dc01.vm.provision "shell",
                      path: "scripts/EnsurePrivateNetworkIPs.ps1",
                      args: ["-IPAddresses", "192.168.136.10"]
    dc01.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── WS01 — Dual-homed pivot ───────────────────────────────────────────────
  config.vm.define "ws01" do |ws01|
    ws01.vm.box      = "gusztavvargadr/windows-11"
    ws01.vm.hostname = "WS01"
    ws01.vm.communicator = "winrm"

    ws01.vm.network "private_network",
                    ip: "192.168.136.11"
    ws01.vm.network "private_network",
                    ip: "10.10.10.11"

    # See dc01's block for why this is needed under WSL2 mirrored networking.
    ws01.winrm.host = "192.168.136.11"

    ws01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-WS01"
      v.memory = 2048
      v.cpus   = 2
    end

    ws01.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"] = "SnowCorp-WS01"
      v.vmx["memsize"]     = "2048"
      v.vmx["numvcpus"]    = "2"
      v.vmx["ethernet1.virtualdev"]      = "vmxnet3"
      v.vmx["ethernet1.connectiontype"]  = "hostonly"
      v.vmx["ethernet2.present"]         = "TRUE"
      v.vmx["ethernet2.virtualdev"]      = "vmxnet3"
      v.vmx["ethernet2.connectiontype"]  = "hostonly"
    end

    # Each IP must be its own array element (not a single comma-joined
    # string) - Vagrant's shell provisioner passes each `args` entry as a
    # separate literal command-line token. A comma-joined string arrives at
    # EnsurePrivateNetworkIPs.ps1's -File invocation as ONE token, which
    # PowerShell does NOT auto-split into an array (unlike typing a
    # comma-separated value interactively) - confirmed by direct testing:
    # it silently produces a 1-element array containing the whole
    # comma-joined string, which then fails New-NetIPAddress with
    # "Invalid parameter IPv4Address ..." / Windows System Error 87.
    ws01.vm.provision "shell",
                      path: "scripts/EnsurePrivateNetworkIPs.ps1",
                      args: ["-IPAddresses", "192.168.136.11", "10.10.10.11"]
    ws01.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── DC02 — corp.local Domain Controller ──────────────────────────────────
  config.vm.define "dc02" do |dc02|
    dc02.vm.box      = "StefanScherer/windows_2022"
    dc02.vm.hostname = "DC02"
    dc02.vm.communicator = "winrm"

    dc02.vm.network "private_network",
                    ip: "10.10.10.20"

    # See dc01's block for why this is needed under WSL2 mirrored networking.
    dc02.winrm.host = "10.10.10.20"

    dc02.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC02"
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

    dc02.vm.provision "shell",
                      path: "scripts/EnsurePrivateNetworkIPs.ps1",
                      args: ["-IPAddresses", "10.10.10.20"]
    dc02.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── WS02 — corp.local workstation ────────────────────────────────────────
  config.vm.define "ws02" do |ws02|
    ws02.vm.box      = "gusztavvargadr/windows-11"
    ws02.vm.hostname = "WS02"
    ws02.vm.communicator = "winrm"

    ws02.vm.network "private_network",
                    ip: "10.10.10.21"

    # See dc01's block for why this is needed under WSL2 mirrored networking.
    ws02.winrm.host = "10.10.10.21"

    ws02.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-WS02"
      v.memory = 2048
      v.cpus   = 2
    end

    ws02.vm.provider "vmware_desktop" do |v|
      v.vmx["displayname"] = "SnowCorp-WS02"
      v.vmx["memsize"]     = "2048"
      v.vmx["numvcpus"]    = "2"
      v.vmx["ethernet1.virtualdev"]     = "vmxnet3"
      v.vmx["ethernet1.connectiontype"] = "hostonly"
    end

    ws02.vm.provision "shell",
                      path: "scripts/EnsurePrivateNetworkIPs.ps1",
                      args: ["-IPAddresses", "10.10.10.21"]
    ws02.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── UBU01 — Ubuntu 22.04 ─────────────────────────────────────────────────
  config.vm.define "ubu01" do |ubu01|
    ubu01.vm.box      = "ubuntu/jammy64"
    ubu01.vm.hostname = "UBU01"

    ubu01.vm.network "private_network",
                    ip: "10.10.10.31"

    # Same reasoning as the Windows guests' winrm.host below: under WSL2
    # NAT networking (see README/install.sh - mirrored mode was dropped
    # for stability reasons), the default NAT-loopback SSH path
    # (127.0.0.1:<forwarded-port>) is only reachable from the Windows
    # host, not from inside WSL (where vagrant itself runs) - confirmed by
    # direct testing (2026-07-26). Point at the guest's real routable IP
    # instead, which WSL can reach via the explicit routes install.sh sets
    # up. See scripts/prepare_fresh_boot.sh for how this IP gets applied
    # on a genuinely fresh boot, before Vagrant's own network-config step
    # (which needs this same SSH connection) can run.
    ubu01.ssh.host = "10.10.10.31"

    ubu01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-UBU01"
      v.memory = 1024
      v.cpus   = 1
      # The box's own bundled Vagrantfile redirects uart1 to Ruby's
      # File::NULL on every boot — since Vagrant itself runs inside WSL
      # (Linux), File::NULL resolves to "/dev/null", which VBoxManage.exe
      # (a native Windows binary) can't create (VERR_PATH_NOT_FOUND).
      # Disable the serial port entirely; this runs after the box's own
      # customize block, so it overrides it on every `vagrant up`.
      v.customize ["modifyvm", :id, "--uart1", "off"]
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
