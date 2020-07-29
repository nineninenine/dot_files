#install in $profile which should be "C:\Users\<username>\Documents\WindowsPowerShell\"
#https://devblogs.microsoft.com/scripting/understanding-the-six-powershell-profiles/

#disable truncated output https://mcsaguru.com/how-to-fix-truncated-powershell-output/
$FormatEnumerationLimit=-1

#bash style tab complete
Set-PSReadlineKeyHandler -Key Tab -Function Complete

#disable horrible bell sound to keep my ears from bleeding ;)
Set-PSReadlineOption -BellStyle None
