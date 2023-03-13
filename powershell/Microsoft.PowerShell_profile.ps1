#install in $profile which should be "C:\Users\<username>\Documents\WindowsPowerShell\"
#https://devblogs.microsoft.com/scripting/understanding-the-six-powershell-profiles/

#disable truncated output https://mcsaguru.com/how-to-fix-truncated-powershell-output/
$FormatEnumerationLimit=-1

# zsh style tabcomplete - Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete


# Autocompletion for arrow keys
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

#disable horrible bell sound to keep my ears from bleeding ;)
Set-PSReadlineOption -BellStyle None





