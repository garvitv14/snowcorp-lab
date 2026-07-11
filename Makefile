.PHONY: up up-vmware down reset provision status ssh-ubu01 check check-vmware install install-vmware

install:
	bash install.sh

install-vmware:
	bash install.sh --vmware

up:
	vagrant up

up-vmware:
	vagrant up --provider vmware_desktop

down:
	vagrant halt

destroy:
	vagrant destroy -f

reset:
	vagrant destroy -f && vagrant up

reset-vmware:
	vagrant destroy -f && vagrant up --provider vmware_desktop

provision:
	vagrant provision

status:
	vagrant status

ssh-ubu01:
	vagrant ssh ubu01

check:
	@echo "Checking requirements (VirtualBox)..."
	@vagrant --version 2>/dev/null && echo "  vagrant OK" || echo "  vagrant MISSING — run: make install"
	@VBoxManage --version 2>/dev/null && echo "  VirtualBox OK" || echo "  VirtualBox MISSING — run: make install"
	@ansible --version 2>/dev/null | head -1 && echo "  ansible OK" || echo "  ansible MISSING — run: make install"
	@ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows" && echo "  ansible.windows OK" || echo "  ansible.windows MISSING — run: make install"

check-vmware:
	@echo "Checking requirements (VMware)..."
	@vagrant --version 2>/dev/null && echo "  vagrant OK" || echo "  vagrant MISSING — run: make install"
	@vmrun 2>/dev/null | head -1 && echo "  VMware OK" || echo "  VMware MISSING — install VMware Workstation/Fusion manually"
	@vagrant plugin list 2>/dev/null | grep -q "vagrant-vmware-desktop" && echo "  vagrant-vmware-desktop plugin OK" || echo "  vagrant-vmware-desktop plugin MISSING — run: make install-vmware"
	@test -f /opt/vagrant-vmware-desktop/certificates/vagrant-utility.client.crt \
		&& echo "  Vagrant VMware Utility OK" \
		|| (systemctl is-active --quiet vagrant-vmware-utility 2>/dev/null \
			&& echo "  Vagrant VMware Utility OK" \
			|| echo "  Vagrant VMware Utility MISSING — run: make install-vmware  (see: https://developer.hashicorp.com/vagrant/install/vmware)")
	@ansible --version 2>/dev/null | head -1 && echo "  ansible OK" || echo "  ansible MISSING — run: make install"
	@ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows" && echo "  ansible.windows OK" || echo "  ansible.windows MISSING — run: make install"
