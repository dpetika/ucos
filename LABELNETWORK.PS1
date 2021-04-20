param(               
    [Parameter(Mandatory = $false)][String]$UserName,
    [Parameter(Mandatory = $false)][String]$PassWord,
    [Parameter(Mandatory = $false)][String]$PEIPAddress
    
)
[string]$PETCPPort = "9440"
[boolean]$VerboseFlag = $true
#
# Write Log Entries to file and to Console.
#    
function Write-Logs {
    param (
        [Parameter(mandatory = $true)]$LogEntry,
        [Parameter(mandatory = $false)]$V,
        [switch]$Err
    )
    $Caller = (Get-PSCallStack | Select-Object FunctionName -Skip 1 -First 1).FunctionName
    $TimeStamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $LogMessage = $TimeStamp + " | " + $Caller + "|" + $LogEntry
    If ($Err) { $LogMessage += " (ERROR)" }
    Add-Content $LogFile $LogMessage
    if ($V -and !($Err)) { $host.ui.WriteLine($LogEntry) }
    if ($Err) { $host.ui.WriteErrorLine($LogEntry) } 
}

$TimeStamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
$LogFile = "C:\" + $TimeStamp + "_LabelNetworkLog.txt"
Write-Logs -LogEntry "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
$LogEntry = "Script Started. " 
Write-Logs -LogEntry $LogEntry -V $true 

#
# Over-ride default Certificate Policy and ignore invalid TLS cert.
#
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


# Get the UUID of this system, it is also the VMUUid within Cluster.
$BootStrapUuid = Get-WmiObject Win32_ComputerSystemProduct | Select-Object -ExpandProperty UUID
$BootStrapUuid = $BootStrapUuid.Trim()

#
# Validate If the user provided the Username and Password as parameters, if not prompt for them
#


if ( ! $PSBoundParameters.ContainsKey('UserName') -or ! $PSBoundParameters.ContainsKey('Password') ) {
    $PrismCredentials = $host.ui.PromptForCredential("", `
            "Please enter the user name and password for the Nutanix cluster.", "", "")
    if ($PrismCredentials.UserName) {
        $UserName = $PrismCredentials.UserName
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PrismCredentials.Password)
        $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    else {
        Write-Logs -LogEntry "Exiting Script. No username provided."  -V $VerboseFlag -Err  
        exit 1
    }
}

$RestCredentials = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($UserName + ":" + $PassWord))
$ClusterUuid = ''

$TcpClient = New-Object Net.Sockets.TcpClient

do { 
    If ($PEIPAddress) {
        $MSG = "Attempting to connect to Prism Element at " + $PEIPAddress
        Write-Logs -LogEntry $MSG -V $VerboseFlag
        try { $TcpClient.Connect($PEIPAddress, $PETCPPort) }
        catch { }
        if ($TcpClient.Connected) {
            #
            # Close Socket to Prism Central.
            #
            $TcpClient.Close()
            $TcpClient.Dispose()
            $MSG = "Connected to port TCP/" + $PETCPPort + " on Prism Central."
            Write-Logs -LogEntry $MSG -V $VerboseFlag
            $Header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $Header.add("Authorization", $RestCredentials)
            $Header.add("Accept", "application/json")
            $ContentType = "application/json"
            $Method = "GET"
            $URI = "https://${PEIPAddress}:${PETCPPort}/api/nutanix/v2.0/cluster/"
            try {
                $Objs = Invoke-Restmethod -method $method `
                    -Uri $URI `
                    -Headers $Header `
                    -ContentType $contenttype
            }
            catch {
                $Result = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($Result)
                $ResponseBody = $Reader.ReadToEnd();
                $ErrMsg = "StatusCode:" + $_.Exception.Response.StatusCode.value__ + `
                    " | StatusDescription:" + $_.Exception.Response.StatusDescription + `
                    " | " + $ResponseBody
                Write-Logs -LogEntry $ErrMsg  -V $VerboseFlag -Err
                exit 1                  
            } 
            #
            # Connected, exit do.
            #
            Write-Logs -LogEntry "Credentials verified for Prism Central." -V $VerboseFlag
            break
        }
        else {
            $MsgStr = "Unable to connect to port " + $PETCPPort + " on IP Address :" + $IPAddress
            Write-Logs -LogEntry $MsgStr  -V $VerboseFlag -Err
        }
    }
    #
    # 
    #
    :IPValidate do {
        # Prompt user for IP address of PRISM.
        try {
            $temp = Read-host "Enter the IP address of Prism Central"
            if ($temp.length -eq 0) {
                Write-Logs -LogEntry "Exiting Script. User Aborted."  -V $VerboseFlag -Err
                Exit
            }
            else {
                [ipaddress] $PEIPAddress = [ipaddress] $temp
                break IPValidate
            }
        }
        catch {
            $host.ui.WriteErrorLine("Please enter the IP Address of Prism Element.")              
        }
    } while ($true) # Prompt user for IP address of Prism Element.
    $PEIPAddress = $PEIPAddress.ToString()
} while ($true) # Connect to Prism Element on TCP Port.


#
# Get NICs for this VM
#
$Header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$Header.add("Authorization", $RestCredentials)
$Header.add("Accept", "application/json")
$ContentType = "application/json"
$Method = "GET"
$URI = "https://${PEIPAddress}:${PETCPPort}/PrismGateway/services/rest/v2.0/vms/${BootStrapUuid}/nics/"
try {
    $NICObjs = Invoke-Restmethod -method $method `
        -Uri $uri `
        -Headers $Header `
        -ContentType $contenttype
}
catch {
    $ErrMsg = "Unable to query VM NICs using V2 REST-API." + `
        "StatusCode:" + $_.Exception.Response.StatusCode.value__ + `
        " | StatusDescription:" + $_.Exception.Response.StatusDescription
    Write-Logs -LogEntry $ErrMsg -V $VerboseFlag -Err
    break                  
}
    



foreach ($NIC in $NICObjs.entities) {
    $into = new-object PSObject
    $MAC = $NIC.mac_address -replace(":","-") 
    $NetworkUUID = $NIC.network_uuid
    $URI = "https://${PEIPAddress}:${PETCPPort}/PrismGateway/services/rest/v2.0/networks/${NetworkUUID}"
    $NetworkObj = @()
    try {
    $NetworkObj = Invoke-Restmethod -method $method `
        -Uri $uri `
        -Headers $Header `
        -ContentType $contenttype
}
catch {
    $ErrMsg = "Unable to query Network using V2 REST-API." + `
        "StatusCode:" + $_.Exception.Response.StatusCode.value__ + `
        " | StatusDescription:" + $_.Exception.Response.StatusDescription
    Write-Logs -LogEntry $ErrMsg -V $VerboseFlag -Err
    return [string]"ERROR"                  
}
   Get-NetAdapter | Where-Object {$_.MacAddress -eq $MAC} | Rename-NetAdapter -NewName $NetworkObj.name
  
}


