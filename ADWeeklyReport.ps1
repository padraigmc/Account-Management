Import-Module ActiveDirectory
# ======================================================================================================================================================================================================================
# Script runs weekly to email reports on Active Directory Account changes.
#
# Previous Reports are moved to an archive folder.
# 3 reports are used:
#
#             DisabledUsers.csv - accounts that have not been logged on to in the last 60 to 89 days or is yet to be logged on to 60 to 89 days after the account was created. Accounts on this list will disabled.
#             RetiredUsers.csv - accounts that have not been logged on to in the last 90+ days or is yet to be logged on to 90+ days after the account was created. Accounts on this list will moved to the 'Retired' OU.
#             ToBeDisabledUsers.csv - accounts that have not been logged on to in the last 53 to 60 days or is yet to be logged on to 53 to 60 days after the account was created.
#
# An email is then sent containing the contents of the .csv's in the email body.
#
# Reports are placed in 'C:\Reports'.
# Archived Reports are placed in 'C:\Reports\Archive'
#
# Author: Padraig McCarthy
# Email: padraig.mc1999@gmail.com
# Date: 26/08/2019
# ======================================================================================================================================================================================================================
# =========================================================== Declarations ===========================================================
#
# $OUFilter tells the script which OU's to scan accounts for. It is then converte to a script block and stored in $OUFilter_ScriptBlock so it can be used in the Get-ADUser cmdlet.
$OUFilter = { $_.DistinguishedName -like "*OU=Users*" -and $_.DistinguishedName -notlike "*OU=Test*" -and $_.SamAccountName -notlike "service-account*" }

# String variables holding the file paths to the various reports on GWRVADM01.
[String]$ReportsPath = "C:\Reports"
[String]$ArchivedReportsPath = "C:\Reports\Archive"

# Email Variables
$MailBody = $null
$MailSubject = "Summary of Active Directory Account Changes " + (Get-Date -UFormat "%D")
$FromEmailAddress = "NoReply@contoso.ie"
[Array]$ToEmailAddress = @("padraig.mccarthy@contoso.ie") # Array holding emails to send the report to, add multiple by separating each by a comma. E.g. @(john@contoso.ie, mary@contoso.ie,.....)
$SMTPServer = "192.168.144.120"
$SMTPPort = 25
$MailBody = "Summary of Changes:</br></br>"

$ListOfAttachments = [System.Collections.ArrayList]::new()
$Files = @()
$Summary = $null

# All Date Time Variables
[DateTime]$currentDate = Get-Date -Hour 00 -Minute 00 -Second 00

# Integer variables holding milestone dates (50, 55, 60, 90 days before date of execution)
[int]$53DaysAgo = Get-Date $currentDate.adddays(-53) -UFormat "%y%m%d"
[int]$60DaysAgo = Get-Date $currentDate.adddays(-60) -UFormat "%y%m%d"
[int]$83DaysAgo = Get-Date $currentDate.adddays(-83) -UFormat "%y%m%d"
[int]$90DaysAgo = Get-Date $currentDate.adddays(-90) -UFormat "%y%m%d"

$UserList = $null

$LastLogonDate = $null
# =========================================================== Functions ===========================================================
# Gets the most up to date value for the user's LastLogon attribute and returns as a string variable.
function SetLastLogonAsDateTime {
    param($Username)

    $DateList = [System.Collections.ArrayList]::new()
    $DateArray = 
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

# =========================================================== Populate ToBeDisabledUsers.csv ===========================================================
# Genereates a list called '$UserList' which holds usernames of accounts which are enabled and in the 'Users' OU.
# Accounts in the 'Test' OU are excluded as they should never be disabled.
$UserList = Get-ADUser -Filter * | Where $OUFilter_ScriptBlock  | Select-Object -ExpandProperty "SamAccountName"
       
ForEach ($Entry in $UserList) {
    # Variable gets table with a specific user's details
    $User = Get-ADUser $Entry -Properties *
    
    [datetime]$DateCreated =  Get-Date ($User.Created)

    # Milestone variables for predicting which accounts will be disabled or retired over the next 7 days.
    [int]$53DaysAfterCreation = Get-Date $DateCreated.addDays(53) -UFormat "%y%m%d"
    [int]$60DaysAfterCreation = Get-Date $DateCreated.addDays(60) -UFormat "%y%m%d"
    [int]$83DaysAfterCreation = Get-Date $DateCreated.addDays(83) -UFormat "%y%m%d"
    [int]$90DaysAfterCreation = Get-Date $DateCreated.addDays(90) -UFormat "%y%m%d"

    $LastLogonDate = SetLastLogonAsDateTime -Username $Entry
    $CompareLastLogonDate = SetLastLogonAsInt -Username $Entry
    
    # Builds 'ToBeDisabledUsers.csv' and 'ToBeRetiredUsers.csv' which holds information on users that will be disabled/retired over the next 7 days (53 - 59 days inactive)
    If ( $User.Enabled -eq $true -and ( ($CompareLastLogonDate -le $53DaysAgo -and $CompareLastLogonDate -gt $60DaysAgo) -or ( $CompareLastLogonDate -eq 0 -and $53DaysAfterCreation -le ( [int] (Get-Date -UFormat "%y%m%d") ) -and $60DaysAfterCreation -gt ( [int] (Get-Date -UFormat "%y%m%d") ) ) ) ) {
            
        $User | Select-Object @{Name="Username"; Expression={$_.SamAccountName}},@{Name="Email Address"; Expression={$_.EmailAddress}},@{Name="Last Logon"; Expression={[String]$LastLogonDate}}, @{Name="Created"; Expression={Get-Date $User.Created -UFormat "%d/%m/%y"}}, Enabled |
        Export-Csv -Path ( $ReportsPath + '\ToBeDisabledUsers.csv' ) -Append -NoTypeInformation

    }  ElseIf ( $user.DistinguishedName -notlike "*OU=Full Time*" -and ( ( $CompareLastLogonDate -le $83DaysAgo -and $CompareLastLogonDate -gt $90DaysAgo) -or ( $CompareLastLogonDate -eq 0 -and $83DaysAfterCreation -le ( [int] (Get-Date -UFormat "%y%m%d") ) -and $90DaysAfterCreation -gt ([int] (Get-Date -UFormat "%y%m%d") ) ) ) ) {
        
        $User | Select-Object @{Name="Username"; Expression={$_.SamAccountName}},@{Name="Email Address"; Expression={$_.EmailAddress}},@{Name="Last Logon"; Expression={[String]$LastLogonDate}}, @{Name="Created"; Expression={Get-Date $User.Created -UFormat "%d/%m/%y"}}, Enabled |
        Export-Csv -Path ( $ReportsPath + '\ToBeRetiredUsers.csv') -Append -NoTypeInformation
    
    
    }

}
# =========================================================== Email Report ===========================================================

# Initialise Variables
$toBeDisabled = $null
$Disabled = $null
$Retired = $null

# Get List of .csv's in $ReportsPath
$Files = Get-ChildItem -Path $ReportsPath -Filter "*.csv" |
        Sort-Object "Name" -Descending
        Select-Object -ExpandProperty Name
        
# Populates an array ($ListOfAttachments) with the .csv files to be attched to the email and imports the files to be used in the email body ($MailBody)
ForEach ($File in $Files) {

    $FilePath = $ReportsPath + '\' + $File
    
    [void]$ListOfAttachments.Add($FilePath)

    # Sets titles on tables in the email body
    If ($File -like "*ToBeDisabledUsers*") {
    
         $MailBody += "Users to be disabled this week running from " + (Get-Date ($currentDate).addDays(1) -Format "dddd d MMMM yyy") + " - " + (Get-Date ($currentDate).addDays(7) -Format "dddd d MMMM yyy") + ":</br>"
    
    } ElseIf ($File -like "*ToBeRetiredUsers*") {
    
         $MailBody += "Users to be retired this week running from " + (Get-Date ($currentDate).addDays(1) -Format "dddd d MMMM yyy") + " - " + (Get-Date ($currentDate).addDays(7) -Format "dddd d MMMM yyy") + ":</br>"
    
    } ElseIf ($File -like "*RetiredUsers*") {
    
         $MailBody += "Users retired last week running from " + (Get-Date ($currentDate).addDays(-6) -Format "dddd d MMMM yyy") + " - " + (Get-Date ($currentDate) -Format "dddd d MMMM yyy") + ":</br>"
    
    } ElseIf ($File -like "*DisabledUsers*") {
    
         $MailBody += "Users disabled last week running from " + (Get-Date ($currentDate).addDays(-6) -Format "dddd d MMMM yyy") + " - " + (Get-Date ($currentDate) -Format "dddd d MMMM yyy") + ":</br>"
    } 
    
    # Imports a .csv as HTML to be placed into $MailBody
    $CSVImport = Import-Csv -Path $filePath | Sort "Last Logon" | ConvertTo-Html -Fragment
    $MailBody += $CSVImport + "</br>"
}

$MailBody += "Note:<br/>"
$MailBody += "Any users with the Last Logon attribute as ''Never Logged On'' are yet to log in. Such users will be disabled when 'Created' + 60 days is reached and retired when 'Created' + 90 days is reached and will also be warned.<br/>"
$MailBody += "Users with no 'Email Address' attribute were not warned of their account being disabled unless done so manually.<br/>"
$MailBody += ""


#Send the email
if ($ListOfAttachments.Count -ne 0) {
    Send-MailMessage -From $FromEmailAddress -To $ToEmailAddress -SmtpServer $SMTPServer -Port $SMTPPort -Subject $MailSubject -Attachments $ListOfAttachments -Body $MailBody -BodyAsHtml 
}

# =========================================================== Archive Previous Reports ===========================================================
# Get list of files in the speified path. All with the extension '.csv' will be added.
$Files = Get-ChildItem -Path $ReportsPath -Filter "*.csv" |
        Sort-Object -Descending |
        Select-Object -ExpandProperty Name

ForEach ($File in $Files) {
    
    $FilePath = $ReportsPath + '\' + $File
    $Date = Get-Date -UFormat "%d_%m_%Y"
    $FileName = ($File.Split("."))[0]
    $Extension = "." + ($File.Split("."))[1]
    $NewFileName = $FileName + "_" + $Date + $Extension
    $RenamedDestination = $ArchivedReportsPath + '\' + $NewFileName

    Move-Item -Path $FilePath -Destination $RenamedDestination -Force
}

# ======================================================================================================================================================================================================================