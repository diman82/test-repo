﻿<#
        .SYNOPSIS
        Script that extracts <UPLOADED> links from a URL list.

        .DESCRIPTION
        Parses a text file containing URL list, extracts <UPLOADED> links and exports them to a text file.
        Script execuion is ASYNCHRONOUS.

        .PARAMETER URLFile
        Mandatory param of the file containing URLS to parse.

        .PARAMETER Share
        Optional switch param of the download site host.

       .PARAMETER outFile
        Optional param of an output file, default value is: 'uploaded2.txt'.
        
       .PARAMETER outExceptionsFile
        Optional param of an output file containing exceptions, default value is: 'web_exceptions.txt'.

        .PARAMETER maxConcurrentJobs
        Optional param of the concurent jobs to be run, default value is the number of logical processors on the running machine.

        .EXAMPLE
        PS> .\DL-UploadedLinks.ps1 -URLFile urls.txt -Share Uploaded
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0, HelpMessage='Enter the input filename for processing urls.')]
    [Alias('urls','file')]
    [string]$URLFile,

    [ValidateNotNullOrEmpty()]
    [ValidateSet('Uploaded','Nitroflarе','mega.co.nz')]
    [parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1, HelpMessage='Choose the download Share site.')]
    [string]$Share = 'Uploaded',

    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2, HelpMessage='Enter the output filename for resulting urls for download.')]
    [string]$outFile = 'uploaded.txt',

    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$false, ValueFromPipeline=$false)]
    [string]$outExceptionsFile = 'web_exceptions.txt',

    [ValidateNotNullOrEmpty()]
    [parameter(Mandatory=$false, ValueFromPipeline=$false)]
    [ValidateRange(4,64)]
    [int]$maxConcurrentJobs = (Get-WmiObject -class Win32_processor).NumberOfLogicalProcessors
)

switch ($Share) {
Uploaded { 
    $matchstr = '(http://uploaded\.net/file/.*?|http://ul\.to/.*?)</a><br\s+'
    break
}
Nitroflarе {
    $matchstr = '(http://nitroflarе.com/.*?)</a><br\s+'
    break
 }
mega.co.nz {
    $matchstr = '(https://mega.co.nz/.*?)</a><br\s+'
    break
 }
default {
 throw "No matching Share found for `$Share: $Share"
 }
}

$urls = get-content $URLFile
$scriptDir = Get-Location
$outCol = @()
$webExepCol = @()
Write-Verbose "Matching string is: `n$matchstr`n`n"
Write-Verbose "Maximum concurent threads is: $maxConcurrentJobs"
$StopWatch = [system.diagnostics.stopwatch]::StartNew()  #Start the stopwatch to measure runtime of parallel loop

workflow WebRequestsInParallel{
    Param($maxConcurrentJobs, $urls, $outCol, $webExepCol, $matchstr)      #pass parameters to workflow, otherwise won't work

    Write-Debug "Inside workflow"

    function Get-Links($Uri, $matchstr){
         <#
      .SYNOPSIS
      Process an URI and output links 
      .DESCRIPTION
      Run a Web-Request on the given URI and output an array of Links matching the provided Regex pattern
      .PARAMETER Uri
      The URI to process.
      .PARAMETER matchstr
      The regex pattern to match the links on the HTML.
      .EXAMPLE
      Get-Links $Uri $matchstr
      #>

       #Run Web-Request & catch the error details, if exception raised
        try {
            $pagecontent = Invoke-WebRequest -Uri $Uri -UseBasicParsing
        }

        catch [System.Net.WebException] {
            $errorcode = $_.Exception.Response.StatusCode.Value__
            #$_ | fl * -Force
            $webExepCol += $uri,"The remote server returned an error: $errorcode" ,$id
            Write-Error -Message "The remote server returned an error for URI: $Uri`n, Error code: $errorcode`n" -Category ConnectionError
            $Host.UI.WriteErrorLine("The remote server returned an error for URI: $Uri`n, Error code: $errorcode`n")
        }
		
        $innerHTML = $pagecontent.Content
        #Get a list of Share host urls ONLY and add them to a global output list
        $ulLinks = ([regex]::matches($innerHTML, $matchstr) | %{$_.value})

        Write-Verbose "Extracted the following links: $ulLinks`n"
        return $ulLinks
    }

    # The urls are processed in parallel.
    ForEach -Parallel -ThrottleLimit $maxConcurrentJobs ($uri in $urls)
    {
        Write-Debug "Processing URL: $uri`n"
        # The commands run sequentially with each fetched URI. 
        $outCol += Get-Links $Uri $matchstr
    }
    return $outCol, $webExepCol
}

$results = WebRequestsInParallel $maxConcurrentJobs $urls $outCol $webExepCol $matchstr
$StopWatch.Stop()

#Output all content to a file
$results | out-file $scriptDir\$outFile -append

#Output all web exceptions to a file
$webExepCol | out-file $scriptDir\$outExceptionsFile -append

Write-Verbose $StopWatch.Elapsed.TotalSeconds