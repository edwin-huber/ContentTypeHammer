# ContentTypeHammer
Corrects Content Type on Azure Files objects in Azure Files, which have somehow been corrupted or set incorrectly.

## Use at your own risk

### Args:

    $subscriptionId,
    $resourceGroupName,
    $storageAccountName,
    $shareName,
    $subscriptionName = "<Subscription Name Here>",
    $pathToMimeTypes = '/etc/mime.types' # needs adjusting on a Windows host to include drive
