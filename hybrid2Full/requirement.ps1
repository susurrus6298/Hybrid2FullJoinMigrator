# This file should always be identical to the one of the same name under .\hybrid2Full(_src)
# Intune requirement rules: device is on-prem joined (hybrid)

$DomainName = "<domain name>" #customize

$obj = Get-WmiObject Win32_ComputerSystem

if ($obj.Domain -eq $DomainName) {
    write-output "Domain found, exiting"
}
else {
	exit 1
}