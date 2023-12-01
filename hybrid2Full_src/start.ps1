## Scheduled task is to prompt users every 2 days by executing this.

## variables

$TempUser = "username"
$TempUserPasswordPlain = "password"
$TempUserPassword = ConvertTo-SecureString $TempUserPasswordPlain -AsPlainText -Force

$IPAddress = "X.X.X.X" # customize: add an on-site domain controller address and un-join acct here

$UnjoinUser = "<domain>\<samAccountName>"
$UnjoinPasswordPlain = "<password>"
$UnjoinPassword = ConvertTo-SecureString $UnjoinPasswordPlain -AsPlainText -Force
$UnjoinCredential = New-Object System.Management.Automation.PSCredential ($UnjoinUser, $UnjoinPassword)

## functions

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
function Add-LocalUser {
    Write-Output "Creating temporary local user"

    New-LocalUser -Name $TempUser -Password $TempUserPassword -Description "Account used for autologin during migration" -AccountNeverExpires:$true -PasswordNeverExpires:$true
    Add-LocalGroupMember -Group "Administrators" -Member $TempUser
}

function Set-Autologon {
    Write-Output "Setting autologon configuration, and other logon settings"

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

function Disable-OOBEPrivacy {
    Write-Output "Disabling OOBE Privacy"

    $RegistryPathUser = 'HKCU:\Software\Policies\Microsoft\Windows\OOBE'
    $RegistryPathMachine = 'HKLM:\Software\Policies\Microsoft\Windows\OOBE'
    $Name = 'DisablePrivacyExperience'
    $Value = '1'

    If (-NOT (Test-Path $RegistryPathUser)) {
        New-Item -Path $RegistryPathUser -Force | Out-Null
    }  

    New-ItemProperty -Path $RegistryPathUser -Name $Name -Value $Value -PropertyType DWORD -Force -Verbose

    If (-NOT (Test-Path $RegistryPathMachine)) {
        New-Item -Path $RegistryPathMachine -Force | Out-Null
    }  

    New-ItemProperty -Path $RegistryPathMachine -Name $Name -Value $Value -PropertyType DWORD -Force -Verbose
}

function Remove-Domain {
    Write-Output "Performing domain-join removal, and rebooting machine"

    dsregcmd.exe /leave /debug
    dsregcmd.exe /cleanupaccounts
    Remove-Computer -UnjoinDomainCredential $UnjoinCredential -Verbose -Force -PassThru
    Restart-Computer
}

function Copy-Downloads {
    Write-Output "Copying currently logged-in user's downloads folder contents to temp. location"

    New-Item -ItemType Directory -Path "C:\Temp\Migration\Copied Downloads" -ErrorAction SilentlyContinue

    $sourceDirectory = "C:\Users\$Env:UserName\Downloads\*"
    $destinationDirectory = "C:\Temp\Migration\Copied Downloads\"

    Copy-Item -Force -Recurse -Verbose $sourceDirectory -Destination $destinationDirectory
}

function Write-UserNameFile {
    Write-Output "Writing username and login name to file for use post-reboot"

    $login_name = "$Env:UserName"
    $login_name | Out-File C:\Temp\Migration\login_name.txt
    $upn = "$Env:UserName@crossroadshealth.org"
    $upn | Out-File C:\Temp\Migration\upn.txt
}

function Set-RunOnceFirst {
    Write-Output "Setting the RunOnce key for the first post-reboot script to run on login"

    $RunOnceKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

    Set-ItemProperty $RunOnceKey "NextRun" ('C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe -executionPolicy Unrestricted -File ' + "C:\Temp\Migration\post_reboot_first.ps1")
}

function Start-Script {
    Write-Output "User confirmed. Starting process..."

    Get-ConnectionStatus

    if ($connected) {
        Write-Output "Connection check OK, continuing"

        Suspend-BitLocker -MountPoint "C:" -RebootCount 0 -Verbose
        Add-LocalUser
        Set-Autologon
        Disable-OOBEPrivacy
        Copy-Downloads
        Write-UserNameFile
        Set-RunOnceFirst
        Remove-Domain #reboots
    }
    else {
        Start-Script
    }
}

function Get-Choice {
    Write-Output "Getting user's choice to continue or not"
    
    Add-Type -AssemblyName PresentationFramework
    $msgBoxInput =  [System.Windows.MessageBox]::Show("ATTENTION: There is required maintenance for your PC. Please choose OK if you have 15 minutes to complete. Note: Please be sure that all of your files are in OneDrive before continuing, that you know your current email password, and that you are connected and YOU MUST BE ON-SITE. Click Cancel if you do not have time right now. You will be prompted again in two days at 2pm, if you click Cancel. Please remain ATTENTIVE at your PC during the process.",'Alert from <company name> IT Department','OKCancel','Asterisk')

    switch ($msgBoxInput) {
        'OK' {
            Start-Script
        }
        
        'Cancel' {
            exit
        }
    }
}

## start

Start-Transcript -Path "C:\Temp\Migration\AADJ-start.txt"
Get-Choice
Stop-Transcript