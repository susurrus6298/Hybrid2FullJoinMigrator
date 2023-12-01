# This file should always be identical to the one of the same name under .\hybrid2Full(_src)
# Intune detection rules: file exists
# 'C:\Windows\System32\Tasks\CRH Migrate Device to AADJ'

$File = "C:\Windows\System32\Tasks\Migrate Device to AADJ"
$File2 = "C:\Temp\Migration\version1.6.txt" #customize -- see deploy.ps1
$present1 = Test-Path $File
$present2 = Test-Path $File2

if ($present1 -and $present2) {
    write-output "Task found, exiting"
    exit 0
}
else {
	exit 1
}