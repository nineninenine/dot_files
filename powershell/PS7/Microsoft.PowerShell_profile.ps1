<# For powershell 7. 
Install Microsoft.PowerShell_profile.ps1 in PS7 $PROFILE (usually C:\Users\<username>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1).
Put the profiles folder (with default.ps1 and coreutils.ps1 inside) in C:\Users\<username>\Documents\PowerShell\

This Microsoft.PowerShell_profile.ps1 is not the same as the PS5 version. Launching PS7 loads a profile menu (via this Microsoft.PowerShell_profile.ps1). If the user selects the default profile or the time limit expires, it loads the default.ps1 profile. The user can optionally choose to load the coreutils.ps1 profile to access the linux coreutils tools.

profiles\default.ps1 is substantively the same as the PS5 version of Microsoft.PowerShell_profile.ps1. It displays a status dashboard, enables zsh style tab completion, and a few other QoL things. No powershell command aliases are changed.

profiles\coreutils.ps1 loads the coreutils linux tools. They have to be accessed this way because there's conflicts between the names of the linux tools and default powershell aliases. The default powershell aliases cannot be permanently overwritten b/c scripts may depend on the aliases to work properly. This seperate profile is intended to make the coreutils available only when needed. Coreutils requires PS 7.4 or later, hence all this bullshit only for PS7. coreutils.ps1 loads the same status dashboard the other things as default.ps1, but it temporarily overwrites the default powershell aliases and checks to make sure the linux tools are loaded instead of the powershell aliases.


#>

# Skip the profile menu in non-interactive sessions.
if ([Environment]::UserInteractive -and
    [Environment]::GetCommandLineArgs() -notcontains '-NonInteractive') {


	$ProfileDir = Join-Path (Split-Path $PROFILE) "Profiles"
	$timeoutSeconds = 8

	$profiles = @{
		"1" = @{
			Name = "Default profile"
			Path = Join-Path $ProfileDir "Default.ps1"
		}
		"2" = @{
			Name = "Coreutils profile"
			Path = Join-Path $ProfileDir "Coreutils.ps1"
		}
	}

	Write-Host ('[+] Loading profile menu from {0}' -f $PSCommandPath) -ForegroundColor Blue
	Write-Host ""
	Write-Host "Select a PowerShell profile:"
	Write-Host "  [1] Default profile (Default.ps1)"
	Write-Host "  [2] Coreutils profile (Coreutils.ps1)"
	Write-Host ""
	Write-Host "Choose 1 or 2 (default: 1 in $timeoutSeconds seconds):" -ForegroundColor Yellow

	$choice = $null
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

	while ($stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) {
		if ([Console]::KeyAvailable) {
			$key = [Console]::ReadKey($true)

			if ($profiles.ContainsKey([string]$key.KeyChar)) {
				$choice = [string]$key.KeyChar
				break
			}
		}

		$elapsed = $stopwatch.Elapsed.TotalSeconds
		$remaining = [Math]::Max(0, $timeoutSeconds - $elapsed)
		$percent = [int](($elapsed / $timeoutSeconds) * 100)

		Write-Progress `
			-Activity "PowerShell profile selection" `
			-Status ("Default profile loads in {0:N1} seconds" -f $remaining) `
			-PercentComplete $percent

		Start-Sleep -Milliseconds 100
	}

	$stopwatch.Stop()
	Write-Progress -Activity "PowerShell profile selection" -Completed

	# ------------------------------------------------------------
	# Choose default profile if the timer expires
	# ------------------------------------------------------------

	if (-not $choice) {
		$choice = "1"
		Write-Host ""
		Write-Host "[!] Timeout reached. Selecting the default profile." -ForegroundColor Red
	}

	# ------------------------------------------------------------
	# Load selected profile
	# ------------------------------------------------------------

	$selectedProfile = $profiles[$choice]
	$selectedFileName = Split-Path -Path $selectedProfile.Path -Leaf

	Write-Host ""
	Write-Host "[+] Selected profile : $($selectedProfile.Name)" -ForegroundColor Blue
	Write-Host "[+] Loading file     : $selectedFileName" -ForegroundColor Blue
	Write-Host "[+] Full path        : $($selectedProfile.Path)" -ForegroundColor Blue
	Write-Host ""

	if (Test-Path -LiteralPath $selectedProfile.Path) {
		. $selectedProfile.Path
	}
	else {
		Write-Host "[!] Profile not found: $($selectedProfile.Path)" -ForegroundColor Red
	}

} 

