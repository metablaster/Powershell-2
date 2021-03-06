# © 2017 Soverance Studios
# Scott McCutchen
# soverance.com
# scott.mccutchen@soverance.com
#
# This script creates a report of the Windows product key and activation status for all computers in the specified Active Directory domain.

# You can limit this script to a specified organizational unit by specifying the -OU parameter.

# You must specify the type of report you wish to run when executing this script, otherwise it will do nothing.

# ACTIVATION REPORT  (-ActivationReport)
# Run the activation report by executing the script with the -ActivationReport parameter
# The Activation Report will return License Activation Status and other various information
# It will also report on Office 365 activations installed on the queried machines

# PRODUCT KEY REPORT  (-KeyReport)
# Run the Product Key report by executing the script with the -KeyReport parameter
# The Product Key Report will return the decrypted Windows license key stored in the operating system for each scanned computer.
# When running this report, you must specify the appropriate SKU parameter in order to return the correct product key for those systems.
#    * -ServerSKU, if you wish to return correct product keys for Server type operating systems, such as Windows Server 2016.
#    * -ClientSKU, if you wish to return correct product keys for Client type operating systems, such as Windows 10.
# There is a known "bug" or limitation in this report:
#    * Scanning the entire domain without specifying an OU will report on all machines and usually results in a "dirty" report, where some keys are correct and others are not.
#    * The accuracy of the product key returned depends on whether or not you have specified the type of SKU you wish to scan for
#    * For example, targeting the entire domain and specifying -ServerSKU will cause the report to show correct information for Server systems, but show Client SKU entries with incorrect license keys
#    * Conversely, targeting the entire domain and specifying -ClientSKU will cause the report to show correct information for Client systems, but show Server SKU entries with incorrect license keys
# TO AVOID INCORRECT REPORTING CAUSED BY THIS LIMITATION,
# YOU SHOULD CONSIDER ONLY RUNNING THE PRODUCT KEY REPORT AT A TARGETED ORGANIZATIONAL UNIT WHICH CONTAINS ONLY THE SKU TYPES YOU WISH TO SCAN

##############################################
###
###  Parameters
###
##############################################

param (
    [string]$Domain = $(throw "-Domain : A valid Active Directory domain name must be specified."),
    [string]$OU,  # -OU : You may limit this function to a specified organizational unit by providing the full distinguished name of the OU.
    [switch]$ActivationReport,  # Run and export the Activation Report
    [switch]$KeyReport,  # Run and export the Product Key Report.  If you run the Product Key Report, you must specify the SKU type you wish to return.
    [switch]$ServerSKU,  # -ServerSKU : Specify this switch if you are running a Product Key Report and wish to check for Windows Server SKUs.
    [switch]$ClientSKU   # -ClientSKU : Specify this switch if you are running a Product Key Report and wish to scan for Client SKUs, such as Windows 10.
)

##############################################
###
###  Functions
###
##############################################

# Since the Windows Product Key is encrypted once stored in the operating system, it is difficult to retrieve.
# This function decrypts and returns the stored product key, stored at HKLM:\Software\Microsoft\Windows NT\CurrentVersion\DigitalProductId  
function Get-WindowsKey($computers) 
{
    try 
    {
        $ResultsArray = @()  # an empty array to store our results for exporting
        $hklm = 2147483650
        $regPath = "Software\Microsoft\Windows NT\CurrentVersion"

        if ($ServerSKU)
        {
            $regValue = "DigitalProductId4"  # scan for Server SKUs, such as Windows Server 2016 / 2019
        }
        if ($ClientSKU)
        {
            $regValue = "DigitalProductId"  # scan for Client SKUs, such as Windows 7 / 10
        }        
            
        foreach ($computer in $computers) 
        {
            if ($computer)
            {
                # make sure connection works before processing this function
                if (Test-Connection -ComputerName $computer -BufferSize 16 -Count 1 -Quiet) 
                {
                    # Because the Windows Product Key is encrypted once it's stored in the operating system, we must decrypt it manually to make it useable.
                    $productKey = $null
                    $win32os = $null
                    $wmi = [WMIClass]"\\$computer\root\default:stdRegProv"
                    $data = $wmi.GetBinaryValue($hklm,$regPath,$regValue)
                    $binArray = ($data.uValue)[52..66]
                    $charsArray = "B","C","D","F","G","H","J","K","M","P","Q","R","T","V","W","X","Y","2","3","4","6","7","8","9"
                    
                    ## decrypt base24 encoded binary data into characters
                    For ($i = 24; $i -ge 0; $i--) 
                    {
                        $k = 0
                        For ($j = 14; $j -ge 0; $j--) 
                        {
                            $k = $k * 256 -bxor $binArray[$j]
                            $binArray[$j] = [math]::truncate($k / 24)
                            $k = $k % 24
                        }
                        
                        $productKey = $charsArray[$k] + $productKey
                        
                        If (($i % 5 -eq 0) -and ($i -ne 0)) 
                        {
                            $productKey = "-" + $productKey
                        }
                    }
                    
                    # print out the key and some related system values
                    $win32os = Get-WmiObject Win32_OperatingSystem -computer $computer
                    $obj = New-Object Object
                    $obj | Add-Member Noteproperty Computer -value $computer
                    $obj | Add-Member Noteproperty Caption -value $win32os.Caption
                    $obj | Add-Member Noteproperty CSDVersion -value $win32os.CSDVersion
                    $obj | Add-Member Noteproperty OSArch -value $win32os.OSArchitecture
                    $obj | Add-Member Noteproperty BuildNumber -value $win32os.BuildNumber
                    $obj | Add-Member Noteproperty RegisteredTo -value $win32os.RegisteredUser
                    $obj | Add-Member Noteproperty ProductID -value $win32os.SerialNumber
                    $obj | Add-Member Noteproperty ProductKey -value $productkey
                    $obj 
                    $ResultsArray += $obj  # add to results array                    
                }
                else 
                {
                    Write-Host "The computer" $($computer) "is currently unavailable, it will be omitted from the report."
                }
            }
            else
            {
                Write-Host "ERROR : No computer specified, it will be omitted from the report.  This error is usually returned because the computer object in AD did not have a DNSHostName attribute.  This is common for programmatic computer accounts, such as the Azure AD Single Sign On Account."   
            }
        }

        # Export the license key report to CSV
        $exportpath = $PSScriptRoot
        $ExportPathWithFileName = $exportpath + "\LicenseReporting_Keys_" + $($Domain) + "_" + (Get-Date -format yyyy-MM-dd-HH-mm-ss) + ".csv"
        $ResultsArray | Export-Csv -Path $ExportPathWithFileName -NoClobber -NoTypeInformation
    }
    catch 
    {
        Write-Host "ERROR : " $($_.Exception.Message)
    }    
}

# This function will return the current Windows license activation status.
function Get-ActivationStatus($computers)
{
    $ResultsArray = @()  # an empty array to store our results for exporting    
    $CimSessionOptions = New-CimSessionOption -Protocol "Dcom"  # configure cim session protocol as dcom
    $Query = "Select * from  SoftwareLicensingProduct Where PartialProductKey LIKE '%'"  # wmi query for activation status

    foreach ($computer in $computers) 
    {
        try 
        {
            if ($computer)
            {
                # make sure connection works before processing this function
                if (Test-Connection -ComputerName $computer -BufferSize 16 -Count 1 -Quiet) 
                {
                    # create CIM session
                    $Cimsession = New-CimSession -Name $computer -ComputerName $computer -SessionOption $CimSessionOptions -Credential $creds -ErrorAction Stop
                    
                    # use CIM session to get windows activation status
                    $LicenseInfo = Get-CimInstance -Query $Query -CimSession $Cimsession -ErrorAction Stop 

                    Switch ($LicenseInfo.LicenseStatus) 
                    {
                        0 {$LicenseStatus = 'Unlicensed'; Break}
                        1 {$LicenseStatus = 'Licensed'; Break}
                        2 {$LicenseStatus = 'OOBGrace'; Break}
                        3 {$LicenseStatus = 'OOTGrace'; Break}
                        4 {$LicenseStatus = 'NonGenuineGrace'; Break}
                        5 {$LicenseStatus = 'Notification'; Break}
                        6 {$LicenseStatus = 'ExtendedGrace'; Break}
                    } 

                    # collect the license info
                    $LicenseInfo | Select-Object PSComputerName, Name, @{N = 'LicenseStatus'; E={$LicenseStatus}},AutomaticVMActivationLastActivationTime, Description, GenuineStatus, GracePeriodRemaining, LicenseFamily, PartialProductKey, RemainingSkuReArmCount, IsKeyManagementServiceMachine #, ApplicationID
                    $ResultsArray += $LicenseInfo                  
                }
                else 
                {
                    Write-Host "The computer" $($computer) "is currently unavailable, it will be omitted from the report."
                }
            }
            else
            {
                Write-Host "ERROR : No computer specified, it will be omitted from the report.  This error is usually returned because the computer object in AD did not have a DNSHostName attribute.  This is common for programmatic computer accounts, such as the Azure AD Single Sign On Account."   
            }
            
        }
        catch 
        {
            Write-Host "ERROR : " $($_.Exception.Message)
        }
    }

    # Export the license key report to CSV
    $exportpath = $PSScriptRoot
    $ExportPathWithFileName = $exportpath + "\LicenseReporting_Activation_" + $($Domain) + "_" + (Get-Date -format yyyy-MM-dd-HH-mm-ss) + ".csv"
    $ResultsArray | Export-Csv -Path $ExportPathWithFileName -NoClobber -NoTypeInformation
    Write-Host "Windows Activation Report successfully exported."
}

##############################################
###
###  Start Script 
###
##############################################

$creds = Get-Credential # supply domain admin creds via GUI at each run

try 
{
    if ($OU)
    {
        Write-Host "Searching Organizational Unit " $($OU) 
        # recursively get all the computers in the specified OU
        # if you want to get only the computers in the specified OU (not recursive), then modify this to use the -SearchScope parameter
        # you can use -SearchScope to specify the depth of your search; "-SearchScope 1" will search just one OU.  "-SearchScope 2" will search two OU's, a parent and child.  
        $computers = Get-ADComputer -Server $domain -Credential $creds -Filter * -SearchBase $OU -Properties *
    }
    else 
    {
        Write-Host "Searching Active Directory Domain " $($domain)
        $computers = Get-ADComputer -Server $domain -Credential $creds -Filter * -Properties *  # get all the computer objects in the specified domain
    }

    $hostNameList = @()  # create an empty array for storing FQDNs

    foreach ($computer in $computers)
    {
        $hostNameList += $computer.DNSHostName   # add fqdn hostnames to the list      
    }

    # Run the License Key Report
    if ($KeyReport)
    {
        Get-WindowsKey($hostNameList)
    }
    
    # Run the System Activation Report
    if ($ActivationReport)
    {
        Get-ActivationStatus($hostNameList)
    }    
}
catch 
{
    Write-Host "ERROR : " $($_.Exception.Message)
}

