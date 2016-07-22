# Scott McCutchen
# soverance.com
# Creates a new Azure Resource Manager VM from a pre-existing VHD storage disk

# Initial Configuration
$location = "eastus"
$resourceGroup = "MyResource"
$storageName =  Get-AzureRmStorageAccount -AccountName "MyStorage" -ResourceGroupName "MyResource"
$virtualNetwork = Get-AzureRmVirtualNetwork -Name "MyNetwork" -ResourceGroupName "MyResource"
Write-Host "Initial configuration complete."

# create a new Public IP resource
Write-Host "Creating new Public IP..."
$ipName = "MyIPName"
$publicIP = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Static
# Use the line below if you have already created a Public IP
#$publicIP = Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $resourceGroup
Write-Host "A new Public IP resource was created in" $resourceGroup 

# create a new Network Interface
Write-Host "Creating new Network Interface..."
$netInterfaceName = "MyNetInterface"
$netInterface = New-AzureRmNetworkInterface -Name $netInterfaceName -ResourceGroupName $resourceGroup -Location $location -SubnetID $virtualNetwork.Subnets[0].Id -PublicIpAddressId $pip.Id
# Use the line below if you already have a Network Interface
#$netInterface = Get-AzureRmNetworkInterface -Name $netInterfaceName -ResourceGroupName $resourceGroup
Write-Host "A new Network Interface resource was created in" $resourceGroup 

# Set Local Admin Credentials
$cred = Get-Credential -Message "Type the user name and password of the local administrator account."

# Initial VM Configuration
$vmName = "MyVM"
$vmSize = "Standard_A1"
$vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
Write-Host "Virtual Machine provisioned as" $vmSize 

# Operating System Config
# Unused here, but you'd use this if you were creating a new VHD instead of an existing VHD
#$vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
#Write-Host "OS configured as " $vmName "."

# Add network interface to VM
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $netInterface.Id
Write-Host "Network Interface" $netInterfaceName "has been applied to the VM."

# Set Disk Configuration
$osDiskName = "WebDisk"
Write-Host "A new OS disk blob was configured."

# set URL of old VHD
$urlVHD = "https://storage.blob.core.windows.net/ExistingDisk.vhd"
Write-Host "Source VHD set to " $urlVHD

# Add OS Disk to VM
$vm = Set-AzureRmVMOSDisk -VM $vm -Name $osDiskName -VhdUri $urlVHD -CreateOption attach -Windows -Caching 'ReadWrite'
Write-Host "OS Disk added to VM."

$result = New-AzureRmVM -ResourceGroupName $resourceGroup -Location $location -VM $vm
$result
