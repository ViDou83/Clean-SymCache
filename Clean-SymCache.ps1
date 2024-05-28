[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $true, ParameterSetName = "Symbol local store")]
    [string]$SymCache = "C:\Symbols",
    [Switch]$force,
    [Switch]$cleanTmpFiles,
    [timespan]$cleanByAge,
    [Switch]$discover
)

### Global variables
[bool]$global:confirm = !$force
[System.Collections.ArrayList]$global:fileToDelete = New-Object System.Collections.ArrayList
[UInt64]$global:TotalBytes = 0
[string]$global:moduleRegex = ".pdb$|.exe$|.sys$|.dll$|.symcache$"

#region functions
function GetSizeInHumanReadable([UInt64]$size) {
    [string]$output = ""
    switch ($size) {
        { $_ -gt 1TB } { $output = ($size / 1TB).ToString("n2") + " TB"; break }
        { $_ -gt 1GB } { $output = ($size / 1GB).ToString("n2") + " GB"; break }
        { $_ -gt 1MB } { $output = ($size / 1MB).ToString("n2") + " MB"; break }
        { $_ -gt 1KB } { $output = ($size / 1KB).ToString("n2") + " KB"; break }
        default { "$size B" }
    }
    return $output
}

function CleanTempFiles() {
    [string]$tmpFileRegex = "download*.error"
    [hashtable]$symbolToTmpFiles = @{}
    [System.Collections.ArrayList]$TmpFilesList = New-Object System.Collections.ArrayList
    [UInt64]$fileRestored = 0

    Write-Host "+  Step 1 - Finding all tmp files from symbols store path:$SymCache" -ForegroundColor DarkBlue

    $TmpFilesList += Get-ChildItem -Recurse $SymCache -File -Filter $tmpFileRegex
    foreach ($fileInfo in $TmpFilesList) {
        [string]$fileName = $fileInfo.FullName
        Write-Verbose "Found tmp file $fileName size:$(GetSizeInHumanReadable($fileInfo.Length)) bytes"
        $global:TotalBytes += $fileInfo.Length
    }

    if ($TmpFilesList.Count -eq 0) {
        Write-Host "No tmp files found in symbols store path:$SymCache"
        return
    }

    [string]$bytesFormatted = GetSizeInHumanReadable($global:TotalBytes)
    Write-Host "Found $($TmpFilesList.Count) tmp files in symbols store path:$SymCache with a total size of $bytesFormatted" -ForegroundColor DarkGreen

    Write-Host "+   Step 2 - Building symbols map from tmp files list discovered" -ForegroundColor DarkBlue

    foreach ($fileInfo in $TmpFilesList) {
        [string]$tmpFile = $fileInfo.FullName
        [string]$folder = $fileInfo.DirectoryName

        [string]$potentialSymbolName = $tmpFile.Split("\") | ForEach-Object { if ( $_ -Match $global:moduleRegex) { $_ } }
        if (!$potentialSymbolName) {
            Write-Verbose "No potential symbol file found for $tmpFile"
            if (!$discover) {
                $global:fileToDelete += $fileInfo 
            }
            continue
        }

        Write-Verbose "Symbol:$potentialSymbolName adding $folder to the list"

        if (!$symbolToTmpFiles[$potentialSymbolName]) {
            $symbolToTmpFiles[$potentialSymbolName] = New-Object System.Collections.ArrayList;
        }

        if ($symbolToTmpFiles[$potentialSymbolName].Contains($folder)) {
            continue
        }

        $symbolToTmpFiles[$potentialSymbolName].Add($folder) | Out-Null;
    }

    # bail out if we are just in discovery mode 
    if ($discover) {
        #Write-Host " End of discovery mode - $($symbolToTmpFiles.Count) potential symbols retrieved with a total size of $bytesFormatted used"
        return;
    }

    Write-Host "+   Step 3 - Recovering symbols " -ForegroundColor DarkBlue

    foreach ($symbol in $symbolToTmpFiles.Keys) {

        Write-Host "$symbol - $($symbolToTmpFiles[$symbol].Count) version found in cache" -ForegroundColor DarkGreen

        foreach ($folder in $symbolToTmpFiles[$symbol]) {
            [string]$target = $($folder + '\' + $symbol)
            
            Write-Verbose "Checking if $target is already located in $folder"

            if (Test-Path -Path $target) {
                Write-Verbose "Symbol $symbol is already located in $folder. Use -cleanTmpFiles to remove tmp files"
                if (!$discover) {
                    $global:fileToDelete += Get-ChildItem -Path $($folder + '\' + $tmpFileRegex) -File -Filter $tmpFileRegex
                }
                continue
            }
            
            Write-Verbose "Getting the bigger temp file in $folder"
            
            [System.Collections.ArrayList]$tmpFiles = New-Object System.Collections.ArrayList

            $tmpFiles += Get-ChildItem -Path $($folder + '\' + $tmpFileRegex) -File  -Filter $tmpFileRegex #| Sort-Object -Property Length -Descending

            [System.IO.FileInfo]$bigger = $tmpFiles[0]
        
            if (!$bigger) {
                Write-Verbose "Unexpected no tmp files found in $folder but were present before..."
                continue
            }
            
            if ($cleanTmpFiles) {
                Write-Verbose "Renaming $bigger to $target "
                Move-Item $bigger $target -Confirm:$global:confirm -Verbose:$VerbosePreference
                Write-Verbose "$bigger renamed to $target" 
                # remove all other tmp files from that folded
                if ($tmpFiles.Count -gt 1) {
                    #remove bigger from the list
                    $tmpFiles.Remove(0)
                    foreach ($tmpFile in $tmpFiles) {
                        Write-Verbose "Adding $tmpFile to the delete list"
                        $global:fileToDelete += $tmpFile
                    }
                }
            }
            else {
                Write-Verbose "Copying $bigger to $target " 
                Copy-Item $bigger $target -Confirm:$global:confirm -Verbose:$VerbosePreference
                Write-Verbose "$bigger to $target copied!"
            }

            $fileRestored++
            Write-Host "Restored $symbol from $bigger to $target"
            $global:TotalBytes -= $bigger.Length

            if ($cleanTmpFiles) {
                Get-ChildItem -Path $($folder + '\' + $tmpFileRegex) | Remove-Item -Confirm:$force
            }
        }
    }

    $bytesFormatted = GetSizeInHumanReadable($global:TotalBytes)

    if (!$cleanTmpFiles) {
        Write-Host "There is $bytesFormatted wasted disk space by tmp files - rerun this script with -cleanTmpFiles switch to free it!" -ForegroundColor Yellow
    }

    Write-Host "Total files restored:$fileRestored from the symbol cache:$SymCache" -ForegroundColor DarkGreen
}

function getOlderFiles()
{
    [System.Collections.ArrayList]$OldestFiles = New-Object System.Collections.ArrayList
    
    Write-Host "+   Step 1 - getting all files with LastAccessTime older than $($cleanByAge.Days) from symbol cache: $SymCache" -ForegroundColor DarkBlue
    $OldestFiles += Get-ChildItem -Path $SymCache -Recurse -File | Where-Object { $_.FullName -match $global:moduleRegex -and $_.LastAccessTime -lt (Get-Date).AddDays(-$cleanByAge.Days) }

    if($VerbosePreference -eq "Continue")
    {
        Write-Verbose "Found $($OldestFiles.Count) files older than $($cleanByAge.Days) days in the symbol cache: $SymCache"
        $OldestFiles | Format-Table FullName,Length,LastAccessTime -Verbose:$VerbosePreference
    }
    Write-Host "Found $($OldestFiles.Count) files older than $($cleanByAge.Days) days in the symbol cache: $SymCache"
    
    Write-Host "+   Step 2 - compute the size all files with LastAccessTime older than $($cleanByAge.Days) from symbol cache: $SymCache" -ForegroundColor DarkBlue
    [UInt64]$TotalBytes = 0
    foreach ($file in $OldestFiles) {
        $TotalBytes += $(Get-Item $file.FullName).Length
    }
    Write-Host "Found $($OldestFiles.Count) files older than $($cleanByAge.Days) days in the symbol cache: $SymCache - total size:$(GetSizeInHumanReadable($TotalBytes))"
    $global:TotalBytes += $TotalBytes

    Write-Host "+   Step 3 - Adding the files to the list of files to delete" -ForegroundColor DarkBlue

    $global:fileToDelete +=  $OldestFiles 
}

function cleaningFiles()
{
    if ($global:fileToDelete.Count -eq 0) {
        Write-Host "No files to delete"
        return
    }

    foreach ($file in $global:fileToDelete) {
        Write-Host $file
        [UInt64]$_length = $(Get-Item $file.FullName).Length
        Write-Verbose "Removing $($file.Name) size:$_length)"
        Remove-Item -Path $file.FullName -Confirm:$global:confirm -Verbose:$VerbosePreference
    }

    $bytesFormatted = GetSizeInHumanReadable($global:TotalBytes)
    
    Write-Host "Total files deleted:$($global:fileToDelete.Count) from the symbol cache:$SymCache - freed space $bytesFormatted" -ForegroundColor DarkGreen
}
#endregion

#region Main
if (! (Test-Path -Path $SymCache)) {
    Write-Host "Symbol cache path does not exist"
    exit
}

if ($cleanTmpFiles) {
    Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
    Write-Host " Cleaning up tmp files from the symbol cache : $SymCache" -ForegroundColor DarkMagenta
    Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
    CleanTempFiles
}

if ($cleanByAge)
{
    Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
    Write-Host " Cleaning up files older than TimeSpan $cleanByAge from the symbol cache : $SymCache" -ForegroundColor DarkMagenta
    Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
    getOlderFiles
}

if(!$discover)
{
    if ($cleanTmpFiles -or $cleanByAge) {
        Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
        Write-Host " Cleaning up remaining tmp files count from the symbol cache " -ForegroundColor DarkMagenta
        Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor DarkMagenta
        cleaningFiles
    }
}
else {
    Write-Host "Potential $($Global:fileToDelete.Count) files to delete in symbolsCache:$SymCache totalSize:$(GetSizeInHumanReadable($global:TotalBytes))" 
}

Write-Host "-------------------" -ForegroundColor DarkMagenta
Write-Host " End of execution " -ForegroundColor DarkMagenta
Write-Host "-------------------" -ForegroundColor DarkMagenta
    
#endregion