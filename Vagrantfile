# SnowCorp Lab — Vagrantfile
# Supports VirtualBox and VMware Workstation/Fusion
#
# VirtualBox (default):  vagrant up
# VMware:                vagrant up --provider vmware_desktop

Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 600

  # ── DC01 — lab.local Domain Controller ───────────────────────────────────
  config.vm.define "dc01" do |dc01|
    dc01.vm.box      = "peru/windows-server-2022-standard-x64-eval"
    dc01.vm.hostname = "DC01"
    dc01.vm.communicator = "winrm"

    dc01.vm.network "private_network",
                    ip: "192.168.136.10",
                    virtualbox__intnet: "snowcorp_lab"

    dc01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC01"
      v.memory = 2048
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
    ws01.vm.box      = "gusztavvargadr/windows-11"
    ws01.vm.hostname = "WS01"
    ws01.vm.communicator = "winrm"

    ws01.vm.network "private_network",
                    ip: "192.168.136.11",
                    virtualbox__intnet: "snowcorp_lab"
    ws01.vm.network "private_network",
                    ip: "10.10.10.11",
                    virtualbox__intnet: "snowcorp_corp"

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

    ws01.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── DC02 — corp.local Domain Controller ──────────────────────────────────
  config.vm.define "dc02" do |dc02|
    dc02.vm.box      = "peru/windows-server-2022-standard-x64-eval"
    dc02.vm.hostname = "DC02"
    dc02.vm.communicator = "winrm"

    dc02.vm.network "private_network",
                    ip: "10.10.10.20",
                    virtualbox__intnet: "snowcorp_corp"

    dc02.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-DC02"
      v.memory = 2048
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
    ws02.vm.box      = "gusztavvargadr/windows-11"
    ws02.vm.hostname = "WS02"
    ws02.vm.communicator = "winrm"

    ws02.vm.network "private_network",
                    ip: "10.10.10.21",
                    virtualbox__intnet: "snowcorp_corp"

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

    ws02.vm.provision "shell", path: "scripts/ConfigureWinRM.ps1"
  end

  # ── UBU01 — Ubuntu 22.04 ─────────────────────────────────────────────────
  config.vm.define "ubu01" do |ubu01|
    ubu01.vm.box      = "ubuntu/jammy64"
    ubu01.vm.hostname = "UBU01"

    ubu01.vm.network "private_network",
                    ip: "10.10.10.31",
                    virtualbox__intnet: "snowcorp_corp"

    ubu01.vm.provider "virtualbox" do |v|
      v.name   = "SnowCorp-UBU01"
      v.memory = 1024
      v.cpus   = 1
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
