## win32 pkg installation from Intune
## Upfront (pre-deployment) criteria: user has known folders backed up in OneDrive already (no user profile migration needed), also NO EAS (DeviceLock CSP) POLICIES CAN BE ACTIVE! (AUTLOGON WON'T WORK)
## Intune criteria: device is hybrid-joined and not full-joined. Determined by requirements.ps1

## Copies script files locally, and schedules a task to run every 2 days at 2pm.

Start-Transcript -Path "C:\deploy_migration.txt"

New-Item -Type Directory -Path "C:\Temp" -ErrorAction SilentlyContinue
New-Item -Type Directory -Path "C:\Temp\Migration" -ErrorAction SilentlyContinue

# versioning - customize
# Remove-Item -Path "C:\Temp\Migration\<previous version>.txt" -Force -ErrorAction SilentlyContinue
New-Item -ItemType File -Path "C:\Temp\Migration\version1.6.txt" -Force -ErrorAction SilentlyContinue

$source = ".\*"
$destination = "C:\Temp\Migration\"

Copy-Item -Force -Recurse $source -Destination $destination

## create task

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy bypass -file C:\Temp\Migration\start.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 2 -At 2pm #customize if wanted
$principal = New-ScheduledTaskPrincipal -UserId (whoami) -RunLevel Highest -LogonType Interactive
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal

Register-ScheduledTask "Migrate Device to AADJ" -InputObject $task

Stop-Transcript