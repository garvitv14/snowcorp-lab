.PHONY: up up-vmware down reset provision status ssh-ubu01 check check-vmware install install-vmware

# Under WSL2, Vagrant and the hypervisor run on Windows, not inside WSL — this
# calls vagrant.exe (via WSL interop) and looks for the hypervisor under
# /mnt/c instead of expecting a Linux-side install. Same pattern GOAD uses.
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1)

ifeq ($(IS_WSL),1)
VAGRANT    := vagrant.exe
VBOXMANAGE := /mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe
VMRUN      := /mnt/c/Program Files (x86)/VMware/VMware Workstation/vmrun.exe
else
VAGRANT    := vagrant
VBOXMANAGE := VBoxManage
VMRUN      := vmrun
endif

install:
	bash install.sh

install-vmware:
	bash install.sh --vmware

up:
	$(VAGRANT) up

up-vmware:
	$(VAGRANT) up --provider vmware_desktop

down:
	$(VAGRANT) halt

destroy:
	$(VAGRANT) destroy -f

reset:
	$(VAGRANT) destroy -f && $(VAGRANT) up

reset-vmware:
	$(VAGRANT) destroy -f && $(VAGRANT) up --provider vmware_desktop

provision:
	$(VAGRANT) provision

status:
	$(VAGRANT) status

ssh-ubu01:
	$(VAGRANT) ssh ubu01

check:
	@echo "Checking requirements (VirtualBox)..."
	@$(VAGRANT) --version 2>/dev/null && echo "  vagrant OK" || echo "  vagrant MISSING — run: make install"
	@"$(VBOXMANAGE)" --version 2>/dev/null && echo "  VirtualBox OK" || echo "  VirtualBox MISSING — run: make install"
	@ansible --version 2>/dev/null | head -1 && echo "  ansible OK" || echo "  ansible MISSING — run: make install"
	@ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows" && echo "  ansible.windows OK" || echo "  ansible.windows MISSING — run: make install"

check-vmware:
	@echo "Checking requirements (VMware)..."
	@$(VAGRANT) --version 2>/dev/null && echo "  vagrant OK" || echo "  vagrant MISSING — run: make install"
	@"$(VMRUN)" 2>/dev/null | head -1 && echo "  VMware OK" || echo "  VMware MISSING — install VMware Workstation/Fusion manually"
	@$(VAGRANT) plugin list 2>/dev/null | grep -q "vagrant-vmware-desktop" && echo "  vagrant-vmware-desktop plugin OK" || echo "  vagrant-vmware-desktop plugin MISSING — run: make install-vmware"
	@test -f /opt/vagrant-vmware-desktop/certificates/vagrant-utility.client.crt \
		&& echo "  Vagrant VMware Utility OK" \
		|| (systemctl is-active --quiet vagrant-vmware-utility 2>/dev/null \
			&& echo "  Vagrant VMware Utility OK" \
			|| echo "  Vagrant VMware Utility — could not verify locally (on WSL: check it's installed on Windows) — see: https://developer.hashicorp.com/vagrant/install/vmware")
	@ansible --version 2>/dev/null | head -1 && echo "  ansible OK" || echo "  ansible MISSING — run: make install"
	@ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows" && echo "  ansible.windows OK" || echo "  ansible.windows MISSING — run: make install"
