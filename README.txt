Contoso User Account Managment powershell scripts README.

Author:	Padraig McCarthy
Email:	padraig.mccarthy1999@gmail.com
Date:	21/08/2019
=============================================================================== ADAccountManagement.ps1 ===============================================================================
Purpose : 	To automatically warn, disable and retire Contoso user accounts due to extended periods of account inactivity (no logon over a period of time).

Frequency: 	Daily

Requirements:	The user account executing the script must have read and write permissions in the affected Active Directory Organizational Units (OU).
		The user account must also have permission to run as a batch job enabled on the local machine and have read/write permissions in file paths specified in the script.
		The script was developed with powershell 5.1. It has not been tested with previous versions of powershell.

Scope:		Users in the as described $OUFilter variable set in the Declarations section of this script will be affected.

Instructions:	To run this script outside of the usual execution time, right click the .ps1 file and select run with powershell or click run when when this script's scheduled task is highlighted in the task schedular.


Notes:

On the 50th and 55th day of inactivity, users will be emailed warning them of the account being disabled.
On the 60th day of inactivity, the user account will be disabled. The IT team must be contacted to re-enable the account. An email notifying the user of this action is also sent.

On the 80th day of inactivity, users will be emailed again warning them of account retirement.
On the 90th day on inactivity, the user account will be retired. A IT support ticket must be completed to remedy this. An email notifying the user of this action is also sent.

Email addresses are retrieved from Active Directory, because of this if an account has an incorrect or blank email address associated with it the ownwer of the account owner will not be warned.
A member of the OT team should be Bcc'd on every warning email sent to a SCADA user.

Full time user accounts will not be retired, only disabled.

When a user account is disabled or retired, its details are appended to a csv file (DisabledUsers.csv or RetiredUsers.csv) for reporting purposes.
Before they are appended, AD is re-queried to ensure the action has been completed.

The paths for these csv's are defined in the declarations section of the ADAccountManagement.ps1.


=============================================================================== ADWeeklyReport.ps1 ===============================================================================
Purpose : 	To report on the actions of ADAccountManagement.ps1 (above).

Frequency: 	Weekly

Requirements:	The user account executing the script must have read permissions in the affected Active Directory Organizational Units (OU).
		The user account must also have permission to run as a batch job enabled on the local machine and have read/write permissions in file paths specified in the script.
		The script was developed with powershell 5.1. It has not been tested with previous versions of powershell.

Scope:		Users in the as described $OUFilter variable set in the Declarations section of this script will be affected.

Instructions:	To run this script outside of the usual execution time, right click the .ps1 file and select run with powershell or click run when when this script's scheduled task is highlighted in the task schedular.


Notes:

This script will read the .csv's exported by ADAccountManagement.ps1 and also compile a list of accounts that will be disabled or retired in the future (over the following 7 days after script execution).

An email with the .csv's attached and the .csv's contents in the body will be sent to the IT team.
If the csv's have not been created (no users being disabled/retired), no email will be sent.

Csv's include:
	DisabledUsers_<date>.csv
	RetiredUsers_<date>.csv
	ToBeDisabledUsers_<date>.csv
	ToBeRetiredUsers_<date>.csv
	
Each .csv will be archived when this script runs. This is for quarterly review.
