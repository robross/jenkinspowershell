############ Configuration ############

# define a config object if it doesn't already exist
# TODO: support strict mode
# TODO: request this info as needed
if (!$JenkinsConfig)
{
    $JenkinsConfig  = @{}
    $JenkinsConfig.Server = "build"
}

############ Helper Functions ############

# downloads xml file from a url
function get-xml($url) {
    $webclient = new-object System.Net.WebClient

    # set creds if we have them
    if ($JenkinsConfig.Credential)
    {
        $userName = $JenkinsConfig.Credential.GetNetworkCredential().UserName
        $password = $JenkinsConfig.Credential.GetNetworkCredential().Password
        $webclient.Credentials = new-object System.Net.NetworkCredential($userName, $password)
    }
    
    # download the xml
    $result = $webclient.DownloadString($url)
    if ($result) { [xml]$result } else { $null }
}

# uploads xml file from a url
function post-xml([string]$url, $data) {
    # create the post request
    $request = [System.Net.WebRequest]::Create($url)
    $request.Method = "POST"
    $request.ContentType = "text/xml"

    # TODO: support creds

    # if we are sending data
    if ($data) {
        # encode data
        $enc = [system.Text.Encoding]::UTF8   
        $byteArray = $enc.GetBytes($data) 
        $request.ContentLength = $byteArray.Length

        # stream data
        $dataStream = $request.GetRequestStream()
        $dataStream.Write($byteArray, 0, $byteArray.Length)
        $dataStream.Close()
    }
    
    # get the response
    $request.GetResponse()
}

# TODO: read this from file
function get-buildConfig {
    [xml]@"
<?xml version='1.0' encoding='UTF-8'?>
<project>
<actions/>
<description>This is the first test build.</description>
<keepDependencies>false</keepDependencies>
<properties/>
<scm class="hudson.scm.NullSCM"/>
<canRoam>true</canRoam>
<disabled>false</disabled>
<blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
<blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
<triggers class="vector"/>
<concurrentBuild>false</concurrentBuild>
<builders/>
<publishers/>
<buildWrappers/>
</project>
"@
}

############ Public Functions ############
<#
    .Synopsis
        Gets a job, by name, from the Jenkins CI server. Specifying -ListAvailable will get all jobs.
#>
function Get-BuildJob {
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)][string]$name,
        [switch]$ListAvailable
    )

    process {
        if ($ListAvailable) {
            $url = "http://" + $JenkinsConfig.Server + "/api/xml"
            (get-xml($url)).hudson.job
        }
        else {
            # make sure name is specified
            if($Name -eq $null -or $Name.Length -eq 0){
                throw "Name must be specified."
            }

            $url = "http://" + $JenkinsConfig.Server + "/job/$Name/api/xml"
            (get-xml $url).freeStyleProject
        }
    }
}

<#
    .Synopsis
        Starts a job, by name, from the Jenkins CI server.
#>          
function Start-BuildJob {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)][string]$name
    )

    process {
        $url = "http://" + $JenkinsConfig.Server + "/job/$name/build"
        $result = get-xml $url
    }
}

<#
    .Synopsis
        Adds a job, by name, to the Jenkins CI server.
#>          
function Add-BuildJob {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)][string]$name
    )

    process {
        $url = "http://" + $JenkinsConfig.Server + "/createItem?name=$Name"
        [xml]$config = get-buildConfig

        # modify config as appropriate
        $config.project.description = "generated build for $Name"

        $result = post-xml $url $config.InnerXml
    }
}

<#
    .Synopsis
        Ensures that every workspace/branch at the given path has a build job.
        Cleans up job for repos that no longer exists.
        Uses a prefix to correlate workspaces and job names.
#>          
function Sync-BuildJobs {
    process {
        param(
            [string]$prefix,
            [string]$repoPath
        )
        
        # get jobs that start with prefix
        write-host "Getting existing jobs"
        $existingJobs = Get-BuildJob -ListAvailable | where {$_.name.StartsWith($prefix)} | foreach {$_.Name}

        # get folders at repoPath
        write-host "Getting repositories"
        $repositories = ls $repoPath | where {$_.mode -match "d"} | foreach {$prefix + $_.Name}

        # remove any job not backed by a repo
        write-host "Removing deleted jobs"
        foreach ($job in $existingJobs) {  
            write-host "Checking if $job was deleted"
            if(!($repositories -contains $job)) {
                write-host "Removing $job"
                Remove-BuildJob $job
            }
        }
        
        # add a job for any repo that doesn't have one
        write-host "Adding new jobs"
        foreach ($repo in $repositories) {  
            write-host "Checking if $repo exists"
            if(!($existingJobs -contains $repo)) {
                write-host "Adding $repo"
                Add-BuildJob $repo
            }
        }
    }
}

<#
    .Synopsis
        Removes a job, by name, from the Jenkins CI server.
#>          
function Remove-BuildJob {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)][string]$name
    )

    process {
        $url = "http://" + $JenkinsConfig.Server + "/job/$Name/doDelete"
        $result = post-xml $url
    }
}

<#
    .Synopsis
        Duplicates a job, by name, from the Jenkins CI server.
#>          
function Copy-BuildJob {
    param(
        [Parameter(Mandatory=$true)]$sourceJobName,
        [Parameter(Mandatory=$true)]$newJobName
    )

    $url = "http://" + $JenkinsConfig.Server + "/createItem?name=" + $newJobName + "&mode=copy&from=" + $sourceJobName
    $result = post-xml $url
}

<#
    .Synopsis
        Restarts the Jenkins CI server.
        TO FIX: Something throws when after the server restarts.
#>          
function Restart-BuildService {
    $url = "http://" + $JenkinsConfig.Server + "/restart"
    post-xml $url
}

<#
    .Synopsis
        Gets the build queue, from the Jenkins CI server
        TODO: figure out what info we get after we have builds that can be queued
#>          
function Get-BuildQueue {
    $url = "http://" + $JenkinsConfig.Server + "/queue/api/xml"
    (get-xml($url))
}

############ Export ############
export-modulemember -alias * -function *-BuildJob, *-BuildJobs, *-BuildQueue -variable JenkinsConfig
