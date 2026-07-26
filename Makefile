.PHONY: up up-vmware up-resume down reset provision orchestrate status ssh-ubu01 check check-vmware install install-vmware

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

# install.sh's own checks include a hard, fail-fast verification that WSL2
# mirrored networking is actually working (not just "probably fine") -
# without it, WSL (where vagrant/ansible run) can't reach any VirtualBox
# host-only network at all, and vagrant up would otherwise fail confusingly
# deep into provisioning instead of with a clear cause + fix steps up front.
#
# Runs prepare_fresh_boot.sh alongside vagrant up: on a genuinely fresh VM,
# Vagrant's own boot-readiness check (pointed at each Windows guest's static
# host-only IP - see Vagrantfile) would otherwise deadlock, since that IP is
# normally only set by a provisioner that Vagrant runs *after* the check
# succeeds. See scripts/prepare_fresh_boot.sh for the full explanation.
#
# vagrant up itself runs via scripts/run_vagrant_up_resilient.sh, not
# directly - confirmed recurring bug (2026-07-26, hit independently for two
# different VMs in the same run): vagrant's own WinRM connection attempt can
# get permanently stuck in TCP SYN-SENT even though the guest is genuinely
# reachable the whole time. The wrapper detects this and restarts vagrant up
# automatically - safe, since vagrant always skips whatever's already done.
# After vagrant reports success, verify_lab_reachable.sh checks ground
# truth (real connectivity to every machine) before trusting that exit
# code - confirmed directly (2026-07-26) that Vagrant's own "success" can
# be a false positive: a provisioner (e.g. the ansible run) can fail once,
# the wrapper retries `vagrant up`, and Vagrant skips re-running it on the
# retry since it already has provisioning history - reporting overall
# success while the actual configuration never completed. See
# scripts/verify_lab_reachable.sh for what's actually checked.
up: install
	bash scripts/prepare_fresh_boot.sh & \
	fixer_pid=$$!; \
	bash scripts/run_vagrant_up_resilient.sh; \
	rc=$$?; \
	kill $$fixer_pid 2>/dev/null; \
	if [ $$rc -ne 0 ]; then exit $$rc; fi; \
	bash scripts/verify_lab_reachable.sh

up-vmware:
	$(VAGRANT) up --provider vmware_desktop

# Resumes an already-created lab that was fully powered off. Starts VMs
# directly via VBoxManage instead of `vagrant up`, which can hang forever on
# "Waiting for machine to boot" under WSL2 mirrored networking (see
# scripts/resume_vms.sh for why). For first-time VM creation, use `make up`.
up-resume:
	bash scripts/resume_vms.sh

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

# Self-healing, per-host provisioning: does one host at a time, auto-detects
# and resets a genuinely stuck guest, waits out transient WinRM blips rather
# than restarting from scratch, and skips any host that's already done. Use
# this instead of `make provision` when a previous run got interrupted or
# kept hitting the same host repeatedly - see scripts/orchestrate_provision.sh
# for the full reasoning.
orchestrate:
	bash scripts/orchestrate_provision.sh

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
