# Enables WinRM for Ansible communication on Windows VMs
# Run once at first boot via Vagrant shell provisioner

$ErrorActionPreference = "Stop"

# Newly attached private_network NICs default to the "Public" firewall
# profile, which blocks WinRM's inbound exception ("WinRM firewall
# exception will not work since one of the network connection types on
# this machine is set to Public" from quickconfig below, and Ansible then
# times out connecting to the VM's private IP even though the port
# forwarding itself is fine). Force every non-Domain-classified network to
# Private before touching WinRM/firewall config, so the exception actually
# takes effect on all adapters, not just the default NAT one.
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -ne "DomainAuthenticated" } | ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
}

winrm quickconfig -q
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986

Set-Service -Name winrm -StartupType Automatic
Start-Service winrm
