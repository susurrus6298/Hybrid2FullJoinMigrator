## variables

$TempUser = "username"
$TempUserPasswordPlain = "password"
$TempUserPassword = ConvertTo-SecureString $TempUserPasswordPlain -AsPlainText -Force

$IPAddress = "X.X.X.X" # customize: add an on-site domain controller address here

$WiFiProfile = "C:\Temp\Migration\WiFi.xml"

## functions

function Add-WiFiProfiles {
    # customize -- export corporate wi-fi profiles before deployment. Add them to this function which appears several times in the next two .ps1's
    netsh wlan add profile filename=$WiFiProfile
}

function Send-UserNotification {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("System rebooting in 1 minute. Please wait. If you are not connected to the <company name> network, you will be prompted to connect.",'Alert from <company name> IT Department','OK','Asterisk')
}

function Get-ConnectionStatus {
    $connection = Test-NetConnection $IPAddress
    $script:connected = $connection.PingSucceeded

    if ($connected) {
        Write-Output "connection check OK"
    }
    else {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("You are not connected to the <company name> network. Please reconnect your PC before continuing.",'Alert from <company name> Health IT Department','OK','Asterisk')
    }
}

function Push-PPKG {
    if ($connected) {
        Write-Output "Connection detection was true. Executing PPKG install."
        Install-ProvisioningPackage -PackagePath "C:\Temp\Migration\AADJ-JOIN.PPKG" -ForceInstall -QuietInstall
    }
    else {
        Write-Output "Connection detection was false. Looping."
        Start-PPKGInstall
    }
}

function Start-PPKGInstall {
    Get-ConnectionStatus
    Push-PPKG
}

function Set-Autologon {
    Write-Output "Setting autologon configuration"

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String -Verbose
    Set-ItemProperty $RegPath "DefaultUsername" -Value $TempUser -type String -Verbose
    Set-ItemProperty $RegPath "DefaultPassword" -Value $TempUserPasswordPlain -type String -Verbose

    $RegPathSecond = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"

    If (-NOT (Test-Path $RegPathSecond)) {
        New-Item -Path $RegPathSecond -Force | Out-Null
    }

    New-ItemProperty $RegPathSecond -Name "DevicePasswordLessBuildVersion" -Value "0" -Type DWord -Force -Verbose

    $RegPathThird = "HKLM:\SYSTEM\CurrentControlSet\Control\EAS\Policies"

    If (Test-Path $RegPathThird) {
        Set-ItemProperty $RegPathThird "1" -Value "0" -type DWord -Force -Verbose
        Set-ItemProperty $RegPathThird "2" -Value "0" -type DWord -Force -Verbose
    }

    $RegPathFourth = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

    Remove-ItemProperty $RegPathFourth "legalnoticecaption" -Force
    Remove-ItemProperty $RegPathFourth "legalnoticetext" -Force
    New-ItemProperty $RegPathFourth -Name "EnableFirstLogonAnimation" -Value "0" -Type DWord -Force -Verbose
}

function Rename-OldProfile {
    Write-Output "Renaming the old user profile folder"

    $login_name = Get-Content -Path C:\Temp\Migration\login_name.txt
    Rename-Item -Path "C:\Users\$login_name" -NewName "$login_name.old"
}

function Set-RunOnceSecond {
    Write-Output "Setting the RunOnce key for the second script on boot"

    $RunOnceKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

    Set-ItemProperty $RunOnceKey "NextRun" ('C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe -executionPolicy Unrestricted -File ' + "C:\Temp\Migration\post_reboot_second.ps1")
}

function Set-LocalAccountSetting {
    Set-LocalUser -Name $TempUser -Password $TempUserPassword -AccountNeverExpires:$true -PasswordNeverExpires:$true
}

## start

Start-Transcript -Path "C:\Temp\Migration\AADJ-R1.txt"
Add-WiFiProfiles
Rename-OldProfile
Start-PPKGInstall
Add-WiFiProfiles
Set-RunOnceSecond

Start-Process powershell -args '-noprofile', '-noexit', '-EncodedCommand',
    ([Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes(
            (Get-Command -Type Function Send-UserNotification).Definition
        )
    ))

Start-Sleep -Seconds 60
Set-LocalAccountSetting
Set-Autologon
Stop-Transcript
Restart-Computer 