#FOR PS5. Install at PS5 $PROFILE which is usually C:\Users\<username>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1



# Skip the profile menu in non-interactive sessions.
if ([Environment]::UserInteractive -and
    [Environment]::GetCommandLineArgs() -notcontains '-NonInteractive') {

	Write-Host ""
	Write-Host "[+] Profile          : Default profile" -ForegroundColor Blue
	Write-Host "[+] Loading file     : $(Split-Path -Path $PSCommandPath -Leaf)" -ForegroundColor Blue
	Write-Host "[+] Full path        : $($PSCommandPath)" -ForegroundColor Blue
	Write-Host ""



	# ============================================================
	# ⚙️   POWERSHELL ENVIRONMENT
	# ============================================================

	$ProfileLoadStart = Get-Date

	# ------------------------------------------------------------
	# 🛠️ PSReadLine
	# ------------------------------------------------------------

	# zsh style tabcomplete - Shows navigable menu of all options when hitting Tab
	$FormatEnumerationLimit = -1

	# Autocompletion for arrow keys
	Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
	Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
	Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
	Set-PSReadLineOption -BellStyle None

	# ------------------------------------------------------------
	# 📊 Helper: Text-based progress bar
	# ------------------------------------------------------------

	function Write-ProfileBar {
		param (
			[string]$Label,
			[double]$Percent,
			[int]$Width = 24,
			[ConsoleColor]$Color = [ConsoleColor]::DarkGray
		)

		$Percent = [math]::Max(0, [math]::Min(100, $Percent))
		$Filled = [int][math]::Round(($Percent / 100) * $Width)
		$Empty = $Width - $Filled
		$Bar = ('#' * $Filled) + ('-' * $Empty)

		Write-Host ('  {0,-5} ' -f $Label) -NoNewline
		Write-Host $Bar -ForegroundColor $Color -NoNewline
		Write-Host (' {0,5:N1}%' -f $Percent)
	}

	# ------------------------------------------------------------
	# 🖥️ Session information
	# ------------------------------------------------------------

	$ProfilePath = $PROFILE
	$ProfileExists = Test-Path -LiteralPath $ProfilePath
	$PowerShellVersion = $PSVersionTable.PSVersion.ToString()
	$PowerShellEdition = $PSVersionTable.PSEdition
	$PowerShellHost = $Host.Name
	$ComputerName = $env:COMPUTERNAME
	$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
	$CurrentDirectory = (Get-Location).Path
	$ExecutionPolicy = Get-ExecutionPolicy

	$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
	$IsAdministrator = $Principal.IsInRole(
		[System.Security.Principal.WindowsBuiltInRole]::Administrator
	)

	# ------------------------------------------------------------
	# 🧠 Memory statistics
	# ------------------------------------------------------------

	$OS = Get-CimInstance -ClassName Win32_OperatingSystem

	$TotalMemoryGB = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
	$FreeMemoryGB = [math]::Round($OS.FreePhysicalMemory / 1MB, 2)
	$UsedMemoryGB = [math]::Round($TotalMemoryGB - $FreeMemoryGB, 2)

	if ($TotalMemoryGB -gt 0) {
		$MemoryUsedPercent = [math]::Round(
			($UsedMemoryGB / $TotalMemoryGB) * 100, 1
		)
	} else {
		$MemoryUsedPercent = 0
	}

	if ($MemoryUsedPercent -ge 90) {
		$MemoryColor = 'Red'
		$MemoryIcon = '🔴'
	} elseif ($MemoryUsedPercent -ge 75) {
		$MemoryColor = 'Yellow'
		$MemoryIcon = '🟡'
	} else {
		$MemoryColor = 'Green'
		$MemoryIcon = '🟢'
	}

	# ------------------------------------------------------------
	# 💾 Drive statistics
	# ------------------------------------------------------------

	$Drives = @(
		Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
			Sort-Object -Property DeviceID
	)

	# ------------------------------------------------------------
	# 📄 Profile file statistics
	# ------------------------------------------------------------

	if ($ProfileExists) {
		$ProfileFileSize = '{0:N1} KB' -f (
			(Get-Item -LiteralPath $ProfilePath).Length / 1KB
		)
		$ProfileFileName = Split-Path -Path $ProfilePath -Leaf
	} else {
		$ProfileFileSize = 'Not found'
		$ProfileFileName = 'Unknown'
	}

	# ------------------------------------------------------------
	# 🎛️ Dashboard header
	# ------------------------------------------------------------

	Write-Host ''
	Write-Host '============================================================' -ForegroundColor DarkGray
	Write-Host '             ⚙️ POWERSHELL ENVIRONMENT DASHBOARD' -ForegroundColor blue
	Write-Host '============================================================' -ForegroundColor DarkGray

	# ------------------------------------------------------------
	# 📋 Session
	# ------------------------------------------------------------
	Write-Host ''
	Write-Host ''
	Write-Host '  📋 SESSION' -ForegroundColor blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	Write-Host ('  🖥️  Computer          {0}' -f $ComputerName)
	Write-Host ('  👤 User               {0}' -f $UserName)
	Write-Host ('  💠 PowerShell         {0} ({1})' -f $PowerShellVersion, $PowerShellEdition)
	Write-Host ('  🪟 Host               {0}' -f $PowerShellHost)

	if ($IsAdministrator) {
		Write-Host '  🛡️  Privileges         ADMINISTRATOR' -ForegroundColor Red
	} else {
		Write-Host '  👤 Privileges         Standard user' -ForegroundColor Gray
	}

	Write-Host ('  🔐 Execution policy   {0}' -f $ExecutionPolicy)
	Write-Host ('  📂 Working directory  {0}' -f $CurrentDirectory)

	# ------------------------------------------------------------
	# 🧠 Physical memory
	# ------------------------------------------------------------
	Write-Host ''
	Write-Host ''
	Write-Host '  🧠 MEMORY' -ForegroundColor blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	Write-Host ('  📊 Used             {0:N2} / {1:N2} GB' -f $UsedMemoryGB, $TotalMemoryGB)
	Write-ProfileBar -Label 'RAM' -Percent $MemoryUsedPercent -Color $MemoryColor
	Write-Host ('  {0} Available        {1:N2} GB' -f $MemoryIcon, $FreeMemoryGB) -ForegroundColor Gray

	# ------------------------------------------------------------
	# 💾 Drive space
	# ------------------------------------------------------------
	Write-Host ''
	Write-Host ''
	Write-Host '  💾 STORAGE' -ForegroundColor blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	foreach ($Drive in $Drives) {
		$DriveSizeGB = [math]::Round($Drive.Size / 1GB, 1)
		$DriveFreeGB = [math]::Round($Drive.FreeSpace / 1GB, 1)
		$DriveUsedGB = [math]::Round(($Drive.Size - $Drive.FreeSpace) / 1GB, 1)

		if ($Drive.Size -gt 0) {
			$DriveUsedPercent = [math]::Round(
				(($Drive.Size - $Drive.FreeSpace) / $Drive.Size) * 100, 1
			)
		} else {
			$DriveUsedPercent = 0
		}

		if ($DriveUsedPercent -ge 90) {
			$DriveColor = 'Red'
			$DriveStatus = 'CRITICAL'
			$DriveIcon = '🔴'
		} elseif ($DriveUsedPercent -ge 75) {
			$DriveColor = 'Yellow'
			$DriveStatus = 'HIGH'
			$DriveIcon = '🟡'
		} else {
			$DriveColor = 'Green'
			$DriveStatus = 'OK'
			$DriveIcon = '🟢'
		}

		Write-Host ''
		Write-Host ('  💽 {0}  {1:N1} / {2:N1} GB used' -f $Drive.DeviceID, $DriveUsedGB, $DriveSizeGB)

		Write-ProfileBar -Label 'DISK' -Percent $DriveUsedPercent -Color $DriveColor

		Write-Host ('        {0:N1} GB free  {1} {2}' -f $DriveFreeGB, $DriveIcon, $DriveStatus) -ForegroundColor $DriveColor
	}

	if ($Drives.Count -eq 0) {
		Write-Host '  ⚠️  No local fixed drives found.' -ForegroundColor DarkGray
	}

	# ------------------------------------------------------------
	# 📄 Profile
	# ------------------------------------------------------------
	<#
	Write-Host ''
	Write-Host '  📄 PROFILE' -ForegroundColor Blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	Write-Host ('  📝 File             {0}' -f (Split-Path -Path $PSCommandPath -Leaf))
	Write-Host ('  📦 Size             {0}' -f $ProfileFileSize)
	Write-Host ('  📍 Path             {0}' -f $PSCommandPath)
	Write-Host ''
	Write-Host ''
	#>
	Write-Host ""
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray
	Write-Host ""
}
	