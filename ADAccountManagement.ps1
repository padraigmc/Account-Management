Import-Module ActiveDirectory

# ==================================================================================================================================================================================================
# This script will notify users of their account being inactive and will disable or retire the account after a certain length of inactivity.
# 
# The user will be emailed, notifying them after 50 and 55 days of inactivity and possible account disabling. At 80 days the user will be warned of account retirement.
# On the 60th day of inactivity, the account will be disabled and the user will be notified via email.
# On the 90th day of inactivity, the account will be retired and the user will be notified via email.
# 
# There are 2 .csv's: UsersDisabled.csv, UsersRetired.csv. Both are stored in "C:\Reports".
# Users whose accounts are disabled/retired will be added to their respective report when they are disabled or retired.
#
# Full time staff will never be retired.
# Note: The term 'retire' refers to moving an account to the 'Retired' OU in the active directory.
#
# Author: Padraig McCarthy
# Email: padraig.mc1999@gmail.com
# Date 26/08/2019
# ==================================================================================================================================================================================================
# ============================================================= Declarations =============================================================

# $OUFilter tells the script which OU's to scan accounts for.
[ScriptBlock]$OUFilter = { $_.DistinguishedName -like "*OU=Users*" -and $_.DistinguishedName -notlike "*OU=Test*" -and $_.SamAccountName -notlike "service-account*" }

# String variable holding the path to the file containing the exported .csv's
$ExportPath = "C:\Reports"

# Email Variables
$Subject = "Account Inactive Notification"
$FromEmailAddress = "NoReply@contoso.ie"
$SMTPServer = "192.168.144.120"
$SMTPPort = 25
$BccList = @("padraig.mccarthy@contoso.ie")

# All Date Time Variables
[DateTime]$CurrentDate = Get-Date -Hour 00 -Minute 00 -Second 00

# String variables holding milestone dates (50, 55, 60, 90 days before date of execution)
[int]$50DaysAgo = Get-Date $CurrentDate.adddays(-50) -UFormat "%y%m%d" # Warn milestone
[int]$55DaysAgo = Get-Date $CurrentDate.adddays(-55) -UFormat "%y%m%d" # Warn milestone
[int]$60DaysAgo = Get-Date $CurrentDate.adddays(-60) -UFormat "%y%m%d" # Disable user
[int]$80DaysAgo = Get-Date $CurrentDate.adddays(-80) -UFormat "%y%m%d" # Warn milestone
[int]$90DaysAgo = Get-Date $CurrentDate.adddays(-90) -UFormat "%y%m%d" # Retire user

# ArrayList of usernames to be disabled (60 - 89 days inactive)
$DisableList = [System.Collections.ArrayList]::new()
# ArrayList of usernames to be retired (90+ days inactive)
$RetireList = [System.Collections.ArrayList]::new()

# Array which holds the usernames in the selected OU.
$UserList = $null

# ===================================================================================================================================================================================================================================

# ============================================================== Functions ==============================================================
# Gets the most up to date value for the user's LastLogon attribute and returns as a string variable.
function SetLastLogonAsDateTime {
    param($Username)

    $DateList = [System.Collections.ArrayList]::new()
    $DateArray = @()
    $LastLogonDate = Get-ADUser $Username -Properties * | Select -ExpandProperty LastLogonDate

    # Get value of $Username.LastLogon in every domain controller.
    foreach ($DC in ( (Get-ADDomainController -filter *).name )) {
        
        # Retrieve $username.LastLogon from the domain controller $dc and add to an arraylist
        $LastLogon = Get-ADUser $Username -Properties * -server $DC | Select -ExpandProperty LastLogon    
        [void]$DateList.Add( $LastLogon )
    
    }
    
    # Arraylist converted to an array and sorted so lastest date is first (at index 0)
    $DateArray = $DateList.ToArray() | Sort-Object -Descending
    
    if ($DateArray -ne $null -and $DateArray -ne 0) {
    
        return Get-Date ($DateArray[0]) -UFormat "%d/%m/%y"
        
    } ElseIf ( $LastLogonDate -ne $null ) {
    
        return Get-Date ($LastLogonDate) -UFormat "%d/%m/%y"
        
    } Else {

        return "Never Logged On"

    }
}

# Gets the most up to date value for the user's LastLogon attribute and returns as an integer variable.
function SetLastLogonAsInt {
    param($Username)

    $DateList = [System.Collections.ArrayList]::new()
    $DateArray = @()
    $LastLogonDate = Get-ADUser $Username -Properties * | Select -ExpandProperty LastLogonDate

    # Get value of $Username.LastLogon in every domain controller.
    foreach ($DC in ( (Get-ADDomainController -filter *).name )) {
        
        # Retrieve $username.LastLogon from the domain controller $dc and add to an arraylist
        $LastLogon = Get-ADUser $Username -Properties * -server $DC | Select -ExpandProperty LastLogon    
        [void]$DateList.Add( $LastLogon )
    
    }
    
    # Arraylist converted to an array and sorted so lastest date is first (at index 0)
    $DateArray = $DateList.ToArray() | Sort-Object -Descending
    
    if ($DateArray -ne $null -and $DateArray -ne 0) {
    
        return [int] (Get-Date ($DateArray[0]) -UFormat "%y%m%d")
    
    } ElseIf ( $LastLogonDate -ne $null ) {

        return [int] (Get-Date ($LastLogonDate) -UFormat "%y%m%d")
       
    } Else {
    
         return 0
         
    }
}

# =========================================================== List Population ===========================================================

# 2 lists are created:
#
#        $DisableList - ArrayList of accounts (username) that have not been logged on to in the last 60 to 89 days or is yet to be logged on to 60 to 89 days after the account was created. Accounts on this list will disabled.
#
#        $RetireList - ArrayList of accounts (username) that have not been logged on to in the last 90+ days or is yet to be logged on to 90+ days after the account was created. Accounts on this list will moved to the 'Retired' OU.
#
# Users are emailed when they reach 50/55/80 days of inactivity, when disabled and when retired.
#
# '$UserList' holds usernames of accounts which are enabled and in the 'Users' OU.
# Accounts in the'Test' OU are excluded as they should never be disabled.

# List of usernames that comply with $OUFilter
$UserList = Get-ADUser -Filter * | Where  $OUFilter  | Select-Object -ExpandProperty "SamAccountName"

ForEach ($Entry in $UserList) {

    # Table with a specific user's details
    $User = Get-ADUser $Entry -Properties *
    
    # Username.LastLogon and Username.Created formatted as yymmdd as in integer (190731 - 31st July 2019)
    $LastLogonDate = SetLastLogonAsInt -Username $Entry
    [int]$DateCreated = Get-Date ($User.Created) -UFormat "%y%m%d"
    

    # --------------------------------------------- Warn Users & Fill Lists ---------------------------------------------
    # Warn user of lockout at day 50 of inactivity
    If ( $User.Enabled -eq $true -and ( ( $LastLogonDate -eq $50DaysAgo) -or ( $LastLogonDate -eq 0 -and $DateCreated -eq $50DaysAgo) ) ) {
       
        $DisableDate = Get-Date $CurrentDate.adddays(10) -UFormat "%A %d %B %Y" 

        $Body = $User.DisplayName + ",`n`n"
        $Body += "Your user account '" + $User.SamAccountName + "' has been inactive for 50 days and will be disabled in 10 days as per Contoso policy.`n"
        $Body += "Please logon to the contoso network before " + $DisableDate + " to prevent automatic lockout -`n`n"

        # Set seperate body for full time and part time users
        If ($user.DistinguishedName -like "*Full Time*")
        {
        $Body += "https://www.login.contoso.ie`n`n"
        }
        Else
        {
        $Body += "https://www.contoso.ie`n`n"
        }

        $Body += "Please contact IT@contoso.ie to reset your password if required.`n`n"
        $Body += "Contoso IT"

        # -To $User.EmailAddress
        Send-MailMessage -From $FromEmailAddress -To $User.EmailAddress -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -Bcc $BccList
    
    # Warn user of lockout at day 55 of inactivity
    } ElseIf ( $User.Enabled -eq $true -and ( ( $LastLogonDate -eq $55DaysAgo) -or ( $LastLogonDate -eq 0 -and $DateCreated -eq $55DaysAgo) ) ) {

        $DisableDate = Get-Date $CurrentDate.adddays(5) -UFormat "%A %d %B %Y" 

        $Body = $User.DisplayName + ",`n`n"
        $Body += "Your user account '" + $User.SamAccountName + "' has been inactive for 55 days and will be disabled in 5 days as per Contoso policy.`n"
        $Body += "Please logon to the contoso network before " + $DisableDate + " to prevent automatic lockout -`n`n"

        # Set seperate body for full time and part time users
        If ($user.DistinguishedName -like "*Full Time*")
        {
            $Body += "https://www.login.contoso.ie`n`n"
        }
        Else
        {
            $Body += "https://www.contoso.ie`n`n"
        }

        $Body += "Please contact IT@contoso.ie to reset your password if required.`n`n"
        $Body += "Contoso IT"

        # -To $User.EmailAddress
        Send-MailMessage -From $FromEmailAddress -To $User.EmailAddress -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -Bcc $BccList
    

    # Disable Accounts (60+ since last logon)
    } ElseIf ( $User.Enabled -eq $true -and ( ( $LastLogonDate -le $60DaysAgo -and $LastLogonDate -ne 0) -or ( $LastLogonDate -eq 0 -and $DateCreated -le $60DaysAgo ) ) ) {
        
        # Add username to the list of accounts to be disabled
        [void]$DisableList.Add($User.SamAccountName)

    # Warn user of retirement (80 days since last logon). Full Time staff will not be retired.
    } ElseIf ( $User.DistinguishedName -notlike "*OU=Full Time*" -and ( ( $LastLogonDate -eq $80DaysAgo) -or ($LastLogonDate -eq 0  -and $DateCreated -eq $80DaysAgo ) ) ) {
    
        $DisableDate = Get-Date $CurrentDate.adddays(10) -UFormat "%A %d %B %Y" 
        
        $Body = $User.DisplayName + ",`n`n"
        $Body += "Your user account '" + $User.SamAccountName + "' has been inactive for 80 days and will be retired in 10 days as per contoso policy.`n"
        $Body += "Please contact IT@contoso.ie before " + $DisableDate + " to prevent this automated action.`n`n"                 
        $Body += "After 90 days all accounts are retired and a service now request is required to reinstate.`n`n"                 
        $Body += "Contoso IT"

        # -To $User.EmailAddress
        Send-MailMessage -From $FromEmailAddress -To $User.EmailAddress -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -Bcc $BccList

    # Retire Account (90+ days since last logon)
    } ElseIf ( $User.DistinguishedName -notlike "*OU=Full Time*" -and ( ($LastLogonDate -le $90DaysAgo -and $LastLogonDate -ne 0) -or ( $LastLogonDate -eq 0 -and $DateCreated -le $90DaysAgo ) ) ) {                    
        
        # Add username to the list of accounts to be retired
        [void]$RetireList.Add($User.SamAccountName)

    }
}

# =========================================================== Account Disabling & Notifying ===========================================================

ForEach ($Entry in $DisableList) {
    $User = Get-ADUser $Entry -Properties *

    # Disable-ADAccount uses the DistinguishedName as the identity parameter (e.g "CN=Padraig McCarthy,OU=Users,OU=,DC=Contoso,DC=IE")
    $DistinguishedName = $user.DistinguishedName
    # Disables the user account
    Disable-ADAccount -Identity $DistinguishedName
   
    # Updates the user variable
    $User = Get-ADUser $Entry -Properties *     

    If (!$User.Enabled) {
        
        # Add user to report
        $User | Select-Object @{Name="Username"; Expression={$_.SamAccountName}},@{Name="Email Address"; Expression={$_.EmailAddress}},@{Name="Last Logon"; Expression={ (SetLastLogonAsDateTime -Username $Entry) }}, @{Name="Created"; Expression={Get-Date $user.Created -Format "dd/MM/yy"}}, Enabled |
                Export-Csv ( $ExportPath + '\DisabledUsers.csv' ) -Append -NoTypeInformation

        # Set email variables
        $Body = $User.DisplayName + ",`n`n"
        $Body += "Your account '" + $User.SamAccountName + "' has been disabled.`n"
        $Body += "This automated action was performed due to 60 days without any activity.`n`n"
        $Body += "You can email IT@contoso.ie within the next 30 days to reinstate your access.`n`n"
        $Body += "Please note that your account will be retired if not used for 90 days or more.`n`n"
        
        If ($user.DistinguishedName -notlike "*Full Time*") { $Body += "At this point a service now application will be required in order to restore your account.`n`n" }
        
        $Body += "Contoso OT"

        # Send email
        Send-MailMessage -From $FromEmailAddress -To $User.EmailAddress -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -Bcc $BccList
    }
}

# =========================================================== Account Retiring & Notifying ===========================================================

ForEach ($Entry in $RetireList) {
    $User = Get-ADUser $Entry -Properties *

    # Move-ADObject uses the DistinguishedName as the identity parameter (e.g "CN=Padraig McCarthy,OU=Users,DC=Contoso,DC=IE")
    $DistinguishedName = $User.DistinguishedName
    # Moves user to the Retired Users OU ("OU=Retired,DC=Contoso,DC=IE")
    Move-ADObject -Identity $DistinguishedName -TargetPath "OU=Retired,DC=Contoso,DC=IE"


    [String]$DateCreated = Get-Date $User.Created -UFormat "%d%m%y"
    
    # Updates the user variable
    $User = Get-ADUser $Entry -Properties *

    If ($User.DistinguishedName -like "*Retired*") {
        
        # Add user to report
        $User | Select-Object @{Name="Username"; Expression={$_.SamAccountName}},@{Name="Email Address"; Expression={$_.EmailAddress}},@{Name="Last Logon"; Expression={ (SetLastLogonAsDateTime -Username $Entry) }}, @{Name="Created"; Expression={Get-Date $user.Created -Format "dd/MM/yy"}}, Enabled |
                Export-Csv ( $ExportPath + '\RetiredUsers.csv') -Append -NoTypeInformation
        
        
        # Set email variables
        $Body = $User.DisplayName + ",`n`n"
        $Body += "Your account '" + $User.SamAccountName + "' has been retired.`n"
        $Body += "This automated action was performed due to 90 days without any activity.`n`n"
        $Body += "Please log an IT application to reinstate access if required -`n`n"
        $Body += "https://www.contoso.ie/ITHelp`n`n"
        $Body += "Contoso IT"

        # Send email
        Send-MailMessage -From $FromEmailAddress -To $User.EmailAddress -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Port $SMTPPort -Bcc $BccList
    }
}
# ===================================================================================================================================================================================================================================