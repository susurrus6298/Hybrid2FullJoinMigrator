## variables

$TempUser = "username"
$WiFiProfile = "C:\Temp\Migration\WiFi.xml"
$NetworkName = "<corporate network name>"

Start-Transcript -Path "C:\Temp\Migration\AADJ-R3.txt"

function Copy-DownloadsBack {
    Write-Output "Beginning copy user downloads"
    
    $sourceDirectory = "C:\Temp\Migration\Copied Downloads\*"
    $destinationDirectory = "$Env:USERPROFILE\Downloads\"
    Copy-Item -Force -Recurse -Verbose $sourceDirectory -Destination $destinationDirectory
}

function Add-WiFiProfiles {
    netsh wlan add profile filename=$WiFiProfile
}
function Complete-Cleanup {
    Write-Output "Beginning to cleanup files, accounts, and registry entries"

    Write-Output "Remove PPKG"
    
    Remove-Item "C:\Temp\Migration\AADJ-JOIN.PPKG" -Force -Confirm:$false

    Write-Output "Remove local admin user"
    # Remove-LocalUser -name $TempUser ## uncomment after testing, for deployment

    Write-Output "Remove autologon registry entries"
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty $RegPath "AutoAdminLogon" -Value "0" -type String
    Set-ItemProperty $RegPath "DefaultUsername" -Value "null" -type String 
    Set-ItemProperty $RegPath "DefaultPassword" -Value "null" -type String

    Write-Output "Remove copied downloads temporary location and files"
    Remove-Item -Path "C:\Temp\Migration\Copied Downloads" -Recurse -Force -Confirm:$false

    Write-Output "Removing scheduled task"
    Unregister-ScheduledTask -TaskName "Migrate Device to AADJ" -Confirm:$false

    Write-Output "Deleting annoying S1 decoy docs to enable OneDrive auto policy to take effect"
    Remove-Item -Path "$Env:USERPROFILE\Documents\afterSentDocuments" -Recurse -Force -Confirm:$false
}

function Send-UserNotification {
    Write-Output "Final user notification. Process completed."

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("PROCESS COMPLETED. Please sign into OneDrive, Teams, and Edge browser. If your OneDrive and Desktop files do not show within 15 minutes, restart your computer and wait another 15 minutes.",'Alert from <company name> IT Department','OK','Asterisk')
}

function Set-CompanyNetworkProfile {
    Set-NetConnectionProfile -Name $NetworkName -NetworkCategory Private -ErrorAction SilentlyContinue
}

## start

Add-WiFiProfiles
Set-CompanyNetworkProfile
Copy-DownloadsBack
Complete-Cleanup
Send-UserNotification
Resume-BitLocker -MountPoint "C:"

Stop-Transcript