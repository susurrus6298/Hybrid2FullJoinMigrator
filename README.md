# Hybrid2FullMigrator
 10-minute migrator of HAADJ devices to AADJ
 Aaron Murphy 11/15/2023

 some functions (such as Copy-BitlockerKeys and Disable-OOBEPrivacy) derived from https://github.com/Mauvlans/ADJoin-to-AADJoin/blob/main/MMS_AD2AAD_Standalone.ps1

 it is suggested to use https://oofhours.com/2023/02/14/simplify-the-process-of-generating-an-aad-bulk-enrollment-provisioning-package/ for generating the required PPKG but is not required

TO USE: follow all requirements and customizations and then create a win32 package for Intune distribution.
Output the package file to the .\hybrid2Full folder. The source folder is hybrid2Full_src. 
You must use Microsoft's Intune win32 packager to do this.
Create the application in Intune, upload the package, utilize the requirement.ps1 and detection.ps1 for 
requirements check and installation detection. Assign computers to that application that you wish to migrate.

REQUIREMENTS: 
1. Your target devices must utilize OneDrive known-folder backup. This script does not perform
a profile migration and it relies on the profile being backed up in OneDrive, which only makes sense for
companies that use MS licensing anyway. However, it does migrate the files in the Downloads folder of the
User profile, since this is not included in MS's OneDrive backup scheme.

2. Your devices must have a certain amount of free space available to create the new user profile and also
to copy the Downloads to it

3. The devices, obviously, must be Hybrid joined

4. The script should be run on-site with line-of-sight to a domain controller (it is probably OK to not require
this, but it makes sure the users are nearby for support at the very least)

5. The executing users must have local admin rights on the machine

6. The script sets the executing user's cloud (AzureAD/Entra) account that corresponds to their on-prem account
as a local admin on the device during the script. This must be a desired outcome

7. You need to utilize Windows Imaging and Configuration Designer in combination with AADInternals to create a barebones
preprovisioning PPKG file that joins devices to your AAD domain. The one I've included is an empty file. See here for an
easier way to get this done, by Michael Niehaus: 

    https://oofhours.com/2023/02/14/simplify-the-process-of-generating-an-aad-bulk-enrollment-provisioning-package/

    specifics excerpted:

    1. install WICD and open it (sets environment variables)
    2. install AADInternals PS Module
    3. download script: https://oofhours.files.wordpress.com/2023/02/generate-aad-ppkg.zip
    3. execute in an admin shell: .\Generate-AAD-PPKG.ps1
    4. take this PPKG and place it in the hybrid2Full_src folder, name it AADJ-JOIN.PPKG

Note: The PPKG adds devices to Entra via a package_user_xxxxxx account. Give this account an Intune License, exclude
it from CA policy requiring MFA, and make it a device enrollment administrator in Intune. Devices are added with this
user as the enrolling user, and with no primary user. You must use a companion process to this script which will go
into Intune and set the appropriate Primary Users to the devices according to who is signing into them which can be
done programmatically.

YOU NEED TO CUSTOMIZE THE FOLLOWING PARTS OF THESE SCRIPTS:
1. versioning in deploy.ps1 and detection.ps1: if you make changes to the script and need to redeploy to devices
without uninstalling (the deploy overwrites existing files), create a new version1.x.txt file in the deploy.ps1 and
make the detection.ps1 look for it.

2. the $IPAddress variables in start.ps1, post_reboot_first.ps1, and post_reboot_second.ps1. Make this the IP
address of a domain controller reachable on-site where the users will be executing the migration.

3. the $TempUser, $TempUserPasswordPlain variables in start.ps1, post_reboot_first.ps1, and post_reboot_second.ps1
are to be set however one wishes. This is a temporary LOCAL admin account that is created for use during the process
and it gets removed on the last step

4. after testing, uncomment the temp. local account user removal found under the Complete-Cleanup function in
post_reboot_third.ps1. This removes the temp. local account used instead of leaving it there.

5. the $UnjoinUser and $UnjoinPasswordPlain variables in start.ps1 must be customized: create an AD user for this purpose
that has only enough permissions to disable computer accounts on your AD domain and then put the user and password here.

6. export a wi-fi profile that corresponds to your corporate wi-fi network to an xml and then replace the WiFi.xml dummy file
in the root with that xml file. Now set the variable $WiFiProfile in post_reboot_first.ps1 and post_reboot_third.ps1 to
correspond to the filename of your corporate wi-fi profile xml file, leaving the rest of the path intact in that variable.
You can export and use one or many .xml's, just execute the command once for each one.

7. replace <company name> in each of the user prompts in each of the following files: start.ps1, post_reboot_first.ps1,
post_reboot_second.ps1, post_reboot_third.ps1. You can find these in the Send-UserNotification and Get-ConnectionStatus functions.

8. replace <domain name> in the requirements.ps1 files with your domain name e.g. "domain.local"

9. replace <network name> in post_reboot_third.ps1 Set-CompanyNetworkProfile function with the name of your company network
connection profile, so that it can be set as Private upon script completion and trusted by the PC.

9. Generate your PPKG (see #8 above)

10. Package your intunewin package file and deploy to devices

FULL PROCESS DESCRIPTION

deploy.ps1
1. The Intune-distributed package deploys to the device, which creates a scheduled task that runs every 2 days and prompts the user

start.ps1
1. (prompts user to Y or N)
2. Checks for connection to domain controller
3. Suspends BitLocker protection on C:
4. Adds the temp. local admin account
5. Sets autologon registry entries, also stops first-logon animation, tries to trash any EAS policies,
    gets rid of legal caption
6. Disables OOBE privacy questions screen
7. Copies user's downloads to temp. location
8. Writes the user's username and cloud upn to a file
9. Sets RunOnce
10. Removes the device from the domain as well as Entra hybrid-join
11. reboots

post_reboot_first.ps1
1. (logs in with autologon)
2. adds corporate wi-fi profile (since leaving join, may have forgotten wi-fi)
3. renames the old user profile folder
4. installs the PPKG (joins to Entra)
5. adds wi-fi profile(s) again (since joining Entra sometimes effects this)
6. Sets RunOnce for the next
7. Notifies user of impending reboot (60 seconds to allow for join processes)
8. Sets the temp. local account to not expire again (in the case of insidious EAS policies)
9. Sets autologon again (also in the case of insidious EAS policies)

post_reboot_second.ps1
1. (logs in with autologon)
2. Gets the Join status. If found not to be Entra-joined, will reinstall the PPKG and then reboot and rerun
    this .ps1 again
3. Copies BitLocker keys to Entra for safekeeping
4. Adds the executing user's cloud account UPN to the local admin group
5. Stops autologon (sets reg key to 0/off) and sets it to not remember the last user that was logged in at
    the login screen upon reboot.
6. Sets RunOnce for the next and last .ps1
7. Sets the option to skip the user ESP for autopilot devices
8. Notifies the user of impending reboot (30 seconds) and instructs them to login with their cloud 
    account on login screen
9. reboots

post_reboot_third.ps1
1. (user logs in with cloud account/email address)
2. adds wi-fi profile(s) again (yes, again) since we want the profile to be deployed for the user
3. Sets the network to be a Private network and not Public
4. Copies the user's downloads to their new user profile Downloads folder
5. Completes a cleanup by deleting files and resetting registry entries
6. Notifies the user that the process is completed.
7. Resumes Bitlocker protection.

Each script outputs a transcript for troubleshooting at C:\Temp\Migration\