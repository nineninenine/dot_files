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


	# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
	# vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	# Inlining the template into the profile shaves off ~10ms (25%).
	$script:__COREUTILS__ = [System.Collections.Generic.HashSet[string]]::new(
		[string[]]@('arch','b2sum','base32','base64','basename','basenc','cat','cksum','comm','cp','csplit','cut','date','df','dirname','du','echo','env','expr','factor','false','find','fmt','fold','grep','head','hostname','join','la','link','ln','ls','md5sum','mkdir','mktemp','mv','nl','nproc','numfmt','od','paste','pathchk','pr','printenv','printf','ptx','pwd','readlink','realpath','rm','rmdir','seq','sha1sum','sha224sum','sha256sum','sha384sum','sha512sum','shuf','sleep','sort','split','stat','sum','tac','tail','tee','test','touch','tr','true','truncate','tsort','unexpand','uniq','unlink','uptime','wc','xargs','yes'),
		[System.StringComparer]::OrdinalIgnoreCase
	)

	$script:__COREUTILS_FAST_SKIP__ = [regex]::new(
		'\b(?:' + ($script:__COREUTILS__ -join '|') + ')\b',
		[System.Text.RegularExpressions.RegexOptions]::Compiled -bor `
			[System.Text.RegularExpressions.RegexOptions]::IgnoreCase
	)

	# Casting the scriptblock to Func<Ast,bool> once and reusing it avoids the
	# per-FindAll scriptblock-to-delegate wrapping overhead (~1.7x faster).
	$script:__COREUTILS_CMD_PREDICATE__ = [System.Func[System.Management.Automation.Language.Ast, bool]] {
		param($n) $n -is [System.Management.Automation.Language.CommandAst]
	}

	$script:__COREUTILS_ARG_SPECIAL__ = [char[]] @("'", '"', '`', '$')

	# Wrap arguments into quotes. By being a function we can properly handle $variables.
	# As per MSVCRT, any `\` before `"` must be doubled to escape them.
	function global:__coreutils_q {
		param($s)
		'"' + (([string]$s) -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
	}

	# PowerShell tokenizes `*"a"*` as [BareWord] instead of the expected [DoubleQuoted, BareWord, DoubleQuoted].
	# To work around that we use... regex. Group 1 = 'single', 2 = "double", 3 = `escape, 4 = bare run.
	$script:__COREUTILS_ARG_RX__ = [regex]::new(
		"'((?:[^']|'')*)'|""((?:[^""``]|""""|``.)*)""|``(.)|([^'""``]+)",
		[System.Text.RegularExpressions.RegexOptions]::Compiled
	)
	$script:__COREUTILS_ARG_EVAL__ = [System.Text.RegularExpressions.MatchEvaluator] {
		param($m)
		if ($m.Groups[1].Success) {
			# Single-quoted: literal. PS '' -> ', then MSVCRT-quote.
			$body = $m.Groups[1].Value.Replace("''", "'")
			if ($body -match '^(.*?)(\\+)$') {
				return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
			}
			return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
		}
		if ($m.Groups[2].Success) {
			# Double-quoted: collapse PS quote-escapes to raw " / ', let ExpandString
			# resolve `n / `t / $var, then MSVCRT-quote.
			$body = $m.Groups[2].Value.
			Replace('`"', '"').
			Replace("``'", "'").
			Replace('""', '"')
			$body = $ExecutionContext.InvokeCommand.ExpandString($body)
			if ($body -match '^(.*?)(\\+)$') {
				return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
			}
			return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
		}
		if ($m.Groups[3].Success) {
			# Backtick-escaped char outside a string: " -> \"; everything else
			# becomes a one-char quoted region so glob metas stay literal.
			$c = $m.Groups[3].Value
			if ($c -eq '"') {
				return '\"'
			}
			return '"' + $c + '"'
		}
		# Bare run: passed through unquoted so coreutils can glob it; expand $vars.
		return $ExecutionContext.InvokeCommand.ExpandString($m.Groups[4].Value)
	}

	# 0: not tested, 1: coreutils not installed, 2: coreutils installed.
	$script:__COREUTILS_CMD_DIR_TEST__ = 0

	# PSConsoleHostReadLine override that rewrites coreutils command names to their
	# .cmd equivalents after PSReadLine returns (history keeps the original).
	#
	# Why .cmd over .exe: PSNativeCommandArgumentPassing = 'Windows' results in a behavior
	# where passing bare quotes to CreateProcess() is impossible. This prevents us from
	# passing "*" as "*" to coreutils and instead will be given as a bare *.
	# This causes it to treat it as a glob pattern. "*.cmd" files however are automatically
	# treated as PSNativeCommandArgumentPassing = 'Legacy', which preserves quotes.
	# It is the only possible workaround and the only way coreutils can work at all.
	function PSConsoleHostReadLine {
		[System.Diagnostics.DebuggerHidden()]
		param()

		$lastRunStatus = $?
		Microsoft.PowerShell.Core\Set-StrictMode -Off
		$line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($host.Runspace, $ExecutionContext, $lastRunStatus)

		# If the line contains no coreutils name, we don't need to parse the AST at all.
		if (-not $script:__COREUTILS_FAST_SKIP__.IsMatch($line)) {
			return $line
		}

		# Roamed/synced profiles can load this snippet on machines where coreutils is not installed.
		# Test for the existence of the command directory once and remember the result.
		if ($script:__COREUTILS_CMD_DIR_TEST__ -eq 0) {
			$script:__COREUTILS_CMD_DIR_TEST__ = 1
			if (Test-Path -LiteralPath 'C:\Program Files\coreutils\cmd\' -PathType Container -ErrorAction Ignore) {
				$script:__COREUTILS_CMD_DIR_TEST__ = 2
			}
		}
		if ($script:__COREUTILS_CMD_DIR_TEST__ -ne 2) {
			return $line
		}

		$ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$null)
		$commands = $ast.FindAll($script:__COREUTILS_CMD_PREDICATE__, $true)

		# Process right-to-left so earlier offsets stay valid after each splice.
		# In-place reverse beats Sort-Object for the typical 1-command line.
		if ($commands.Count -gt 1) {
			$commands = [System.Collections.Generic.List[object]]::new($commands)
			$commands.Reverse()
		}

		foreach ($cmd in $commands) {
			$name = $cmd.GetCommandName()
			if (!$name) {
				continue
			}

			$baseName = $name
			if ($name.EndsWith('.exe') -or $name.EndsWith('.cmd')) {
				$baseName = $name.Substring(0, $name.Length - 4)
			}
			if (!$script:__COREUTILS__.Contains($baseName)) {
				continue
			}

			# ls/la get colour + listing flags injected; la also rewrites to ls.
			$cmdElement = $cmd.CommandElements[0]
			$start = $cmdElement.Extent.StartOffset
			$end = $cmdElement.Extent.EndOffset
			$replacement = "& 'C:\Program Files\coreutils\cmd\"

			switch ($baseName) {
				'la' { $replacement += "ls.cmd' --color=auto -AFhl" }
				'ls' { $replacement += "ls.cmd' --color=auto" }
				default { $replacement += "$baseName.cmd'" }
			}

			# Walk command elements, merging adjacent ones whose extents touch
			# (e.g. `'a'*` parses as [SingleQuoted, BareWord] but is one shell word).
			# The inverse case `*'a'*` parses as a single BareWord whose text
			# contains the embedded quotes, which is why AST-only analysis
			# isn't enough and we still need to re-tokenize the source span.
			$argsStart = $end
			$argsEnd = $cmd.Extent.EndOffset
			$rewrittenArgs = ''
			$elements = $cmd.CommandElements
			$count = $elements.Count
			$i = 1
			while ($i -lt $count) {
				$first = $elements[$i]
				$wordStart = $first.Extent.StartOffset
				$wordEnd = $first.Extent.EndOffset
				$merged = $false
				while ($i + 1 -lt $count -and $elements[$i + 1].Extent.StartOffset -eq $wordEnd) {
					$i++
					$wordEnd = $elements[$i].Extent.EndOffset
					$merged = $true
				}
				$source = $line.Substring($wordStart, $wordEnd - $wordStart)
				$rewrittenArgs += $line.Substring($argsStart, $wordStart - $argsStart)
				$argsStart = $wordEnd
				# IndexOfAny beats running the regex per arg.
				if ($source.IndexOfAny($script:__COREUTILS_ARG_SPECIAL__) -lt 0) {
					$rewrittenArgs += $source
					$i++
					continue
				}
				# A single un-merged PS expression that needs $var resolution
				# (bare $var, "...$var...", $x.Member, $($expr), etc.).
				# Defer evaluation to runtime so the value reaches coreutils as a literal arg.
				# This matches POSIX behaviour where variable expansions don't result in globbing.
				if (-not $merged -and
					($first -is [System.Management.Automation.Language.VariableExpressionAst] -or
					$first -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
					$first -is [System.Management.Automation.Language.MemberExpressionAst])) {
					$rewrittenArgs += '(__coreutils_q ' + $source + ')'
					$i++
					continue
				}
				# Slow path: re-tokenise and re-emit as MSVCRT-style quoting,
				# then wrap in PS single quotes so PS hands the body verbatim.
				$windowsQuoted = $script:__COREUTILS_ARG_RX__.Replace($source, $script:__COREUTILS_ARG_EVAL__)
				$rewrittenArgs += "'" + $windowsQuoted.Replace("'", "''") + "'"
				$i++
			}
			$rewrittenArgs += $line.Substring($argsStart, $argsEnd - $argsStart)

			$line = $line.Substring(0, $start) + $replacement + $rewrittenArgs + $line.Substring($argsEnd)
		}

		return $line
	}
	# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
	# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a

	Write-Host -ForegroundColor blue "[+] Default + Linux coreutils PowerShell profile loaded."

	#Remove PowerShell aliases that conflict with Coreutils
	foreach ($name in $script:__COREUTILS__) {
		if (Test-Path -LiteralPath "Alias:\$name") {
			Remove-Item -LiteralPath "Alias:\$name" -Force -ErrorAction SilentlyContinue
		}
	}
	Remove-Item Function:\mkdir -Force -ErrorAction SilentlyContinue
	sleep 2

	#test that coreutils are loaded
	<#
	Get-Alias cat -ErrorAction SilentlyContinue
	Get-Command cat -All
	Get-Alias cp -ErrorAction SilentlyContinue
	Get-Command cp -All
	Get-Alias date -ErrorAction SilentlyContinue
	Get-Command date -All
	Get-Alias echo -ErrorAction SilentlyContinue
	Get-Command echo -All
	Get-Alias ls -ErrorAction SilentlyContinue
	Get-Command ls -All
	Get-Alias mkdir -ErrorAction SilentlyContinue
	Get-Command mkdir -All
	Get-Alias mv -ErrorAction SilentlyContinue
	Get-Command mv -All
	Get-Alias pwd -ErrorAction SilentlyContinue
	Get-Command pwd -All
	Get-Alias rm -ErrorAction SilentlyContinue
	Get-Command rm -All
	Get-Alias rmdir -ErrorAction SilentlyContinue
	Get-Command rmdir -All
	Get-Alias sleep -ErrorAction SilentlyContinue
	Get-Command sleep -All
	Get-Alias sort -ErrorAction SilentlyContinue
	Get-Command sort -All
	Get-Alias tee -ErrorAction SilentlyContinue
	Get-Command tee -All
	Get-Alias uptime -ErrorAction SilentlyContinue
	Get-Command uptime -All
	#>

	Write-Host -ForegroundColor blue "`n[+] Testing for shell conflicts:`n"
	#confirm unix commands are loaded
	ls --version
	cat --version
	cp --version
	date --version
	echo --version
	ls --version
	mkdir --version
	mv --version
	pwd --version
	rm --version
	rmdir --version
	sleep --version
	sort --version
	tee -V
	uptime --version
	Write-Host ''

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
	Write-Host '  📋 SESSION' -ForegroundColor blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	Write-Host ('  🖥️  Computer         {0}' -f $ComputerName)
	Write-Host ('  👤 User             {0}' -f $UserName)
	Write-Host ('  💠 PowerShell       {0} ({1})' -f $PowerShellVersion, $PowerShellEdition)
	Write-Host ('  🪟 Host             {0}' -f $PowerShellHost)

	if ($IsAdministrator) {
		Write-Host '  🛡️  Privileges       ADMINISTRATOR' -ForegroundColor Red
	} else {
		Write-Host '  👤 Privileges       Standard user' -ForegroundColor Gray
	}

	Write-Host ('  🔐 Execution policy {0}' -f $ExecutionPolicy)
	Write-Host ('  📂 Working directory {0}' -f $CurrentDirectory)

	# ------------------------------------------------------------
	# 🧠 Physical memory
	# ------------------------------------------------------------

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

	<# ------------------------------------------------------------
	# 📄 Profile
	# ------------------------------------------------------------

	Write-Host ''
	Write-Host '  📄 PROFILE' -ForegroundColor blue
	Write-Host '  --------------------------------------------------------' -ForegroundColor DarkGray

	Write-Host ('  📝 File             {0}' -f (Split-Path -Path $PSCommandPath -Leaf))
	Write-Host ('  📦 Size             {0}' -f $ProfileFileSize)
	Write-Host ('  📍 Path             {0}' -f $PSCommandPath)
	Write-Host ''
	Write-Host ''
#>
Write-Host ''

}	