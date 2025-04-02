# TODOs #
# WSL activation and installing WSL and adding .bashrc
# Selection Menu for what to install
# Update profile.ps1 (Review content)
# Edit Oh-My-Posh theme: blocks > segments > "type": "executiontime"; change "style": "roundrock" -> "style": "austin"
# Edit Oh-My-Posh theme: blocks > segments > "type": "os"; change -> "template": " {{ if eq .UserName \"kali\"}}Kali at \uF316{{ else if  .WSL }}WSL at {{.Icon}}{{ else }}{{.Icon}}{{ end }} ",
# Add ruff and uv config files: %APPDATA%\ruff\ruff.toml and %APPDATA%\uv\uv.toml
# Add Catppuccin Themes to everything
# Use this script for "Windows Files" theme install: `$host.UI | Add-Member -MemberType ScriptMethod -Name PromptForChoice -Value { $args[3] } -Force; . { iwr -UseBasicParsing https://github.com/catppuccin/windows-files/raw/main/install.ps1 } | iex`

param(
   [string]$GitHubToken,
   [switch]$InitialRun = $false # PowerShell7 switch is redundant now
)

function Write-ColorOutput($ForegroundColor, $Message) {
   # Simple wrapper for colored output
   Write-Host $Message -ForegroundColor $ForegroundColor
}

# Determine if running in PowerShell 7+
$IsPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
Write-ColorOutput Cyan "Running in PowerShell Version: $($PSVersionTable.PSVersion.ToString()) (IsPS7: $IsPowerShell7)"
Write-ColorOutput Cyan "InitialRun flag: $InitialRun"

# Change to user profile directory
Set-Location $env:USERPROFILE
Write-ColorOutput Cyan "Current Location: $(Get-Location)"


# Check if the HKCR PSDrive already exists
if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
   # If it doesn't exist, create it
   Write-ColorOutput Yellow "Creating HKCR PSDrive..."
   New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" -ErrorAction Stop | Out-Null
}

#region Core Functions
function InstallAllTheThings {
   Write-ColorOutput Magenta "--- Starting Main Installation Sequence ---"
   if (-not $IsPowerShell7) {
      # This block will only run if the script starts in PS5.1
      # It will attempt to install Winget and PS7, then restart.
      InstallWingetAndRestartIfInitialRun
   }
   else {
      # This block runs if the script *starts* in PS7 OR after a successful restart
      Write-ColorOutput Green "Running in PowerShell 7. Proceeding with installations..."
      # Ensure NuGet is available in PS7+ if needed later
      if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
         Write-ColorOutput Yellow "Installing NuGet Package Provider..."
         Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
      }
      # Run installations that require PS7 / Winget
      InstallDependencies
      QoLRegConfigurations
      InstallBasicKit
      InstallAdvanced
      InstallMedia
      InstallDevTools
      AddRegistryEntries
      NvidiaSettings
      # PoEStuff function missing, add if needed
      StartServices
      TakeOwnership
      TerminalStuff # Depends on PS7/Winget being present

      # Autostart AHK script
      $ahkScriptPath = Join-Path $env:USERPROFILE "autostart.ahk"
      if (Test-Path $ahkScriptPath) {
         Write-ColorOutput Green "Starting existing $ahkScriptPath"
         Start-Process $ahkScriptPath
      }
      else {
         Write-ColorOutput Green "Downloading Autostart.ahk..."
         try {
            Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/autostart.ahk" -Destination $ahkScriptPath -ErrorAction Stop
            if (Test-Path $ahkScriptPath) {
               Write-ColorOutput Green "Starting downloaded $ahkScriptPath"
               Start-Process $ahkScriptPath
            }
         }
         catch {
            Write-ColorOutput Red "Failed to download autostart.ahk: $($_.Exception.Message)"
         }
      }
   }
   Write-ColorOutput Magenta "--- End of Main Installation Sequence ---"
}

function Update-Environment {
   # This function attempts to refresh the current session's environment vars.
   # Note: Immediate effect, especially for PATH changes via AppX, isn't guaranteed.
   Write-ColorOutput Cyan "Attempting to update environment variables for current session..."
   $env:Path = ([System.Environment]::GetEnvironmentVariable("Path", "Machine", [System.EnvironmentVariableTarget]::Machine).TrimEnd(';') + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User", [System.EnvironmentVariableTarget]::User).TrimEnd(';')) -replace ';+', ';'
   # Reload PATH into current session
   $env:Path = $env:Path
   Write-ColorOutput Cyan "Session PATH updated (best effort)."
}

# Renamed function for clarity
function InstallWingetAndRestartIfInitialRun {
   Write-ColorOutput Yellow "--- Attempting Winget & PowerShell 7 Installation (Initial Run) ---"
   $wingetInstalled = $false
   $psInstallAttempted = $false
   $psInstallSuccess = $false

   # --- 1. Install Winget Dependencies and Winget itself ---
   if ($InitialRun.IsPresent) {
      Write-ColorOutput Green "Initial Run: Installing Winget dependencies and Winget..."
      try {
         $xamlPath = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.x64.appx"
         $vcLibsPath = Join-Path $env:TEMP "Microsoft.VCLibs.x64.14.00.Desktop.appx"
         $wingetBundlePath = Join-Path $env:TEMP "winget.msixbundle" # Simpler temp name

         Write-ColorOutput Cyan "Downloading UI.Xaml..."
         Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $xamlPath -ErrorAction Stop
         Write-ColorOutput Cyan "Installing UI.Xaml..."
         Add-AppxPackage -Path $xamlPath -ErrorAction Stop

         Write-ColorOutput Cyan "Downloading VCLibs..."
         Start-BitsTransfer -Source "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Destination $vcLibsPath -ErrorAction Stop
         Write-ColorOutput Cyan "Installing VCLibs..."
         Add-AppxPackage -Path $vcLibsPath -ErrorAction Stop

         Write-ColorOutput Cyan "Fetching latest Winget release..."
         $latestWingetMsixBundleUri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") } | Select-Object -First 1
         if (-not $latestWingetMsixBundleUri) { throw "Could not find latest Winget msixbundle URI." }

         Write-ColorOutput Cyan "Downloading Winget bundle..."
         Start-BitsTransfer -Source $latestWingetMsixBundleUri -Destination $wingetBundlePath -ErrorAction Stop
         Write-ColorOutput Cyan "Installing Winget bundle..."
         Add-AppxPackage -Path $wingetBundlePath -ErrorAction Stop

         $wingetInstalled = $true
         Write-ColorOutput Green "Winget installed via Add-AppxPackage successfully."

         # Attempt immediate PATH update (helper, restart is main fix)
         $windowsAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
         if (Test-Path $windowsAppsPath) {
            Write-ColorOutput Yellow "Adding $windowsAppsPath to session PATH (best effort)..."
            $env:Path = "$($env:Path.TrimEnd(';'));$windowsAppsPath" -replace ';+', ';'
            Start-Sleep -Seconds 5 # Give OS a moment
         }

      }
      catch {
         Write-ColorOutput Red "FATAL: Failed to install Winget or its dependencies: $($_.Exception.Message)"
         Write-ColorOutput Red "Script cannot continue without Winget. Exiting."
         exit 1 # Exit script with error code
      }
      finally {
         # Clean up installers
         Remove-Item -Path $xamlPath -ErrorAction SilentlyContinue
         Remove-Item -Path $vcLibsPath -ErrorAction SilentlyContinue
         Remove-Item -Path $wingetBundlePath -ErrorAction SilentlyContinue
      }
   }
   else {
      # Should not happen if called correctly, but safety check
      Write-ColorOutput Magenta "Winget installation skipped (Not Initial Run or already PS7)."
      return
   }

   # --- 2. Install PowerShell 7 using the (hopefully) just-installed Winget ---
   if ($wingetInstalled) {
      if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
         Write-ColorOutput Green "PowerShell 7 not found. Attempting installation via Winget..."
         $psInstallAttempted = $true
         try {
            # Use winget now - this was the failure point before
            winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
            $psInstallSuccess = $true
            Write-ColorOutput Green "PowerShell 7 installed successfully via Winget."
            # Attempt to ensure NuGet is available after PS7 install
            Write-ColorOutput Yellow "Ensuring NuGet Package Provider is installed..."
            # Need to find the new pwsh executable to run this
            $pwshExe = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($pwshExe) {
               Start-Process -FilePath $pwshExe.Source -ArgumentList "-NoProfile -Command Install-PackageProvider -Name NuGet -Force -Scope CurrentUser" -Wait
            }
            else {
               Write-ColorOutput Red "Could not find pwsh.exe after installation to install NuGet."
            }

         }
         catch {
            # Catch failure specifically for winget install pwsh
            Write-ColorOutput Red "FATAL: 'winget install Microsoft.PowerShell' failed. Error: $($_.Exception.Message)"
            Write-ColorOutput Red "This might indicate Winget path wasn't updated in time or another Winget issue."
            Write-ColorOutput Red "Script cannot continue reliably. Exiting."
            exit 1
         }
      }
      else {
         Write-ColorOutput Magenta "PowerShell 7 seems to be already installed."
         # If PS7 is already installed during InitialRun, we don't need to restart.
         # Set flags to simulate successful install to allow script to continue in PS5 context
         # (It will then likely fail later if PS7 features are needed, but avoids unnecessary exit)
         $psInstallAttempted = $true
         $psInstallSuccess = $true
      }
   }

   # --- 3. Trigger Restart if PS7 was just installed during InitialRun ---
   if ($InitialRun -and $psInstallAttempted -and $psInstallSuccess -and (-not (Get-Command pwsh -ErrorAction SilentlyContinue))) {
      # This condition should now only be true if winget install JUST finished
      Write-ColorOutput Yellow "PowerShell 7 was just installed during Initial Run. Restarting script in new PS7 session..."
      # Ensure $PSCommandPath is the full path to *this* running script
      if (-not $PSCommandPath) {
         # If running interactively or via IEX, $PSCommandPath might be empty. Use $MyInvocation
         if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
            $CurrentScriptPath = $MyInvocation.MyCommand.Path
            Write-ColorOutput Yellow "Using `$MyInvocation path: $CurrentScriptPath"
         }
         else {
            Write-ColorOutput Red "FATAL: Cannot determine current script path (\$PSCommandPath or \$MyInvocation). Cannot restart script."
            exit 1
         }
      }
      else {
         $CurrentScriptPath = $PSCommandPath
      }

      $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # Note: No -InitialRun on restart!
      Write-ColorOutput Cyan "Starting: pwsh $ArgList"
      try {
         Start-Process pwsh -ArgumentList $ArgList -ErrorAction Stop
         Write-ColorOutput Green "New PowerShell 7 process started. Exiting current PS5.1 session."
         exit 0 # Exit current script cleanly
      }
      catch {
         Write-ColorOutput Red "FATAL: Failed to start new PowerShell 7 process: $($_.Exception.Message)"
         exit 1
      }
   }
   else {
      Write-ColorOutput Cyan "No restart needed or conditions not met (Not InitialRun, PS7 already present, or PS7 install failed)."
      # If we get here in PS5 during InitialRun, something went wrong earlier (e.g., PS7 install failed but didn't exit)
      if ($InitialRun -and (-not $IsPowerShell7)) {
         Write-ColorOutput Red "Warning: Reached end of InstallWingetAndRestartIfInitialRun during InitialRun without restarting. Installations might fail."
      }
   }
   Write-ColorOutput Yellow "--- End of Winget & PowerShell 7 Installation ---"
}
#endregion

#region Installation Functions (Dependencies, Basic, Advanced, etc.)

function InstallNeededForScript {
   # These should run in PS7+ after potential restart
   Write-ColorOutput Magenta "--- Installing Script Prerequisites (jq, wget) ---"
   try {
      Set-PSRepository PSGallery -InstallationPolicy Trusted -ErrorAction Stop
      winget install -h jqlang.jq --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      winget install -h GerbenBosscher.Wget --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop # Corrected ID likely
   }
   catch {
      Write-ColorOutput Red "Failed to install script prerequisites: $($_.Exception.Message)"
      # Decide whether to exit or continue
   }
}

function DownlaodInstallGithub($name, $repo, $filePattern) {
   Write-ColorOutput Magenta "--- Installing $name from GitHub ($repo) ---"
   $downloadPath = Join-Path $env:TEMP "$($filePattern.Split('*')[0].TrimEnd('-','.')).exe"

   try {
      # Fetch the latest release information
      Write-ColorOutput Cyan "Fetching latest release info for $repo..."
      $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -ErrorAction Stop

      # Find the asset URL
      $assetUrl = $releaseInfo.assets | Where-Object { $_.name -like $filePattern } | Select-Object -ExpandProperty browser_download_url -First 1

      if (-not $assetUrl) {
         Write-ColorOutput Red "Could not find asset matching '$filePattern' in the latest release of $repo."
         return # Don't stop the whole script, just skip this app
      }

      # Download the file
      Write-ColorOutput Green "Downloading $name from $assetUrl..."
      Start-BitsTransfer -Source $assetUrl -Destination $downloadPath -ErrorAction Stop

      # Check if the file was downloaded successfully
      if (Test-Path $downloadPath) {
         Write-ColorOutput Green "Download completed. Installing $name silently..."
         # Use /S or /VERYSILENT common silent switches. May need adjustment per installer.
         Start-Process -FilePath $downloadPath -ArgumentList "/S" -Wait -ErrorAction Stop
         Write-ColorOutput Green "$name installation command issued."
      }
      else {
         # Should be caught by Start-BitsTransfer -ErrorAction Stop, but safety check
         Write-ColorOutput Red "Failed to download $name (File not found after BITS transfer)."
      }
   }
   catch {
      $errorMessage = "... {0} ..." -f $_.Exception.Message
      Write-ColorOutput Red "An error occurred during download/install of $errorMessage"
   }
   finally {
      Remove-Item -Path $downloadPath -ErrorAction SilentlyContinue
   }
}

function Gaming {
   Write-ColorOutput Magenta "--- Installing Gaming Apps ---"
   # Consider moving nested functions out for readability
   function wow {
      Write-ColorOutput Cyan "Installing WoW related apps..."
      winget install -h Blizzard.BattleNet --accept-source-agreements --accept-package-agreements -e -l "C:\Program Files\Battle.net\" --ErrorAction Stop
      winget install -h WowUp.CF --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   }

   function poe {
      Write-ColorOutput Cyan "Installing Path of Exile related apps..."
      DownlaodInstallGithub "PoELurker" "C1rdec/Poe-Lurker" "PoeLurkerSetup*.exe"
      DownlaodInstallGithub "AwakenedPoeTrade" "SnosMe/awakened-poe-trade" "Awakened-PoE-Trade-Setup-*.exe"
      winget install -h PathofBuildingCommunity.PathofBuildingCommunity --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   }

   wow # Call nested function
   poe # Call nested function

   winget install -h Valve.Steam --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h TeamSpeakSystems.TeamSpeakClient.Beta --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function InstallBasicKit {
   Write-ColorOutput Magenta "--- Installing Basic Kit ---"
   winget install -h AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   try {
      Write-ColorOutput Cyan "Installing uv..."
      powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" # Ensure Bypass
   }
   catch {
      Write-ColorOutput Red "Failed to install uv: $($_.Exception.Message)"
   }
   # Update PATH for uv - requires knowing where it installs! Assumes %USERPROFILE%\.local\bin
   $uvPath = Join-Path $env:USERPROFILE ".local\bin"
   if (Test-Path $uvPath) {
      Write-ColorOutput Cyan "Adding uv path ($uvPath) to session PATH..."
      $env:PATH = "$uvPath;$env:PATH"
   }
   else {
      Write-ColorOutput Yellow "uv path ($uvPath) not found after install attempt."
   }

   winget install Microsoft.VisualStudioCode --override "/verysilent /suppressmsgboxes /mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" --accept-source-agreements --accept-package-agreements -e --disable-interactivity --ErrorAction Stop
   DownlaodInstallGithub "PowerToys" "microsoft/PowerToys" "PowerToysUserSetup-*-x64.exe"

   winget install -h Audacity.Audacity --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h dotPDN.PaintDotNet --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Discord.Discord --accept-source-agreements --accept-package-agreements -e --disable-interactivity --ErrorAction Stop
   winget install -h Foxit.FoxitReader --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h MediaArea.MediaInfo.GUI --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Xanashi.Icaros --accept-source-agreements --accept-package-agreements -e --source winget --ErrorAction Stop
   winget install -h XP8BSBGQW2DKS0 --accept-source-agreements --accept-package-agreements -e --force --ErrorAction Stop
   InstallJdownloader
   winget install -h RevoUninstaller.RevoUninstaller --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Nvidia.Broadcast --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop

   winget install -h Telegram.TelegramDesktop --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h 9N8G7TSCL18R --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Google.QuickShare --accept-source-agreements --accept-package-agreements -e --disable-interactivity --ErrorAction Stop
   winget install -h Mozilla.Firefox.DeveloperEdition --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Parsec.Parsec --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h 9NCBCSZSJRSB --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install --id lsd-rs.lsd --accept-package-agreements --accept-source-agreements -e --ErrorAction Stop
}

function InstallJdownloader {
   Write-ColorOutput Cyan "Installing JDownloader and configuration..."
   try {
      winget install -h AppWork.JDownloader --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      $jdownloaderConfigDest = "C:\Program Files\JDownloader\cfg\org.jdownloader.controlling.filter.LinkFilterSettings.filterlist.json" # Assuming default install path
      if (Test-Path (Split-Path $jdownloaderConfigDest)) {
         Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/jdownloader.json" -Destination $jdownloaderConfigDest -ErrorAction Stop
         Write-ColorOutput Green "JDownloader config applied."
      }
      else {
         Write-ColorOutput Yellow "JDownloader config directory not found. Skipping config."
      }
   }
   catch {
      Write-ColorOutput Red "Failed during JDownloader install/config: $($_.Exception.Message)"
   }
}

function InstallAdvanced {
   Write-ColorOutput Magenta "--- Installing Advanced Kit ---"
   winget install -h Logitech.GHUB --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop # Can be problematic
   winget install -h Microsoft.Sysinternals.ProcessExplorer --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h StefanSundin.Superf4 --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h ArcadeRenegade.SidebarDiagnostics --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h 9NBLGGH4S79B --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h AntibodySoftware.WizTree --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h 9NK1HLWHNP8S --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop

   winget install Obsidian.Obsidian --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Intel.PresentMon --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Bruno.Bruno --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h qBittorrent.qBittorrent --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h WinSCP.WinSCP --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h voidtools.Everything --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h Nvidia.PhysX --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop

   winget install -h UnifiedIntents.UnifiedRemote --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h HandBrake.HandBrake --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function InstallMedia {
   Write-ColorOutput Magenta "--- Installing Media Apps ---"
   winget install -h Jellyfin.JellyfinMediaPlayer --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h XBMCFoundation.Kodi --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function InstallDependencies {
   Write-ColorOutput Magenta "--- Installing Core Dependencies ---"
   # Use -i (--ignore-unavailable) as some might already be present depending on Windows version
   winget install -h Microsoft.DotNet.DesktopRuntime.6 --accept-source-agreements --accept-package-agreements -e -i
   winget install -h Microsoft.XNARedist --accept-source-agreements --accept-package-agreements -e -i
   winget install -h Microsoft.VCRedist.2015+.x86 --accept-source-agreements --accept-package-agreements -e -i
   winget install -h Microsoft.VCRedist.2015+.x64 --accept-source-agreements --accept-package-agreements -e -i
}

function InstallDevTools {
   Write-ColorOutput Magenta "--- Installing Developer Tools ---"
   winget install -h Chocolatey.Chocolatey --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   winget install -h JetBrains.Toolbox --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
   InstallPythonAndPackages # Contains winget installs
   SetupGit # Contains winget installs
   winget install Nvidia.CUDA --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function InstallPythonAndPackages {
   Write-ColorOutput Cyan "--- Installing Python Versions and Tools via uv ---"
   if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
      Write-ColorOutput Red "uv command not found. Skipping Python/Tool installation."
      return
   }
   $pythonVersions = @("3.7", "3.8", "3.9", "3.10", "3.11", "3.12")
   foreach ($version in $pythonVersions) {
      Write-ColorOutput Cyan "Installing Python $version via uv..."
      try {
         uv python install $version
      }
      catch {
         # Use -f format operator
         $errorMessage = "Failed to install Python '{0}': {1}" -f $version, $_.Exception.Message
         Write-ColorOutput Red $errorMessage
      }
   }

   $pythonTools = @("hashcat", "ipython", "nuitka", "ruff")
   foreach ($tool in $pythonTools) {
      Write-ColorOutput Cyan "Installing Python tool '$tool' via uv..."
      try {
         uv tool install $tool
      }
      catch {
         # Use -f format operator
         $errorMessage = "Failed to install tool '{0}': {1}" -f $tool, $_.Exception.Message
         Write-ColorOutput Red $errorMessage
      }
   }
   try {
      uv tool ensurepath
   }
   catch {
      # Use -f format operator
      $errorMessage = "Failed uv ensurepath: {0}" -f $_.Exception.Message
      Write-ColorOutput Red $errorMessage
   }

   Install-PyCharm -SkipPyFileAssociation # Call internal function
}

# Internal function for PyCharm install logic
function Install-PyCharm {
   param (
      [string]$InstallDir = "C:\Program Files\JetBrains\PyCharm", # Default install path might vary
      [switch]$SkipAddToPath,
      [switch]$SkipContextMenu,
      [switch]$SkipPyFileAssociation
   )
   Write-ColorOutput Cyan "Installing PyCharm Professional..."
   $tempConfigPath = [System.IO.Path]::Combine($env:TEMP, "pycharm_install.config")
   $configContent = @"
mode=admin
launcher32=0
launcher64=1
updatePATH=$(if (-not $SkipAddToPath.IsPresent) {"1"} else {"0"})
updateContextMenu=$(if (-not $SkipContextMenu.IsPresent) {"1"} else {"0"})
jre32=0
regenerationSharedArchive=1
`.py`=$(if (-not $SkipPyFileAssociation.IsPresent) {"1"} else {"0"})
"@
   try {
      Set-Content -Path $tempConfigPath -Value $configContent -Encoding ASCII -Force -ErrorAction Stop
      $installCommand = "winget install -e --id JetBrains.PyCharm.Professional --override `"/S /CONFIG=$tempConfigPath /D=$InstallDir`" --accept-source-agreements --accept-package-agreements --ErrorAction Stop"
      Write-ColorOutput Cyan "Running: $installCommand"
      Invoke-Expression $installCommand
      Write-ColorOutput Green "PyCharm installation command issued."
   }
   catch {
      Write-ColorOutput Red "Failed to install PyCharm: $($_.Exception.Message)"
   }
   finally {
      Remove-Item -Path $tempConfigPath -Force -ErrorAction SilentlyContinue
   }
}

function SetupGit {
   Write-ColorOutput Magenta "--- Setting Up Git ---"
   if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
      Write-ColorOutput Red "Git command not found. Skipping Git setup."
      return
   }
   try {
      git config --global user.email "kmeinon@gmail.com"
      git config --global user.name "Kevin Meinon"
      git config --global --add safe.directory '*'
      Write-ColorOutput Green "Git user configured globally."
      LoginGitHubCLI -Token $GitHubToken -ErrorAction Stop
   }
   catch {
      Write-ColorOutput Red "Failed during Git setup: $($_.Exception.Message)"
   }
}

# Internal function for GitHub CLI Login
function LoginGitHubCLI {
   param (
      [Parameter(Mandatory = $true)]
      [string]$Token
   )
   Write-ColorOutput Cyan "Attempting GitHub CLI authentication..."
   if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-ColorOutput Red "GitHub CLI (gh) command not found. Skipping authentication."
      return
   }
   try {
      $output = $Token | gh auth login --hostname "github.com" --with-token --git-protocol https 2>&1
      if ($output -match 'Authentication successful' -or $output -match 'Already logged in') {
         Write-ColorOutput Green "Successfully authenticated with GitHub CLI."
      }
      else {
         Write-ColorOutput Red "Failed to authenticate with GitHub CLI. Output: $output"
      }
   }
   catch {
      Write-ColorOutput Red "An error occurred while running GitHub CLI: $($_.Exception.Message)"
   }
}
#endregion

#region Configuration Functions (Registry, Services, Profiles)

function TakeOwnership {
   Write-ColorOutput Magenta "--- Applying Take Ownership Registry ---"
   try {
      Remove-Item -Path "Registry::HKCR\*\shell\TakeOwnership" -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -Path "Registry::HKCR\*\shell\runas" -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -Path "Registry::HKCR\Drive\shell\runas" -Recurse -Force -ErrorAction SilentlyContinue

      # Files
      New-Item -Path "Registry::HKCR\*\shell\TakeOwnership" -Force -ErrorAction Stop | Out-Null
      Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -Name "(Default)" -Value "Take Ownership" -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -Name "HasLUAShield" -PropertyType String -Value "" -Force -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -Name "NoWorkingDirectory" -PropertyType String -Value "" -Force -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -Name "NeverDefault" -PropertyType String -Value "" -Force -ErrorAction Stop
      New-Item -Path "Registry::HKCR\*\shell\TakeOwnership\command" -Force -ErrorAction Stop | Out-Null
      $commandValue = 'powershell -windowstyle hidden -command "Start-Process cmd -ArgumentList ''/c takeown /f \""%1\"" && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l'' -Verb runAs"'
      Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership\command" -Name "(Default)" -Value $commandValue -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership\command" -Name "IsolatedCommand" -Value $commandValue -ErrorAction Stop

      # Directories
      New-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Force -ErrorAction Stop | Out-Null
      Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Name "(Default)" -Value "Take Ownership" -ErrorAction Stop
      $appliesToValue = 'NOT (System.ItemPathDisplay:="C:\Users" OR System.ItemPathDisplay:="C:\ProgramData" OR System.ItemPathDisplay:="C:\Windows" OR System.ItemPathDisplay:="C:\Windows\System32" OR System.ItemPathDisplay:="C:\Program Files" OR System.ItemPathDisplay:="C:\Program Files (x86)")'
      Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Name "AppliesTo" -Value $appliesToValue -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Name "HasLUAShield" -PropertyType String -Value "" -Force -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Name "NoWorkingDirectory" -PropertyType String -Value "" -Force -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Name "Position" -Value "middle" -ErrorAction Stop
      New-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -Force -ErrorAction Stop | Out-Null
      $dirCommandValue = 'powershell -windowstyle hidden -command "$Y = ($null | choice).Substring(1,1); Start-Process cmd -ArgumentList (''/c takeown /f \""%1\"" /r /d '' + $Y + '' && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l /q'') -Verb runAs"'
      Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -Name "(Default)" -Value $dirCommandValue -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -Name "IsolatedCommand" -Value $dirCommandValue -ErrorAction Stop

      # Drives
      New-Item -Path "Registry::HKCR\Drive\shell\runas" -Force -ErrorAction Stop | Out-Null
      Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -Name "(Default)" -Value "Take Ownership" -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -Name "HasLUAShield" -PropertyType String -Value "" -Force -ErrorAction Stop
      New-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -Name "NoWorkingDirectory" -PropertyType String -Value "" -Force -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -Name "Position" -Value "middle" -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -Name "AppliesTo" -Value 'NOT (System.ItemPathDisplay:="C:\")' -ErrorAction Stop
      New-Item -Path "Registry::HKCR\Drive\shell\runas\command" -Force -ErrorAction Stop | Out-Null
      $driveCommandValue = 'cmd.exe /c takeown /f "%1\" /r /d y && icacls "%1\" /grant *S-1-3-4:F /t /c'
      Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas\command" -Name "(Default)" -Value $driveCommandValue -ErrorAction Stop
      Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas\command" -Name "IsolatedCommand" -Value $driveCommandValue -ErrorAction Stop

      Write-ColorOutput Green "Take Ownership registry entries applied successfully."
   }
   catch {
      Write-ColorOutput Red "Failed to apply Take Ownership registry entries: $($_.Exception.Message)"
   }
}

function AddRegistryEntries {
   Write-ColorOutput Magenta "--- Applying Other Registry Entries (WizTree) ---"
   try {
      $wizTreeExe = "C:\Program Files\WizTree\WizTree64.exe" # Assuming default path
      if (Test-Path $wizTreeExe) {
         $regPathCommand = "Registry::HKLM\SOFTWARE\Classes\*\shell\WizTree\command"
         $regPathIcon = "Registry::HKLM\SOFTWARE\Classes\*\shell\WizTree"
         New-Item -Path $regPathIcon -Force -ErrorAction Stop | Out-Null
         New-Item -Path $regPathCommand -Force -ErrorAction Stop | Out-Null
         Set-ItemProperty -Path $regPathCommand -Name "(Default)" -Value "`"$wizTreeExe`" `"%1`"" -ErrorAction Stop
         Set-ItemProperty -Path $regPathIcon -Name "Icon" -Value "`"$wizTreeExe`",0" -ErrorAction Stop
         Write-ColorOutput Green "WizTree context menu entry added."
      }
      else { Write-ColorOutput Yellow "WizTree executable not found at '$wizTreeExe'. Skipping context menu entry." }
   }
   catch { Write-ColorOutput Red "Failed to add WizTree registry entry: $($_.Exception.Message)" }
}

function Start-Services {
   Write-ColorOutput Magenta "--- Configuring Services (SSH Agent) ---"
   $services = @("ssh-agent")
   foreach ($serviceName in $services) {
      try {
         $service = Get-Service $serviceName -ErrorAction Stop
         if ($service.Status -ne 'Running') {
            Write-ColorOutput Cyan "Setting '$serviceName' startup to Automatic and starting..."
            Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-ColorOutput Green "'$serviceName' started."
         }
         else {
            Write-ColorOutput Green "'$serviceName' is already running."
            if ($service.StartType -ne 'Automatic') {
               Write-ColorOutput Cyan "Setting '$serviceName' startup to Automatic..."
               Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
            }
         }
      }
      catch { Write-ColorOutput Red "Failed to configure or start service '$serviceName': $($_.Exception.Message)" }
   }
}

function TerminalStuff {
   Write-ColorOutput Magenta "--- Setting Up Terminal Environment ---"
   # Needs to run in PS7+ context
   InstallNeededForScript # Install jq, wget first

   try {
      winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      winget install -h 9N0DX20HK701 --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop # Windows Terminal

      Set-WindowsTerminalAsDefault # Call internal function

      winget install -h JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -Force -ErrorAction Stop }
      Install-Module -Name Terminal-Icons -Repository PSGallery -Force -ErrorAction Stop
      Update-Environment
      oh-my-posh font install FiraCode # May require user interaction

      # Install Clink
      winget install -h ChrisLundquist.Clink --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
      $clinkPath = "C:\Program Files (x86)\clink" # Default path
      if (Test-Path $clinkPath) {
         Write-ColorOutput Cyan "Adding Clink path to session PATH..."
         $env:Path = "$($env:Path.TrimEnd(';'));$clinkPath" -replace ';+', ';'
         try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c clink set clink.logo none" -Wait -WindowStyle Hidden } catch { Write-ColorOutput Yellow "Could not run clink set command: $($_.Exception.Message)" }
         $clinkConfigDir = Join-Path $env:LOCALAPPDATA "clink"
         New-Item -Path $clinkConfigDir -ItemType Directory -Force -ErrorAction SilentlyContinue
         $ohMyPoshLuaContent = @"
load(io.popen('oh-my-posh init cmd --config=""$env:POSH_THEMES_PATH\jandedobbeleer.omp.json""'):read(""*a""))()
"@
         Set-Content -Path (Join-Path $clinkConfigDir "oh-my-posh.lua") -Value $ohMyPoshLuaContent -ErrorAction Stop
      }
      else { Write-ColorOutput Yellow "Clink path not found. Skipping config." }

      PowerShellProfileSettings # Call profile function

      $wtSettingsDest = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
      Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/terminal-settings.json" -Destination $wtSettingsDest -ErrorAction Stop
      Write-ColorOutput Green "Terminal settings downloaded."

   }
   catch {
      Write-ColorOutput Red "An error occurred during Terminal setup: $($_.Exception.Message)"
   }
}

# Internal function used by TerminalStuff
function Set-WindowsTerminalAsDefault {
   Write-ColorOutput Cyan "Setting Windows Terminal as default console host..."
   try {
      $wtCmd = Get-Command wt -ErrorAction SilentlyContinue
      if (-not $wtCmd) {
         Write-ColorOutput Yellow "Windows Terminal (wt.exe) not found in PATH. Cannot set as default yet."
         return
      }
      $consoleRegPath = "Registry::HKCU\Console"
      if (-not (Test-Path $consoleRegPath)) { New-Item -Path $consoleRegPath -Force | Out-Null }
      # Ensure %%Startup exists
      if (-not (Test-Path "$consoleRegPath\%%Startup")) { New-Item -Path "$consoleRegPath\%%Startup" -Force | Out-Null }
      New-ItemProperty -Path "$consoleRegPath\%%Startup" -Name "DelegationConsole" -Value "{00000000-0000-0000-0000-000000000000}" -PropertyType String -Force -ErrorAction Stop
      New-ItemProperty -Path "$consoleRegPath\%%Startup" -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -PropertyType String -Force -ErrorAction Stop

      Write-ColorOutput Green "Windows Terminal has been set as the default console host (Registry update)."
   }
   catch {
      Write-ColorOutput Red "An error occurred while setting Windows Terminal as default: $($_.Exception.Message)"
   }
}

function QoLRegConfigurations {
   Write-ColorOutput Magenta "--- Applying Quality-of-Life Registry Configs ---"
   try {
      # Remove specific UK/US keyboard layouts (0809=UK, 0409=US) - adjust if needed
      $layoutsToRemove = @("00000809", "00000409")
      $preloadPath = "Registry::HKCU:\Keyboard Layout\Preload"
      $substitutesPath = "Registry::HKCU:\Keyboard Layout\Substitutes"

      # Remove Substitute
      if (Test-Path $substitutesPath) {
         if (Get-ItemProperty -Path $substitutesPath -Name "00000809" -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $substitutesPath -Name "00000809" -Force
            Write-ColorOutput Cyan "Removed Substitute 00000809."
         }
      }

      # Remove Preloads
      if (Test-Path $preloadPath) {
         $preloadEntries = Get-ItemProperty -Path $preloadPath
         $properties = $preloadEntries.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' }

         foreach ($layoutToRemove in $layoutsToRemove) {
            $propToRemove = $properties | Where-Object { $_.Value -eq $layoutToRemove } | Select-Object -First 1
            if ($propToRemove) {
               Remove-ItemProperty -Path $preloadPath -Name $propToRemove.Name -Force
               Write-ColorOutput Cyan "Removed Preload entry '$($propToRemove.Name)' with value '$layoutToRemove'."
            }
            else { Write-ColorOutput Yellow "Preload entry for layout '$layoutToRemove' not found." }
         }
         Write-ColorOutput Cyan "`nCurrent Preload entries:"
         Get-ItemProperty -Path $preloadPath | Format-List
      }
      else { Write-ColorOutput Yellow "Keyboard Preload registry path not found." }

      Write-ColorOutput Yellow "Restarting Explorer process to apply keyboard layout changes..."
      Stop-Process -Name explorer -Force

   }
   catch {
      Write-ColorOutput Red "Failed during QoL Registry Config: $($_.Exception.Message)"
   }
}

function PowerShellProfileSettings {
   Write-ColorOutput Magenta "--- Configuring PowerShell Profiles (All Users, All Hosts) ---"
   # Requires Administrator privileges

   # Define the common profile content
   $commonProfileContent = @"
# Common settings for PowerShell Profile (All Users, All Hosts)

# Oh My Posh Initialization
# Check if the command exists before trying to run init
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    # Use a built-in theme or ensure the custom path is correct and accessible system-wide
    # Using 'jandedobbeleer' as a fallback; replace with your 'night-owl' if $env:POSH_THEMES_PATH is set system-wide
    # or provide the full path to night-owl.omp.json if needed.
    # Consider potential issues if POSH_THEMES_PATH isn't defined for all users.
    `$themePath = Join-Path `$env:POSH_THEMES_PATH "jandedobbeleer.omp.json" # Default theme path
    if (Test-Path `$themePath) {
        oh-my-posh init pwsh --config "`$themePath" | Invoke-Expression
    } else {
        Write-Warning "Oh My Posh theme not found at default path: `$themePath. Using default prompt."
    }
} else {
    Write-Warning "oh-my-posh command not found. Skipping Posh initialization."
}

# Terminal Icons Module Import
# Check if the module exists before importing
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
} else {
    Write-Warning "Terminal-Icons module not found. Skipping import."
}

# Aliases
# Set aliases carefully in AllUsers profiles to avoid conflicts
Set-Alias denv Deactivate -ErrorAction SilentlyContinue -Scope Global # Use Global scope

# Functions
# Define functions within the profile scope
function mklink (`$target, `$link) {
    # Ensure the command runs with appropriate context if needed, though New-Item is usually fine
    New-Item -Path `$link -ItemType SymbolicLink -Value `$target -ErrorAction Stop
}

# Auto-activate venv (optional, consider performance impact on shell startup for all users)
# function Activate-Venv { ... } # Keep function definition from previous version if desired
# Activate-Venv # Call it if you want it to run for every user on every shell start

"@

   # --- Target Paths ---
   # Windows PowerShell (PS 5.1) All Users Profile Path
   $ps5ProfilePath = Join-Path $PSHOME "profile.ps1" # $PSHOME is correct for PS5.1 system location

   # PowerShell 7+ All Users Profile Path
   $ps7ProfilePath = ""
   $pwshExe = Get-Command pwsh -ErrorAction SilentlyContinue
   if ($pwshExe) {
      $ps7InstallDir = Split-Path $pwshExe.Source -Parent
      $ps7ProfilePath = Join-Path $ps7InstallDir "profile.ps1"
   }
   else {
      Write-ColorOutput Yellow "pwsh.exe not found. Cannot determine PS7+ AllUsers profile path."
   }

   # --- Apply Profile Content ---
   # Apply to PS 5.1
   Write-ColorOutput Cyan "Attempting to configure PS 5.1 AllUsers profile: $ps5ProfilePath"
   try {
      # Ensure directory exists (should for $PSHOME, but belt-and-suspenders)
      $ps5ProfileDir = Split-Path $ps5ProfilePath -Parent
      if (-not (Test-Path $ps5ProfileDir)) {
         Write-ColorOutput Yellow "PS 5.1 profile directory '$ps5ProfileDir' not found? Attempting to create..."
         New-Item -Path $ps5ProfileDir -ItemType Directory -Force -ErrorAction Stop
      }
      Set-Content -Path $ps5ProfilePath -Value $commonProfileContent -Force -Encoding UTF8 -ErrorAction Stop
      Write-ColorOutput Green "PS 5.1 AllUsers profile configured successfully."
   }
   catch {
      Write-ColorOutput Red "Failed to configure PS 5.1 AllUsers profile: $($_.Exception.Message)"
   }

   # Apply to PS 7+ if path found
   if ($ps7ProfilePath -and (Test-Path (Split-Path $ps7ProfilePath -Parent))) {
      Write-ColorOutput Cyan "Attempting to configure PS 7+ AllUsers profile: $ps7ProfilePath"
      try {
         # Directory should exist if pwsh was found correctly
         Set-Content -Path $ps7ProfilePath -Value $commonProfileContent -Force -Encoding UTF8 -ErrorAction Stop
         Write-ColorOutput Green "PS 7+ AllUsers profile configured successfully."
      }
      catch {
         Write-ColorOutput Red "Failed to configure PS 7+ AllUsers profile: $($_.Exception.Message)"
      }
   }
   elseif ($pwshExe) {
      Write-ColorOutput Yellow "PS 7+ installation directory found, but cannot write profile to '$ps7ProfilePath'. Check permissions or path."
   }

   Write-ColorOutput Magenta "--- Finished Configuring PowerShell Profiles ---"
}


function NvidiaSettings {
   Write-ColorOutput Magenta "--- Applying NVIDIA Overlay Settings ---"
   try {
      $overlayBaseDir = Join-Path $env:LOCALAPPDATA "NVIDIA Corporation\NVIDIA Overlay"
      $gallerySettingsPath = Join-Path $overlayBaseDir "GallerySettings.json"
      $shareSettingsPath = Join-Path $overlayBaseDir "ShareSettings.json"

      if (-not (Test-Path $overlayBaseDir)) { New-Item -Path $overlayBaseDir -ItemType Directory -Force }

      $gallery_settings = @"
{
    "settings": { "capEnabled": false, "capSizePercent": 100, "currentDirectoryV2": "D:\\Recording\\RAW",
                  "tempDirectory": "$($env:LOCALAPPDATA.Replace('\','\\'))\\Temp\\", "trackerUpdateState": "TrackerUpdateComplete" }
}
"@
      $share_settings = @"
{ "settings": {
    "shortcuts": { "OpenIGO": [ 18, 17, 78 ], "Screenshot": [ 0 ], "PMOCOverlay": [ 18, 121 ], "OpenFreestyle": [ 0 ], "RecordToggle": [ 17, 117 ], "OpenAnsel": [ 0 ], "DVRSave": [ 18, 117 ], "DVRToggle": [ 17, 18, 117 ], "MicToggle": [ 0 ], "PTT": [ 0 ], "FreeStyleToggleStyle1": [], "FreeStyleToggleStyle2": [], "FreeStyleToggleStyle3": [], "PMOCOverlayVisibility": [ 0 ], "PMOCOverlayCycle": [ 17, 121 ], "PMOCResetAverageMetrics": [], "PMOCLoggingToggle": [] },
    "globalhighlights": { "enabled": true }, "video": { "irEnabled": false, "irBufferLength": 180 }, "micmode": { "mode": "on" } } }
"@

      Set-Content -Path $gallerySettingsPath -Value $gallery_settings -Encoding UTF8 -Force -ErrorAction Stop
      Set-Content -Path $shareSettingsPath -Value $share_settings -Encoding UTF8 -Force -ErrorAction Stop
      Write-ColorOutput Green "NVIDIA Overlay Gallery and Share settings applied."

   }
   catch { Write-ColorOutput Red "Failed to apply NVIDIA settings: $($_.Exception.Message)" }
}
#endregion

# --- Main Script Execution ---
try {
   InstallAllTheThings -ErrorAction Stop # Call the master function, stop script on unhandled error within it
   Write-ColorOutput Green "##############################################"
   Write-ColorOutput Green "All installations and configurations completed."
   Write-ColorOutput Green "##############################################"
}
catch {
   Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
   Write-ColorOutput Red "An UNHANDLED ERROR occurred in the main script execution:"
   Write-ColorOutput Red $_.Exception.ToString() # Use ToString() for more detail potentially
   Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
   exit 1 # Exit with error code
}

exit 0 # Explicitly exit with success code
