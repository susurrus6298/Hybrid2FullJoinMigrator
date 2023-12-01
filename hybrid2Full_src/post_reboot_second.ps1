## variables

$IPAddress = "X.X.X.X" # customize: add an on-site domain controller address here

$TempUser = "username"
$TempUserPasswordPlain = "password"

## functions

function Set-RunOnceAgain {
    Write-Output "Setting the RunOnce key for the second script on boot"

    $RunOnceKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

    Set-ItemProperty $RunOnceKey "NextRun" ('C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe -executionPolicy Unrestricted -File ' + "C:\Temp\Migration\post_reboot_second.ps1")
}

function Set-SkipUserStatusPage {
    Write-Output "Finding user ESP registry entry and setting it to skip"

    $Name = Get-ChildItem -path "HKLM:\Software\Microsoft\Enrollments\" -Recurse | Where-Object { $_.Property -match 'SkipUserStatusPage' }

    if ($Name) {
    Write-Output "Found user ESP registry entry, changing"

    $Converted = Convert-Path $Name.PSPath

    reg add $Converted /v SkipUserStatusPage /t REG_DWORD /d 4294967295 /f

    }
}

function Get-ConnectionStatus {
    $connection = Test-NetConnection $IPAddress
    $script:connected = $connection.PingSucceeded

    if ($connected) {
        Write-Output "connection check OK"
    }
    else {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("You are not connected to the <company name> network. Please reconnect your PC before continuing.",'Alert from <company name> IT Department','OK','Asterisk')
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

function Get-JoinStatus {
    Write-Output "Checking for successful join on previous boot"

    $script:joinstate = dsregcmd /status | Select-String "AzureADJoined :"
    $script:joined = $joinstate -match "YES"

    if ($joined) {
        Write-Output "Joined shows as true"
    }
    else {
        Write-Output "Joined shows as false"

        Start-PPKGInstall
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Issue: join shows as not successful. retrying and rebooting.",'Alert from <company name> IT Department','OK','Asterisk')
        Set-RunOnceAgain
        Set-Autologon
        Restart-Computer
    }
}

function Copy-BitlockerKeys {
    Write-Output "Beginning to escrow the bitlocker key"

    function Test-Bitlocker ($BitlockerDrive) {
        #Tests the drive for existing Bitlocker keyprotectors
        try {
            Get-BitLockerVolume -MountPoint $BitlockerDrive -ErrorAction Stop
        } catch {
            Write-Output "Bitlocker was not found protecting the $BitlockerDrive drive. Terminating script!"
        }
    }
    function Get-KeyProtectorId ($BitlockerDrive) {
        #fetches the key protector ID of the drive
        $BitLockerVolume = Get-BitLockerVolume -MountPoint $BitlockerDrive
        $KeyProtector = $BitLockerVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
        return $KeyProtector.KeyProtectorId
    }
    function Invoke-BitlockerEscrow ($BitlockerDrive,$BitlockerKey) {
        #Escrow the key into Azure AD
        try {
            BackupToAAD-BitLockerKeyProtector -MountPoint $BitlockerDrive -KeyProtectorId $BitlockerKey -ErrorAction SilentlyContinue
            Write-Output "Attempted to escrow key in Azure AD"
        } catch {
            Write-Error "Debug"
        }
    }
    
    ## run

    $BitlockerVolumers = Get-BitLockerVolume
    $BitlockerVolumers | ForEach-Object {
        $MountPoint = $_.MountPoint
        $RecoveryKey = [string]($_.KeyProtector).RecoveryPassword
        if ($RecoveryKey.Length -gt 5) {
            $DriveLetter = $MountPoint
            Write-Output $DriveLetter
            Test-Bitlocker -BitlockerDrive $DriveLetter
            $KeyProtectorId = Get-KeyProtectorId -BitlockerDrive $DriveLetter
            Invoke-BitlockerEscrow -BitlockerDrive $DriveLetter -BitlockerKey $KeyProtectorId
        }
    }
}

function Add-CloudUserAdmin {
    Write-Output "Adding user's cloud account as local admin"

    $upn = Get-Content -Path C:\Temp\Migration\upn.txt
    net localgroup Administrators /add "AzureAD\$upn"
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

function Stop-AutologonLast {
    Write-Output "Cleaning Autologon config for live user to login next reboot"

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty $RegPath "AutoAdminLogon" -Value "0" -type String
    Set-ItemProperty $RegPath "DefaultUsername" -Value "null" -type String -Verbose
    Set-ItemProperty $RegPath "DefaultPassword" -Value "null" -type String -Verbose

    Write-Output "Setting do not remember last logged-in user"
    New-ItemProperty $RegPath -Name "DontDisplayLastUserName" -Value "1" -Type DWord -Force -Verbose


    $RegPathSecond = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
    Set-ItemProperty $RegPathSecond "DevicePasswordLessBuildVersion" -Value "2" -Type DWord -Verbose
}

function Send-UserNotification {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("IMPORTANT PLEASE READ: Your computer is rebooting one more time in 1 minute. When your PC finishes rebooting, YOU MUST LOGIN WITH YOUR FULL <company name> EMAIL ADDRESS and password at the login screen. (including @<company domain name>)",'Alert from <company name> IT Department','OK','Asterisk')
}

function Set-RunOnceLast {
    Write-Output "Setting the RunOnce key for the third and last post-reboot script to run on login"

    $RunOnceKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

    Set-ItemProperty $RunOnceKey "NextRun" ('C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe -executionPolicy Unrestricted -File ' + "C:\Temp\Migration\post_reboot_third.ps1")
}

## start

Start-Transcript -Path "C:\Temp\Migration\AADJ-R2.txt"
Get-JoinStatus # if not joined, will reboot here and restart this script
Copy-BitlockerKeys
Add-CloudUserAdmin
Stop-AutologonLast
Set-SkipUserStatusPage
Set-RunOnceLast
Send-UserNotification
Start-Sleep -Seconds 30

Stop-Transcript
Restart-Computer