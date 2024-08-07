# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.

foreach($file in Get-ChildItem -Path "$PSScriptRoot\Modules" -Filter *.psm1){
    Import-Module $file.fullname
}

Import-module DattoRMM
Import-Module HaloAPI

# Import Az and AzTable modules
Import-Module Az
Import-Module Az.Accounts
Import-Module Az.Storage
Import-Module AzTable

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
