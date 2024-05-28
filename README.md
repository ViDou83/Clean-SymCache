# Purpose 
Clean-SymCache.ps1 is a PS script to clean up wasted disk space by symbol cached but never used and to restore temporary files Windows DBG (WinDBGx) failed to rename.  

# Parameters 
-SymCache       : The local symbols cache path 
-cleanTmpFiles  : Switch parameter (no argument) to delete temporary files Windows DBG (WinDBGx) failed to rename. Additionally that script will try to recover the missing symbol files.
-cleanByAge     : Switch parameter (no argument) to delete cached files that are older than a specified date (argument should be in TimeSpan)
-discover       : Combine with -cleanTmpFiles or -cleanByAge (can be combined) will only files and space w/o deleting them
-Verbose        : prints out additional logging
-Force          : Don't prompt to confirm files deletion
