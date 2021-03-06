﻿<#
        .DESCRIPTION
            Gets metrics from XIO arrays, and sends them to Graphite.
            This is done with API calls to the array's unisphere instance
        .PARAMETER arrayName
            The name of the XIO array. If fqdn is not supplied, the script will append it, based on the Domain setting in the xml.
        .PARAMETER logPath
            The full path to the log file for the script. If not determined, it will default to c:\it\logs\xiometrics_graphite.log
        .EXAMPLE
           .\xiometrics_graphite.ps1 -arrayName xioarray01 -logPath c:\it\logs\xiometrics_graphite.log
        .Author
            jpeacock@
            Created 10/03/16

        .Requires
            Graphite-PowerShell-Functions module https://github.com/MattHodge/Graphite-PowerShell-Functions     
            PoshRSJob module https://github.com/proxb/PoshRSJob
#>
   param
    (
        [CmdletBinding()]
        [parameter(Mandatory = $true)]
        [string]$arrayName,
        [parameter(Mandatory = $false)]
        [string]$logPath = "c:\it\logs\xiometrics_graphite.log"
        )

Function Write-Log
{
    <#	
	.Description  
		Writes a new line to the end of the specified log file
    
	.EXAMPLE
        Write-Log -LogPath "C:\Windows\Temp\Test_Script.log" -LineValue "This is a new line which I am appending to the end of the log file."
    #>
 
    [CmdletBinding()]
    Param (
	[Parameter(Mandatory=$true)]
	[string]$LogPath, 
	[Parameter(Mandatory=$true)]
	[string]$LineValue,
	[Parameter(Mandatory=$false)]
	[switch]$TimeStamp	
	)
	
    Process
		{
			$parentLogPath = Split-Path -Parent $LogPath
			if (!(Test-Path $parentLogPath))
			{
				New-Item -ItemType directory -Path $parentLogPath
			}
			$time = get-date -Uformat "%D %T"	
		
		
				if ($timestamp -eq $True)
				{
					Add-Content -Path $LogPath -Value "$time`: $LineValue"
				}
				else
				{
	     		   Add-Content -Path $LogPath -Value "$LineValue"
				}
	        #Write to screen for debug mode
	        Write-Debug $LineValue
	    }
}

function Send-v2_BulkGraphiteMetrics
{
<#
    .Synopsis
        Sends several Graphite Metrics to a Carbon server with one request. Bulk requests save a lot of resources for Graphite server.
        Modified from Send-BulkGraphiteMetrics function to permit sending bulk metrics from an array, without a separate Unix time requirement.
        This mod was required to permit sending past timestamps, as collected through the NAR file, as opposed to current time stamp used by the default function.
    .Description
        This function takes an array with a metric path, value, and timestamp, and sends them to a Graphite server.
    .Parameter CarbonServer
        The Carbon server IP or address.
    .Parameter CarbonServerPort
        The Carbon server port. Default is 2003.
    .Parameter Metrics
        Array containing the following: MetricPath, MetricValue, Timestamp
    .Parameter UnixTime
        The the unix time stamp of the metrics being sent the Graphite Server. 
        No longer required/Do not use; this will most likely break if used. UnixTime variable should be in the Metrics array.
    .Parameter DateTime
        The DateTime object of the metrics being sent the Graphite Server. This does a direct conversion to Unix time without accounting for Time Zones. If your PC time zone does not match your Graphite servers time zone the metric will appear on the incorrect time.
        No longer required/Do not use; this will most likely break if used. Time is gathered from the NAR.
    .Example
        Send-v2_BulkGraphiteMetrics -CarbonServer myserver.local -CarbonServerPort 2003 -Metrics $perfObjs
        This sends all metrics in the $perfObjs array to the specified carbon server.
    .Notes
        NAME:      Send-BulkGraphiteMetrics
        AUTHOR:    Alexey Kirpichnikov
        Modified:  Jeff Peacock 

#>
    param
    (
        [CmdletBinding(DefaultParametersetName = 'Date Object')]
        [parameter(Mandatory = $true)]
        [string]$CarbonServer,
        [parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$CarbonServerPort = 2003,
        [parameter(Mandatory = $true)]
        [array]$Metrics,
        [Parameter(Mandatory = $false,
                   ParameterSetName = 'Epoch / Unix Time')]
        [ValidateRange(1, 99999999999999)]
        [string]$UnixTime,
        [Parameter(Mandatory = $true,
                   ParameterSetName = 'Date Object')]
        [datetime]$DateTime,
        # Will Display what will be sent to Graphite but not actually send it
        [Parameter(Mandatory = $false)]
        [switch]$TestMode,
        # Sends the metrics over UDP instead of TCP
        [Parameter(Mandatory = $false)]
        [switch]$UDP
    )

    # If Received A DateTime Object - Convert To UnixTime
    if ($DateTime)
    {
        $utcDate = $DateTime.ToUniversalTime()
        
        # Convert to a Unix time without any rounding
        [uint64]$UnixTime = [double]::Parse((Get-Date -Date $utcDate -UFormat %s))
    }

    # Create Send-To-Graphite Metric
    [string[]]$metricStrings = @()
    foreach ($key in $Metrics)
    {
        $metricStrings += $key.metricpath + " " + $key.metricvalue + " " + $key.timestamp

        Write-host ("Metric Received: " + $metricStrings[-1])
    }

    $sendMetricsParams = @{
        "CarbonServer" = $CarbonServer
        "CarbonServerPort" = $CarbonServerPort
        "Metrics" = $metricStrings
        "IsUdp" = $UDP
        "TestMode" = $TestMode
    }

    SendMetrics @sendMetricsParams
}

Function Import-XMLConfig
{
<#
    .Synopsis
        Loads the XML Config File for Send-StatsToGraphite.
    .Description
        Loads the XML Config File for Send-StatsToGraphite.
    .Parameter ConfigPath
        Full path to the configuration XML file.
    .Example
        Import-XMLConfig -ConfigPath C:\Stats\Send-PowerShellGraphite.ps1
    .Notes
        NAME:      Convert-TimeZone
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au
#>
    [CmdletBinding()]
    Param
    (
        # Configuration File Path
        [Parameter(Mandatory = $true)]
        $ConfigPath
    )

    [hashtable]$Config = @{ }

    # Load Configuration File
    $xmlfile = [xml]([System.IO.File]::ReadAllText($configPath))
    # Set the Graphite carbon server location and port number
    $Config.CarbonServer = $xmlfile.Configuration.Graphite.CarbonServer
    $Config.CarbonServerPort = $xmlfile.Configuration.Graphite.CarbonServerPort
    # Get the HostName to use for the metrics from the config file
    $Config.NodeHostName = $xmlfile.Configuration.Graphite.NodeHostName   
    # Set the NodeHostName to ComputerName
    if($Config.NodeHostName -eq '$env:COMPUTERNAME')
    {
        $Config.NodeHostName = $env:COMPUTERNAME
    }
   
    # Get Metric Send Interval From Config
    [int]$Config.MetricSendIntervalSeconds = $xmlfile.Configuration.Graphite.MetricSendIntervalSeconds
    # Convert Value in Configuration File to Bool for Sending via UDP
    [bool]$Config.SendUsingUDP = [System.Convert]::ToBoolean($xmlfile.Configuration.Graphite.SendUsingUDP)
    # Convert Interval into TimeSpan
    $Config.MetricTimeSpan = [timespan]::FromSeconds($Config.MetricSendIntervalSeconds)
    # What is the metric path
    $Config.MetricPath = $xmlfile.Configuration.Graphite.MetricPath
    # Convert Value in Configuration File to Bool for showing Verbose Output
    [bool]$Config.ShowOutput = [System.Convert]::ToBoolean($xmlfile.Configuration.Logging.VerboseOutput)
    # Create the Performance Counters Array
    $Config.Counters = @()
    # Load each row from the configuration file into the counter array
    foreach ($counter in $xmlfile.Configuration.PerformanceCounters.Counter)
    {
        $Config.Counters += $counter.Name
    }

    # Create the Metric Cleanup Hashtable
    $Config.MetricReplace = New-Object System.Collections.Specialized.OrderedDictionary
    # Load metric cleanup config
    ForEach ($metricreplace in $xmlfile.Configuration.MetricCleaning.MetricReplace)
    {
        # Load each MetricReplace into an array
        $Config.MetricReplace.Add($metricreplace.This,$metricreplace.With)
    }

    $Config.Filters = [string]::Empty;
    # Load each row from the configuration file into the counter array
    foreach ($MetricFilter in $xmlfile.Configuration.Filtering.MetricFilter)
    {
        $Config.Filters += $MetricFilter.Name + '|'
    }

    if($Config.Filters.Length -gt 0) {
        # Trim trailing and leading white spaces
        $Config.Filters = $Config.Filters.Trim()
        # Strip the Last Pipe From the filters string so regex can work against the string.
        $Config.Filters = $Config.Filters.TrimEnd("|")
    }
    else
    {
        $Config.Filters = $null
    }

    # Doesn't throw errors if users decide to delete the SQL section from the XML file. Issue #32.
    try
    {
        # Below is for SQL Metrics
        $Config.MSSQLMetricPath = $xmlfile.Configuration.MSSQLMetics.MetricPath
        [int]$Config.MSSQLMetricSendIntervalSeconds = $xmlfile.Configuration.MSSQLMetics.MetricSendIntervalSeconds
        $Config.MSSQLMetricTimeSpan = [timespan]::FromSeconds($Config.MSSQLMetricSendIntervalSeconds)
        [int]$Config.MSSQLConnectTimeout = $xmlfile.Configuration.MSSQLMetics.SQLConnectionTimeoutSeconds
        [int]$Config.MSSQLQueryTimeout = $xmlfile.Configuration.MSSQLMetics.SQLQueryTimeoutSeconds

        # Create the Performance Counters Array
        $Config.MSSQLServers = @()     
     
        foreach ($sqlServer in $xmlfile.Configuration.MSSQLMetics)
        {
            # Load each SQL Server into an array
            $Config.MSSQLServers += [pscustomobject]@{
                ServerInstance = $sqlServer.ServerInstance;
                Username = $sqlServer.Username;
                Password = $sqlServer.Password;
                Queries = $sqlServer.Query
            }
        }
    }
    catch
    {
        Write-Verbose "SQL configuration has been left out, skipping."
    }

    Return $Config
}

function PSUsing
{
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )

    Try
    {
        &$scriptBlock
    }
    Finally
    {
        if ($inputObject -ne $null)
        {
            if ($inputObject.psbase -eq $null)
            {
                $inputObject.Dispose()
            }
            else
            {
                $inputObject.psbase.Dispose()
            }
        }
    }
}

function SendMetrics
{
    param (
        [string]$CarbonServer,
        [int]$CarbonServerPort,
        [string[]]$Metrics,
        [switch]$IsUdp = $false,
        [switch]$TestMode = $false
    )

    if (!($TestMode))
    {
        try
        {
            if ($isUdp)
            {
                PSUsing ($udpobject = new-Object system.Net.Sockets.Udpclient($CarbonServer, $CarbonServerPort)) -ScriptBlock {
                    $enc = new-object system.text.asciiencoding
                    foreach ($metricString in $Metrics)
                    {
                        $Message += "$($metricString)`n"
                    }
                    $byte = $enc.GetBytes($Message)

                    Write-Verbose "Byte Length: $($byte.Length)"
                    $Sent = $udpobject.Send($byte,$byte.Length)
                }

                Write-Verbose "Sent via UDP to $($CarbonServer) on port $($CarbonServerPort)."
            }
            else
            {
                PSUsing ($socket = New-Object System.Net.Sockets.TCPClient) -ScriptBlock {
                    $socket.connect($CarbonServer, $CarbonServerPort)
                    PSUsing ($stream = $socket.GetStream()) {
                        PSUSing($writer = new-object System.IO.StreamWriter($stream)) {
                            foreach ($metricString in $Metrics)
                            {
                                $writer.WriteLine($metricString)
                            }
                            $writer.Flush()
                            Write-Verbose "Sent via TCP to $($CarbonServer) on port $($CarbonServerPort)."
                        }
                    }
                }
            }
        }
        catch
        {
            $exceptionText = GetPrettyProblem $_
            Write-Error "Error sending metrics to the Graphite Server. Please check your configuration file. `n$exceptionText"
        }
    }
}

function GetPrettyProblem {
    param (
        $Problem
    )

    $prettyString = (Out-String -InputObject (format-list -inputobject $Problem -Property * -force)).Trim()
    return $prettyString
}

Write-Log -LogPath $logPath -LineValue "Beginning metrics script for $arrayName" -TimeStamp
#Get settings from xml file
[xml]$settingsFile = get-content ".\xiometrics.xml"
$gServer = $settingsFile.Configuration.Graphite.CarbonServer
$gPort = $settingsFile.Configuration.Graphite.CarbonServerPort
$mRoot = $settingsFile.Configuration.Graphite.MetricRoot
$validScopes = @()
$validScopes = ($settingsfile.Configuration.Monitor.Scope | ?{$_.Enabled -eq "True"}).Type
$retainCsv = ($settingsfile.Configuration.Debug.Retain).metricCSV
#configure auth
$user = $settingsFile.Configuration.Array.User
$pass = $settingsFile.Configuration.Array.Pass
$pair = "${user}:${pass}"
#Encode the string to the RFC2045-MIME variant of Base64, except not limited to 76 char/line.
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
#Create the Auth value as the method, a space, and then the encoded pair Method Base64String
$basicAuthValue = "Basic $base64"
#Create the header Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==
$headers = @{ Authorization = $basicAuthValue }
#Disable SSL Verification
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

#add the fqdn if array name does not already contain it. This is needed for api url calls.
$domain = $settingsFile.Configuration.Array.Domain
if ($arrayName -notmatch "$domain"){
$arrayName = $arrayName + "." + $domain
}

#create the base url for querying the api
$baseUrl = "https://" + $arrayName + "/api/json/types/"
#Create an object to convert time stamps to Unix Time, required for graphite metrics
$unixEpochStart = new-object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
$polltime = Get-Date
$uTime = [uint64]([datetime]$pollTime.ToUniversalTime() - $unixEpochStart).TotalSeconds
$clusterurl = $baseUrl + "clusters"
$clusters = Invoke-RestMethod $clusterurl -headers $headers -Method Get
$clustername = $clusters.clusters.name

#check if Volumes(LUNs) are enabled in the xml file, if so, process them.
if ($validScopes -contains "volumes"){
    $scopename = "volumes"
    #get the selected metric types for volumes from the xml file
    $validMetricTypes = @()
    $validMetricTypes = (($settingsfile.Configuration.Monitor.Scope | ?{$_.Type -eq $scopename}).Metric | ?{$_.Enabled -eq "True"}).Name
    #build the api url
    $queryType = $scopename
    $url = "$baseurl$querytype" + "?full=1"
    #jobname is used for multithreaded runspaces
    $jobName = "$arrayName" + "_" + "$querytype"
    $result = Invoke-RestMethod $url -headers $headers -Method Get
    #only get LUNs that are mapped to something.
    $volumes = $result.'volumes' | ? {$_.'lun-mapping-list' -ne ""}
    $vcount = $volumes.Count
    $lunobjs = @()
    $starttime = Get-Date -Format hh:mm:ss
    Write-Log -LogPath $logPath -LineValue "Beginning query of LUN metrics for $vcount LUNs..." -TimeStamp
        #start multithread operation, with a new thread for each volume in the list. 
        $volumes | Start-RSJob -Name $jobname -Throttle 7 -ScriptBlock {
                $DebugPreference = 'Continue'
                $PSBoundParameters.GetEnumerator() | ForEach {
                Write-Debug $_
                }
                #Get host/initiator group info for the LUN
                $igs = @()
                $iglist = @()
                $igs = $_.'lun-mapping-list'
                #parse data to list the actual IGs
                foreach ($ig in $igs){
                                $initgroup = $ig[0][1]
                                $iglist += $initgroup
                            }
                #Get static/non-metric info for each LUN: ID, GUID, Name, Size, InitiatorGroups
                $lunName = $_.'name'
                $lunSizeGB = ($_.'vol-size' / 1024 / 1024)
                $lunGuid = $_.'guid'
                $lunID = $_.'index'
                        #create graphite metric for lun size
                            $mName = $lunName + "." + "SizeGB"
                            $mPath = $using:mRoot + $using:clusterName + "." + $using:scopeName + "." + $mName
                            $mValue = $lunSizeGB
                            $metricobj = New-Object psobject -Property ([Ordered]@{MetricPath=$mpath; MetricValue=$mvalue; Timestamp=$using:utime})
                            $metricobj
                        #create graphite metric for UID
                            $mName = $lunName + "." + "GUID." + $lunGuid
                            $mPath = $using:mRoot + $using:clusterName + "." + $using:scopeName + "." + $mName
                            #set an arbitratry value, as graphite needs a datapoint
                            $mValue = [int]1
                            $metricobj = New-Object psobject -Property ([Ordered]@{MetricPath=$mpath; MetricValue=$mvalue; Timestamp=$using:utime})
                            $metricobj
                        #create graphite metric for each IG mapped to the LUN
                        foreach ($ig in $iglist){
                            $mName = $lunName + "." + "IGs." + $ig
                            $mPath = $using:mRoot + $using:clusterName + "." + $using:scopeName + "." + $mName
                            #set an arbitratry value, as graphite needs a datapoint
                            $mValue = [int]1
                            $metricobj = New-Object psobject -Property ([Ordered]@{MetricPath=$mpath; MetricValue=$mvalue; Timestamp=$using:utime})
                            $metricobj
                        }
                        #get actual LUN metrics selected in the xml
                        foreach ($metric in $using:validMetricTypes){
                            #create the graphite metric
                            $metricvalue = $_.$metric
                            $mName = $lunName + "." + $metric
                            $mPath = $using:mRoot + $using:clusterName + "." + $using:scopeName + "." + $mName
                            $mValue = $metricValue
                            #create the obj with necessary properties. Output the obj so it can be collected from the runspace threads.
                            $metricobj = New-Object psobject -Property ([Ordered]@{MetricPath=$mpath; MetricValue=$mvalue; Timestamp=$using:utime})
                            $metricobj
                        }             
        }

        #create a wait timer to ensure all threads are complete before gathering data
        do {
        $runningcount = (Get-RSjob -name $jobName | ? {$_.state-eq "Running"}).count
        Write-Host "$runningcount threads remaining"
        Start-Sleep -Seconds 3
        } until ($runningcount -eq 0)
        Write-Host "All threads complete"
        #process the runspace threads, retrieve the data.
        $rsObjs = @()
        $rsObjs = Get-RSJob -Name $jobName | Receive-RSJob
        $totalobjs = $rsobjs.count
        Write-Host "$totalobjs LUN metrics processed for $vcount LUNs with host mappings"
        Get-RSJob -Name $jobName | Remove-RSJob
        $endtime = Get-Date -Format hh:mm:ss
        Write-Host "Start time: $starttime"
        Write-Host "End Time: $endtime"
        Write-Log -LogPath $logPath -LineValue "Query of LUN metrics complete." -TimeStamp

}

#Get the cluster metrics if selected. We do not multithread, as there is no need for the additional overhead.
if ($validScopes -contains "clusters"){
 Write-Log -LogPath $logPath -LineValue "Collecting Cluster Metrics" -TimeStamp
    $scopename = "clusters"
    $metricobjs = @()
    #get the selected metric types for volumes from the xml file
    $validMetricTypes = @()
    $validMetricTypes = (($settingsfile.Configuration.Monitor.Scope | ?{$_.Type -eq $scopename}).Metric | ?{$_.Enabled -eq "True"}).Name
    #build the api url
    $queryType = $scopename
    $url = "$baseurl$querytype" + "/?name=" + "$clustername"
    #jobname is used for multithreaded runspaces
    $jobName = "$arrayName" + "_" + "$querytype"
    #query the API for the cluster data
    $result = (Invoke-RestMethod $url -headers $headers -Method Get).content
                foreach ($metric in $validMetricTypes){
                #create the graphite metric
                $metricvalue = $result.$metric
                $mName = $metric
                $mPath = $mRoot + $clusterName + "." + $mName
                $mValue = $metricValue
                #create the obj with necessary properties. Output the obj so it can be collected from the runspace threads.
                $metricobj = New-Object psobject -Property ([Ordered]@{MetricPath=$mpath; MetricValue=$mvalue; Timestamp=$utime})
                $metricobjs += $metricobj
                }
Write-Log -LogPath $logPath -LineValue "Finished collecting Cluster Metrics" -TimeStamp
}

Write-Log -LogPath $logPath -LineValue "Beginning send of Performance Payload to Graphite" -TimeStamp
Send-v2_BulkGraphiteMetrics -CarbonServer $gServer -CarbonServerPort 2003 -Metrics $rsObjs
if ($validScopes -contains "clusters"){
    Send-v2_BulkGraphiteMetrics -CarbonServer $gServer -CarbonServerPort 2003 -Metrics $metricObjs
}
Write-Log -LogPath $logPath -LineValue "Sending metrics complete" -TimeStamp

#create CSVs if selected in XML.
if ($retainCsv -eq "True"){
	$metricsfile = ".\xioMetrics_" + $clustername + "_" + (get-date -f MM-dd-yyyy_HH_mm_ss) + ".csv"  
	$rsObjs | Export-Csv -verbose $metricsfile
    if ($validScopes -contains "clusters"){
    $metricobjs | Export-Csv -Verbose $metricsfile -Append
    }
}
Write-Host 'Script Complete'

#End Script
