# Purpose 
Clean-SymCache.ps1 is a PS script to clean up wasted disk space by symbol cached but never used and to restore temporary files Windows DBG (WinDBGx) failed to rename.  

# Parameters 
Clean-SymCache.ps1 -SymCache <string> [-force] [-cleanTmpFiles] [-cleanByAge <timespan>] [-discover] [<CommonParameters>] 

  
-SymCache       : The local symbols cache path  
-cleanTmpFiles  : Switch parameter (no argument) to delete temporary files Windows DBG (WinDBGx) failed to rename. Additionally that script will try to recover the missing symbol files.  
-cleanByAge     : Switch parameter (no argument) to delete cached files that are older than a specified date (argument should be in TimeSpan)  
-discover       : Combine with -cleanTmpFiles or -cleanByAge (can be combined) will only files and space w/o deleting them  
-Verbose        : prints out additional logging  
-Force          : Don't prompt to confirm files deletion  

# Examples
* Will list all temporary files and files with LastAccessTime older than 120 days (about 4 month)
````
  .\Clean-SymCache.ps1 -SymCache D:\symbols\Sym\ -cleanTmpFiles -cleanByAge $(New-TimeSpan -Days 120) -discover
````

* Will delete all temporary files while trying to recover missing symbols w/o prompting for deletion confirmation:
````
.\Clean-SymCache.ps1 -SymCache D:\symbols\Sym\  -cleanTmpFiles -force
````

* Will delete both all temporary files while trying to recover missing symbols w/o and symbols files older than 120 days prompting for deletion confirmation:
````
.\Clean-SymCache.ps1 -SymCache D:\symbols\Sym\  -cleanTmpFiles -cleanByAge $(New-TimeSpan -Days 120) -force
````
