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
    [switch]$PowerShell7 = $false,
    [switch]$InitialRun = $false
)

# At the beginning of your script
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PowerShell7 = $true
}

Write-Host "Script starting - PowerShell Version: $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Cyan
Write-Host "Parameters - InitialRun: $InitialRun, PowerShell7: $PowerShell7, GitHubToken: $($GitHubToken -ne $null)" -ForegroundColor Cyan
Write-Host "Invocation context - InvocationName: '$($MyInvocation.InvocationName)', Line: '$($MyInvocation.Line)'" -ForegroundColor Cyan

# Check if we're being dot-sourced
$IsDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\s*\.\s+'
Write-Host "Dot-sourced execution detected: $IsDotSourced" -ForegroundColor Cyan

# If this is the initial run and we're not already in PowerShell 7, restart in PowerShell 7
if ($InitialRun -and -not $PowerShell7 -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "PowerShell 7 detected but not currently running. Restarting script in PowerShell 7..." -ForegroundColor Yellow

    # Build the restart command with all original parameters
    $restartArgs = @("-File", $MyInvocation.MyCommand.Path)
    if ($GitHubToken) { $restartArgs += "-GitHubToken", $GitHubToken }
    $restartArgs += "-PowerShell7", "-InitialRun"

    # Start the script in PowerShell 7
    Start-Process -FilePath "pwsh.exe" -ArgumentList $restartArgs -Wait -NoNewWindow
    exit
}

Write-Host "Continuing with script execution..." -ForegroundColor Green
Write-Host "About to set location to user profile: $env:USERPROFILE" -ForegroundColor Cyan

# Rest of your script goes here
# Change to user profile directory
Set-Location $env:USERPROFILE

function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

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
    if (-not $PowerShell7) {
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

function InstallWingetAndRestartIfInitialRun {
    Write-ColorOutput Yellow "--- Attempting Winget & PowerShell 7 Installation (Initial Run) ---"
    $wingetInstalled = $false
    $psInstallSuccess = $false

    # Check for pre-installed Terminal
    Write-ColorOutput Cyan "Checking for existing Windows Terminal installation..."
    try { if (Get-AppxPackage -Name "Microsoft.WindowsTerminal" -EA SilentlyContinue) { Write-ColorOutput Green "Windows Terminal appears to be pre-installed."; $global:TerminalAlreadyInstalled = $true } else { Write-ColorOutput Yellow "Windows Terminal not detected."; $global:TerminalAlreadyInstalled = $false } }
    catch { Write-ColorOutput Yellow "Could not check for Windows Terminal: $($_.Exception.Message)"; $global:TerminalAlreadyInstalled = $false }


    if ($InitialRun.IsPresent) {
        Write-ColorOutput Green "Initial Run: Installing prerequisites..."
        # --- 1. Ensure Latest VC++ Redistributable (Provides VCLibs) ---
        $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcRedistPath = Join-Path $env:TEMP "vc_redist.x64.exe"
        try {
            Write-ColorOutput Cyan "Downloading latest VC++ Redistributable..."
            Start-BitsTransfer -Source $vcRedistUrl -Destination $vcRedistPath -ErrorAction Stop
            Write-ColorOutput Cyan "Installing/Verifying VC++ Redistributable silently..."
            # Installer handles existing versions gracefully
            Start-Process -FilePath $vcRedistPath -ArgumentList "/install /quiet /norestart" -Wait -ErrorAction Stop
            Write-ColorOutput Green "VC++ Redistributable check/install complete."
        }
        catch {
            Write-ColorOutput Red "FATAL: Failed VC++ Redistributable step: $($_.Exception.Message)"; exit 1
        }
        finally { Remove-Item -Path $vcRedistPath -EA SilentlyContinue }

        # --- 2. Check and Install UI.Xaml if needed ---
        Write-ColorOutput Cyan "Checking for Microsoft.UI.Xaml.2.8..."
        $xamlInstalled = $false
        try {
            if (Get-AppxPackage -Name Microsoft.UI.Xaml.2.8 -ErrorAction SilentlyContinue) {
                Write-ColorOutput Green "Microsoft.UI.Xaml.2.8 is already installed. Skipping install."
                $xamlInstalled = $true
            }
        }
        catch { Write-ColorOutput Yellow "Could not reliably check for UI.Xaml 2.8: $($_.Exception.Message)" }

        if (-not $xamlInstalled) {
            Write-ColorOutput Green "Installing Winget dependency (UI.Xaml)..."
            $xamlPath = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.x64.appx"
            try {
                Write-ColorOutput Cyan "Downloading UI.Xaml 2.8.6..." # Specify version being downloaded
                Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $xamlPath -EA Stop
                Write-ColorOutput Cyan "Installing UI.Xaml..."
                # This might still fail if resources are locked, but won't fail due to higher version.
                Add-AppxPackage -Path $xamlPath -EA Stop
                Write-ColorOutput Green "UI.Xaml installed successfully."
            }
            catch {
                if ($_.Exception.HResult -eq [int]0x80073D02) { Write-ColorOutput Red "FATAL: Failed UI.Xaml install (0x80073D02) - Resources likely in use." }
                elseif ($_.Exception.HResult -eq [int]0x80073D06) { Write-ColorOutput Yellow "Warning: UI.Xaml install failed (0x80073D06) - Higher version likely present despite check. Continuing..." } # Treat higher version error as non-fatal now
                else { Write-ColorOutput Red "FATAL: Failed UI.Xaml install: $($_.Exception.Message)"; exit 1 }
            }
            finally { Remove-Item -Path $xamlPath -EA SilentlyContinue }
        }

        # --- 3. Check and Install Winget if needed ---
        Write-ColorOutput Cyan "Checking for Winget (Microsoft.DesktopAppInstaller)..."
        try {
            if (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue) {
                Write-ColorOutput Green "Winget (Microsoft.DesktopAppInstaller) is already installed."
                $wingetInstalled = $true # Crucial: Mark as installed so PS7 install can proceed
            }
        }
        catch { Write-ColorOutput Yellow "Could not reliably check for Winget: $($_.Exception.Message)" }

        if (-not $wingetInstalled) {
            Write-ColorOutput Green "Installing Winget package..."
            $wingetBundlePath = Join-Path $env:TEMP "winget.msixbundle"
            try {
                Write-ColorOutput Cyan "Fetching Winget..."; $uri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") } | Select -First 1
                if (-not $uri) { throw "Could not find Winget URI." }
                Write-ColorOutput Cyan "Downloading Winget..."; Start-BitsTransfer -Source $uri -Destination $wingetBundlePath -EA Stop
                Write-ColorOutput Cyan "Installing Winget..."; Add-AppxPackage -Path $wingetBundlePath -EA Stop
                $wingetInstalled = $true; Write-ColorOutput Green "Winget installed successfully."
            }
            catch {
                if ($_.Exception.HResult -eq [int]0x80073CF3) { Write-ColorOutput Red "FATAL: Failed Winget install (0x80073CF3) - Dependency validation failed." }
                else { Write-ColorOutput Red "FATAL: Failed Winget install: $($_.Exception.Message)" }
                exit 1
            }
            finally { Remove-Item -Path $wingetBundlePath -EA SilentlyContinue }
        }        # Attempt PATH update regardless of whether Winget was *just* installed or already present
        $winAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"; if (Test-Path $winAppsPath) { Write-ColorOutput Yellow "Adding/Verifying WinApps in session PATH..."; $env:Path = "$($env:Path.TrimEnd(';'));$winAppsPath" -replace ';+', ';'; Start-Sleep -Seconds 3 }

    }
    else {
        Write-ColorOutput Magenta "Winget install skipped (Not Initial Run)."
        # Still need to check if Winget exists for PowerShell 7 installation
        if (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue) {
            Write-ColorOutput Green "Winget found on system for PowerShell 7 installation."
            $wingetInstalled = $true
        }
        else {
            Write-ColorOutput Yellow "Winget not found on system."
            $wingetInstalled = $false
        }
    }    # --- Install PS7 (only if Winget was found or installed) ---
    Write-ColorOutput Cyan "Checking PowerShell 7 installation status..."

    if ($wingetInstalled) {
        Write-ColorOutput Green "Winget available - proceeding with PowerShell 7 check..."

        if (-not (Get-Command pwsh -EA SilentlyContinue)) {
            Write-ColorOutput Green "PS7 not found. Installing via Winget...";
            try {
                & winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e
                if ($LASTEXITCODE -eq 0) {
                    $psInstallSuccess = $true
                    Write-ColorOutput Green "PS7 installed successfully."
                }
                else {
                    throw "Winget install failed with exit code: $LASTEXITCODE"
                }
            }
            catch { Write-ColorOutput Red "FATAL: 'winget install PS7' failed: $($_.Exception.Message)"; exit 1 }
            # Install NuGet Provider
            $pwshExe = Get-Command pwsh -EA SilentlyContinue; if ($pwshExe) { Start-Process -FilePath $pwshExe.Source -Args "-NoP -Command Install-PackageProvider -Name NuGet -Force -Scope CU" -Wait } else { Write-ColorOutput Red "pwsh.exe not found after install." }
        }
        else { Write-ColorOutput Magenta "PS7 already installed."; $psInstallSuccess = $true }
    }
    else {
        Write-ColorOutput Yellow "Winget was not found or installed. Skipping PS7 installation via Winget."
        # Cannot proceed reliably without PS7 in this script's design
        Write-ColorOutput Red "FATAL: Cannot install PowerShell 7 without Winget. Exiting."        exit 1
    }

    # --- Restart Logic ---
    $RestartNeeded = $InitialRun -and $psInstallSuccess -and (-not $PowerShell7)
    if ($RestartNeeded) {
        Write-ColorOutput Yellow "PowerShell 7 was just installed during Initial Run. Restarting script..."
        $CurrentScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Write-ColorOutput Red "FATAL: Cannot determine script path."; exit 1 }

        # Check if we're being dot-sourced (common in autounattend scenarios)
        $IsDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\s*\.\s+'

        if ($IsDotSourced) {
            Write-ColorOutput Cyan "Detected dot-sourcing context. Using inline restart approach..."
            # Instead of Start-Process + exit, we'll invoke PowerShell 7 directly and wait
            $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # NO -InitialRun
            Write-ColorOutput Cyan "Invoking: pwsh $ArgList"
            try {
                Start-Process pwsh -ArgumentList $ArgList -Wait -ErrorAction Stop
                Write-ColorOutput Green "PowerShell 7 execution completed. Returning from current session."
                return # Use return instead of exit to avoid terminating the calling context
            }
            catch { Write-ColorOutput Red "FATAL: Failed to invoke PS7 process: $($_.Exception.Message)"; throw }
        }
        else {
            Write-ColorOutput Cyan "Detected normal execution context. Using standard restart approach..."
            $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # NO -InitialRun
            Write-ColorOutput Cyan "Starting: pwsh $ArgList"
            try { Start-Process pwsh -ArgumentList $ArgList -ErrorAction Stop; Write-ColorOutput Green "New PS7 process started. Exiting current PS5.1 session."; exit 0 }
            catch { Write-ColorOutput Red "FATAL: Failed to start new PS7 process: $($_.Exception.Message)"; exit 1 }
        }
    }
    else { Write-ColorOutput Cyan "No restart needed or conditions not met." }
    Write-ColorOutput Yellow "--- End of Winget & PowerShell 7 Installation ---"
}
#endregion

#region Installation Functions (Dependencies, Basic, Advanced, etc.)

function InstallNeededForScript {
    # These should run in PS7+ after potential restart
    Write-ColorOutput Magenta "--- Installing Script Prerequisites (jq, wget) ---"
    try {
        Set-PSRepository PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        winget install -h jqlang.jq --accept-source-agreements --accept-package-agreements -e
        winget install -h GerbenBosscher.Wget --accept-source-agreements --accept-package-agreements -e # Corrected ID likely
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
        winget install -h Blizzard.BattleNet --accept-source-agreements --accept-package-agreements -e -l "C:\Program Files\Battle.net\"
        winget install -h WowUp.CF --accept-source-agreements --accept-package-agreements -e
    }

    function poe {
        Write-ColorOutput Cyan "Installing Path of Exile related apps..."
        DownlaodInstallGithub "PoELurker" "C1rdec/Poe-Lurker" "PoeLurkerSetup*.exe"
        DownlaodInstallGithub "AwakenedPoeTrade" "SnosMe/awakened-poe-trade" "Awakened-PoE-Trade-Setup-*.exe"
        winget install -h PathofBuildingCommunity.PathofBuildingCommunity --accept-source-agreements --accept-package-agreements -e
    }

    wow # Call nested function
    poe # Call nested function

    winget install -h Valve.Steam --accept-source-agreements --accept-package-agreements -e
    winget install -h TeamSpeakSystems.TeamSpeakClient.Beta --accept-source-agreements --accept-package-agreements -e
}

function InstallBasicKit {
    Write-ColorOutput Magenta "--- Installing Basic Kit ---"
    winget install -h AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements -e
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

    winget install Microsoft.VisualStudioCode --override "/verysilent /suppressmsgboxes /mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    DownlaodInstallGithub "PowerToys" "microsoft/PowerToys" "PowerToysUserSetup-*-x64.exe"

    winget install -h Audacity.Audacity --accept-source-agreements --accept-package-agreements -e
    winget install -h dotPDN.PaintDotNet --accept-source-agreements --accept-package-agreements -e
    winget install -h Discord.Discord --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Foxit.FoxitReader --accept-source-agreements --accept-package-agreements -e
    winget install -h MediaArea.MediaInfo.GUI --accept-source-agreements --accept-package-agreements -e
    winget install -h Xanashi.Icaros --accept-source-agreements --accept-package-agreements -e --source winget
    winget install -h XP8BSBGQW2DKS0 --accept-source-agreements --accept-package-agreements -e --force
    InstallJdownloader
    winget install -h RevoUninstaller.RevoUninstaller --accept-source-agreements --accept-package-agreements -e
    winget install -h Nvidia.Broadcast --accept-source-agreements --accept-package-agreements -e

    winget install -h Telegram.TelegramDesktop --accept-source-agreements --accept-package-agreements -e
    winget install -h 9N8G7TSCL18R --accept-source-agreements --accept-package-agreements -e
    winget install -h Google.QuickShare --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Mozilla.Firefox.DeveloperEdition --accept-source-agreements --accept-package-agreements -e
    winget install -h Parsec.Parsec --accept-source-agreements --accept-package-agreements -e
    winget install -h 9NCBCSZSJRSB --accept-source-agreements --accept-package-agreements -e
    winget install --id lsd-rs.lsd --accept-package-agreements --accept-source-agreements -e
}

function InstallJdownloader {
    Write-ColorOutput Cyan "Installing JDownloader and configuration..."
    try {
        winget install -h AppWork.JDownloader --accept-source-agreements --accept-package-agreements -e
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
    winget install -h Logitech.GHUB --accept-source-agreements --accept-package-agreements -e # Can be problematic
    winget install -h Microsoft.Sysinternals.ProcessExplorer --accept-source-agreements --accept-package-agreements -e
    winget install -h StefanSundin.Superf4 --accept-source-agreements --accept-package-agreements -e
    winget install -h ArcadeRenegade.SidebarDiagnostics --accept-source-agreements --accept-package-agreements -e
    winget install -h 9NBLGGH4S79B --accept-source-agreements --accept-package-agreements -e
    winget install -h AntibodySoftware.WizTree --accept-source-agreements --accept-package-agreements -e
    winget install -h 9NK1HLWHNP8S --accept-source-agreements --accept-package-agreements -e

    winget install Obsidian.Obsidian --accept-source-agreements --accept-package-agreements -e
    winget install -h Intel.PresentMon --accept-source-agreements --accept-package-agreements -e
    winget install -h Bruno.Bruno --accept-source-agreements --accept-package-agreements -e
    winget install -h qBittorrent.qBittorrent --accept-source-agreements --accept-package-agreements -e
    winget install -h WinSCP.WinSCP --accept-source-agreements --accept-package-agreements -e
    winget install -h voidtools.Everything --accept-source-agreements --accept-package-agreements -e
    winget install -h Nvidia.PhysX --accept-source-agreements --accept-package-agreements -e

    winget install -h UnifiedIntents.UnifiedRemote --accept-source-agreements --accept-package-agreements -e
    winget install -h HandBrake.HandBrake --accept-source-agreements --accept-package-agreements -e
}

function InstallMedia {
    Write-ColorOutput Magenta "--- Installing Media Apps ---"
    winget install -h Jellyfin.JellyfinMediaPlayer --accept-source-agreements --accept-package-agreements -e
    winget install -h XBMCFoundation.Kodi --accept-source-agreements --accept-package-agreements -e
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
    winget install -h Chocolatey.Chocolatey --accept-source-agreements --accept-package-agreements -e
    winget install -h JetBrains.Toolbox --accept-source-agreements --accept-package-agreements -e
    InstallPythonAndPackages # Contains winget installs
    SetupGit # Contains winget installs
    winget install Nvidia.CUDA --accept-source-agreements --accept-package-agreements -e
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
        $installCommand = "winget install -e --id JetBrains.PyCharm.Professional --override `"/S /CONFIG=$tempConfigPath /D=$InstallDir`" --accept-source-agreements --accept-package-agreements"
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
        winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e
        winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e
        winget install -h 9N0DX20HK701 --accept-source-agreements --accept-package-agreements -e # Windows Terminal

        Set-WindowsTerminalAsDefault # Call internal function

        winget install -h JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements -e
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -Force -ErrorAction Stop }
        Install-Module -Name Terminal-Icons -Repository PSGallery -Force -ErrorAction Stop
        Update-Environment
        oh-my-posh font install FiraCode # May require user interaction

        # Install Clink
        winget install -h ChrisLundquist.Clink --accept-source-agreements --accept-package-agreements -e
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
    # Requires Administrator privileges    # Define the common profile content
    $commonProfileContent = @"
# Common settings for PowerShell Profile (All Users, All Hosts)

# Environment Variables
`$env:VIRTUAL_ENV_DISABLE_PROMPT = 1
`$env:POSH_GIT_ENABLED = `$true
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# Oh My Posh Initialization
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/config/krytos.omp.json" | Invoke-Expression
} else {
    Write-Warning "oh-my-posh command not found. Skipping Posh initialization."
}

# Terminal Icons Module Import
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
} else {
    Write-Warning "Terminal-Icons module not found. Skipping import."
}

# Aliases
Set-Alias denv Deactivate -ErrorAction SilentlyContinue

# Functions
function mklink (`$target, `$link) {
    New-Item -Path `$link -ItemType SymbolicLink -Value `$target
}

function venv {
    `$venvDirs = Get-ChildItem -Directory -Path . | Where-Object { `$_.Name -match '^\.?venv' }
    foreach (`$dir in `$venvDirs) {
        `$activatePath = Join-Path `$dir.Name "Scripts\Activate.ps1"
        if (Test-Path `$activatePath) {
            & `$activatePath
            Write-Host "Activated virtual environment in `$(`$dir.FullName)" -ForegroundColor Green
            return
        }
    }
}

function gitclone {
    [CmdletBinding(SupportsShouldProcess = `$true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = `$true, Position = 0, HelpMessage = "The URL of the Git repository to clone.")]
        [string]`$RepositoryUrl,
        [Parameter(Mandatory = `$false, Position = 1, HelpMessage = "Optional: The name or full path for the target directory.")]
        [string]`$TargetDirectoryName
    )

    `$ErrorActionPreferenceBackup = `$ErrorActionPreference
    `$ErrorActionPreference = 'Stop'

    try {
        `$defaultRepoName = (`$RepositoryUrl.Split('/')[-1] -replace '\.git`$', '')
        `$actualTargetNameOrPath = ""
        `$finalPathToCd = ""

        if (`$PSBoundParameters.ContainsKey('TargetDirectoryName')) {
            `$actualTargetNameOrPath = `$TargetDirectoryName
            if ([System.IO.Path]::IsPathRooted(`$TargetDirectoryName)) {
                `$finalPathToCd = `$TargetDirectoryName
            } else {
                `$finalPathToCd = Join-Path -Path (Get-Location).Path -ChildPath `$TargetDirectoryName
            }
        } else {
            `$finalPathToCd = Join-Path -Path (Get-Location).Path -ChildPath `$defaultRepoName
        }

        if (Test-Path -Path `$finalPathToCd -PathType Container) {
            Write-Warning "Target directory '`$finalPathToCd' already exists. Skipping clone and attempting to CD."
        } else {
            `$gitArgs = @("clone", `$RepositoryUrl)
            if (`$PSBoundParameters.ContainsKey('TargetDirectoryName')) {
                `$gitArgs += `$actualTargetNameOrPath
            }
            Write-Host "Attempting to clone '`$RepositoryUrl' into '`$(`$finalPathToCd)'..."
            if (`$PSCmdlet.ShouldProcess(`$RepositoryUrl, "Clone repository")) {
                & git @gitArgs
                Write-Host "Successfully cloned."
            }
        }

        if (Test-Path -Path `$finalPathToCd -PathType Container) {
            Write-Host "Changing directory to '`$finalPathToCd'..."
            if (`$PSCmdlet.ShouldProcess(`$finalPathToCd, "Set Location (cd)")) {
                Set-Location -Path `$finalPathToCd
                Write-Host "Current directory: `$(Get-Location)"
            }
        } else {
            throw "Cloned directory '`$finalPathToCd' not found. Cannot change directory."
        }
    } catch {
        Write-Error "An error occurred: `$(`$_.Exception.Message)"
    } finally {
        `$ErrorActionPreference = `$ErrorActionPreferenceBackup
    }
}

# Auto-activate venv on shell startup
venv

# Terminal prompt enhancements for Windows Terminal
`$Global:__OriginalPrompt = `$function:Prompt

function Global:__Terminal-Get-LastExitCode {
    if (`$? -eq `$True) { return 0 }
    `$LastHistoryEntry = `$(Get-History -Count 1)
    `$IsPowerShellError = `$Error[0].InvocationInfo.HistoryId -eq `$LastHistoryEntry.Id
    if (`$IsPowerShellError) { return -1 }
    return `$LastExitCode
}

function prompt {
    `$gle = `$(__Terminal-Get-LastExitCode);
    `$LastHistoryEntry = `$(Get-History -Count 1)
    if (`$Global:__LastHistoryId -ne -1) {
        if (`$LastHistoryEntry.Id -eq `$Global:__LastHistoryId) {
            `$out += "`e]133;D`a"
        } else {
            `$out += "`e]133;D;`$gle`a"
        }
    }
    `$loc = `$(`$executionContext.SessionState.Path.CurrentLocation);
    `$out += "`e]133;A`$([char]07)";
    `$out += "`e]9;9;`"`$loc`"`$([char]07)";
    `$out += `$Global:__OriginalPrompt.Invoke();
    `$out += "`e]133;B`$([char]07)";
    `$Global:__LastHistoryId = `$LastHistoryEntry.Id
    return `$out
}

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
Write-Host "=== REACHED MAIN EXECUTION BLOCK ===" -ForegroundColor Magenta
Write-Host "About to call InstallAllTheThings function..." -ForegroundColor Magenta
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
