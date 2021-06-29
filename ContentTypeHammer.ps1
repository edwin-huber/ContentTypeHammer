##########################################################
#  Script to set content type for a specific file extension recursively in Azure Files
#  This script is not restart tollerant, and will start from the begining again
#  To process folders in a restartable manner, we would need to externalise the queue
#  Memory usage will be dependent on the depth and content (number of files in folders)
##########################################################
#  DISCLAIMER: This is not an official PowerShell Script.
#  Use and modify at your own risk.
#  This code-sample is provided "AS IT IS" without warranty of any kind, either expressed or implied, including but not limited to the implied warranties of merchantability and/or fitness for a particular purpose.
#  This sample is not supported under any Microsoft standard support program or service.. 
#  Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. 
#  The entire risk arising out of the use or performance of the sample and documentation remains with you. 
#  In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of  the use of or inability to use the sample or documentation, even if Microsoft has been advised of the possibility of such damages.
##########################################################

param(
    $subscriptionId,
    $resourceGroupName,
    $storageAccountName,
    $shareName,
    $subscriptionName = "<Subscription Name Here>",
    $pathToMimeTypes = '/etc/mime.types' # needs adjusting on a Windows host to include drive
    )

# or # $ContentType = "application/pdf" # needed to be able to open PDF, other file types, other content types!
# see also /etc/mime.types
###########################################################
#  Globals
###########################################################
$global:mimeTypes = @{}
$useMimeTypes = $true

###########################################################
#  Functions
###########################################################

# ##############
# Logs message to host, modify if you need file based logging
# ##############
function Log {
    param($message)
    Write-Output $message
}

# ##############
# Loads the mime typoes from the default location on an Azure Linux VM / Cloud shell
# ##############
function loadMimeTypes {
    param($pathToMimeTypes)
    #  try open /etc/mime.types
    $mimeFile = Get-Content -Path $pathToMimeTypes
    if ($null -ne $mimeFile) {
        foreach ($line in $mimeFile) {
            if ($line.IndexOf('#') -ne 0 -and $line.IndexOf(' ') -ne 0) {
                # write-Output $line
                $def = $line | Select-String -Pattern "^(\w+\W\w+)"
                $exts = $line | Select-String -Pattern "(\s+.+)"
                if ($exts.Matches.Length -gt 0) {
                    foreach ($ext in $exts.Matches.Groups) {
                        # adds extension and contentType to our table
                        $extsToInsert = $ext.Value.Trim().Split(" ")
                        if ($extsToInsert.Length -gt 0) {
                            foreach ($extToInsert in $extsToInsert) {
                                if ($extToInsert.Length -gt 0 -and $false -eq $global:mimeTypes.ContainsKey($extToInsert)) {
                                    $global:mimeTypes.Add( $extToInsert, $def.Matches[0].Value)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

# ##############
# Connects to Azure Resources
# ##############
function ConnectToAzureAndStorageAccount {
    Connect-AzAccount
    Select-AzSubscription -SubscriptionId $subscriptionId -Name $subscriptionName -Force
    # set-azcontext -Subscription $subscriptionName
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    return $storageAccount
}

# ##############
# Processes All Files in an Azure File Share directory
# Assumption is that type != "AzureStorageFileDirectory"
# ##############
function ProcessFiles {
    param(
        $files
    ) 
    # need to validate case there is only 1 file
    if ($null -ne $files) {
        foreach ($file in $files) {
    
            $file.CloudFile.FetchAttributes()
            $fileExtensionMatches = $file.CloudFile.Name | Select-String -Pattern "\w+$"
            if ($null -ne $fileExtensionMatches.Matches -and 0 -ne $fileExtensionMatches.Matches.Length ) {
                $fileExtension = $fileExtensionMatches.Matches[0].Groups[0].Value

                if ($global:mimeTypes.ContainsKey($fileExtension)) {
                    $message = $file.CloudFile.Name
                    $message += " : "
                    $message += $file.CloudFile.Properties.ContentType
                    Log $message
                    # set correct contentType if needed
                    if ($file.CloudFile.Properties.ContentType -ne $global:mimeTypes[$fileExtension]) {
                        $message = "Correcting to "
                        $message += $global:mimeTypes[$fileExtension].ToString()
                        $file.CloudFile.Properties.ContentType = $global:mimeTypes[$fileExtension]
                        $file.CloudFile.SetProperties() 
                    }
                } 
            }
        }
    }
}

# ##############
# Processes All Files in an Azure File Share directory
# Assumption type == "AzureStorageFileDirectory"
# ##############
function ProcessFolders {
    param(
        $folders,
        $storageAccount,
        $shareName
    ) 
    # need to validate case there is only 1 folder
    if ($null -ne $folders) {
        foreach ($folder in $folders) {
            $message = "processing files in "
            $message += $folder.CloudFileDirectory.Name
            Log $message
            # Process files
            $files = Get-AzStorageFile -Directory $folder.CloudFileDirectory | Where-Object { $_.GetType().Name -ne "AzureStorageFileDirectory" }
            if ($null -ne $files) {
                ProcessFiles $files
            }
            # Process folders
            $message =  "processing folders in "
            $message += $folder.CloudFileDirectory.Name
            Log $message
            $subFolders = Get-AzStorageFile -Directory $folder.CloudFileDirectory | Where-Object { $_.GetType().Name -eq "AzureStorageFileDirectory" }
            ProcessFolders $subFolders $storageAccount $shareName
        }
    }
}

# Theoretically we could iterate through all storage accounts and file shares and files...
# $storageAccounts = Get-AzResource -ResourceType 'Microsoft.Storage/storageAccounts'
# however, we are working in a more targetted mode for now

# again, theoretically we could iterate all shares in the account
# $fileshares = Get-AzStorageShare -Context $sa.Context
Clear-Host
if ($true -eq $useMimeTypes) {
    loadMimeTypes $pathToMimeTypes
}
# Uncomment this if you want to see the mime types that we have found
# foreach ($type in $global:mimeTypes.Keys) {
#     Log $type
# }

$storageAccount = ConnectToAzureAndStorageAccount
$topLevelFiles = Get-AzStorageFile -Context $storageAccount[2].Context -ShareName $shareName | Where-Object { $_.GetType().Name -ne "AzureStorageFileDirectory" }
Log "Processing Top Level Files"
ProcessFiles $topLevelFiles
$topLevelFolders = Get-AzStorageFile -Context $storageAccount[2].Context -ShareName $shareName | Where-Object { $_.GetType().Name -eq "AzureStorageFileDirectory" }
Log "Processing Top Level Folders"
ProcessFolders $topLevelFolders $storageAccount[2] $shareName

Log "DONE"

