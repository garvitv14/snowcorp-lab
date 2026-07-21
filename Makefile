.PHONY: up up-vmware down reset provision status ssh-ubu01 check check-vmware install install-vmware

SHELL := bash

# Vagrant always runs as the Linux binary, including under WSL2 — it drives
# ansible-playbook directly and needs to run where Ansible lives. Only the
# hypervisor stays on Windows under WSL2, so its CLI name changes (found via
# PATH — see install.sh, which adds the Windows install dir to ~/.bashrc).
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1)

VAGRANT := vagrant

ifeq ($(IS_WSL),1)
VBOXMANAGE := VBoxManage.exe
VMRUN      := vmrun.exe
else
VBOXMANAGE := VBoxManage
VMRUN      := vmrun
endif

install:
	bash install.sh

install-vmware:
	bash install.sh --vmware

# `vagrant up` is idempotent — a retry skips whatever's already
# imported/booted/provisioned and only redoes what failed.
# scripts/vagrant_up_resilient.sh handles two failure modes found running
# this lab under WSL2: known-transient WinRM/boot-timing errors, and a
# WSL<->Windows interop hang with no error at all (see the script for
# details). A real failure is not retried — it surfaces immediately.
up:
	@bash scripts/vagrant_up_resilient.sh

up-vmware:
	@bash scripts/vagrant_up_resilient.sh --provider vmware_desktop

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
	@vbox_ver="$$("$(VBOXMANAGE)" --version 2>/dev/null)"; \
	if [ -z "$$vbox_ver" ]; then \
		echo "  VirtualBox MISSING — run: make install"; \
	else \
		echo "  VirtualBox $$vbox_ver"; \
		major=$$(echo "$$vbox_ver" | cut -d. -f1); minor=$$(echo "$$vbox_ver" | cut -d. -f2); \
		if [ "$$major" -lt 7 ] || { [ "$$major" -eq 7 ] && [ "$$minor" -lt 2 ]; }; then \
			echo "  WARNING: VirtualBox < 7.2 fails to import UEFI-firmware boxes"; \
			echo "  (all modern Windows 11 boxes) — upgrade before 'make up':"; \
			echo "  https://www.virtualbox.org/wiki/Downloads"; \
		else \
			echo "  VirtualBox OK"; \
		fi; \
	fi
	@ansible --version 2>/dev/null | head -1 && echo "  ansible OK" || echo "  ansible MISSING — run: make install"
	@ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows" && echo "  ansible.windows OK" || echo "  ansible.windows MISSING — run: make install"
	@apipa=$$("$(VBOXMANAGE)" list hostonlyifs 2>/dev/null | grep -A1 "^Name:" | grep "^IPAddress:" | grep -c "169\.254\."); \
	if [ "$$apipa" -gt 0 ] 2>/dev/null; then \
		echo "  WARNING: $$apipa VirtualBox host-only adapter(s) stuck on a"; \
		echo "  169.254.x.x (APIPA) address instead of their configured static IP."; \
		echo "  This breaks 'vagrant up' private_network subnet matching — VMs meant"; \
		echo "  to share a network can end up on separate isolated adapters instead."; \
		echo "  See README.md 'WSL <-> Windows networking' troubleshooting section."; \
	fi

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
