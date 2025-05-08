# TODOs #
# WSL activation and installing WSL and adding .bashrc
# Selection Menu for what to install -> DONE (Basic Implementation)
# Update profile.ps1 (Review content)
# Edit Oh-My-Posh theme: blocks > segments > "type": "executiontime"; change "style": "roundrock" -> "style": "austin"
# Edit Oh-My-Posh theme: blocks > segments > "type": "os"; change -> "template": " {{ if eq .UserName \"kali\"}}Kali at \uF316{{ else if  .WSL }}WSL at {{.Icon}}{{ else }}{{.Icon}}{{ end }} ",
# Add ruff and uv config files: %APPDATA%\ruff\ruff.toml and %APPDATA%\uv\uv.toml
# Add Catppuccin Themes to everything
# Use this script for "Windows Files" theme install: `$host.UI | Add-Member -MemberType ScriptMethod -Name PromptForChoice -Value { $args[3] } -Force; . { iwr -UseBasicParsing https://github.com/catppuccin/windows-files/raw/main/install.ps1 } | iex`

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,
    [switch]$InitialRun = $false
)

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

# Determine if running in PowerShell 7+
$IsPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
Write-ColorOutput Cyan "Running in PowerShell Version: $($PSVersionTable.PSVersion.ToString()) (IsPS7: $IsPowerShell7)"
Write-ColorOutput Cyan "InitialRun flag: $InitialRun"

# Change to user profile directory (Important for relative paths later)
try {
    Set-Location $env:USERPROFILE -ErrorAction Stop
    Write-ColorOutput Cyan "Current Location: $(Get-Location)"
}
catch {
    Write-ColorOutput Red "FATAL: Could not change location to $env:USERPROFILE. Exiting."
    exit 1
}


# Check if the HKCR PSDrive already exists
if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
    Write-ColorOutput Yellow "Creating HKCR PSDrive..."
    try {
        New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" -ErrorAction Stop | Out-Null
    }
    catch {
        Write-ColorOutput Red "FATAL: Could not create HKCR PSDrive. Registry operations might fail. Exiting."
        exit 1
    }
}

# --- GLOBAL STATE for Selections ---
$global:SelectionState = @{
    # Core Functions
    'InstallDependencies'  = $false
    'QoLRegConfigurations' = $false
    'TakeOwnership'        = $false
    'AddRegistryEntries'   = $false
    'StartServices'        = $false
    'TerminalStuff'        = $false

    # Application/Tool Groups
    'InstallBasicKit'      = $false
    'InstallAdvanced'      = $false
    'InstallMedia'         = $false
    'InstallDevTools'      = $false
    'Gaming'               = $false
    'NvidiaSettings'       = $false
}

#region Core Functions (Utility, Winget/PS7 Install)
# ==================================================
# UTILITY FUNCTIONS
# ==================================================
function Write-ColorOutput($ForegroundColor, $Message) {
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Update-Environment {
    Write-ColorOutput Cyan "Attempting to update environment variables for current session..."
    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine", [System.EnvironmentVariableTarget]::Machine)
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User", [System.EnvironmentVariableTarget]::User)
        $env:Path = ($machinePath.TrimEnd(';') + ";" + $userPath.TrimEnd(';')) -replace ';+', ';'
        $env:Path = $env:Path # Reload PATH into current session
        Write-ColorOutput Cyan "Session PATH updated (best effort)."
    }
    catch {
        Write-ColorOutput Yellow "Could not fully update session PATH: $($_.Exception.Message)"
    }
}

function DownlaodInstallGithub($name, $repo, $filePattern) {
    Write-ColorOutput Magenta "--- Installing $name from GitHub ($repo) ---"
    $downloadPath = Join-Path $env:TEMP "$($filePattern.Split('*')[0].TrimEnd('-','.')).exe"
    try {
        Write-ColorOutput Cyan "Fetching latest release info for $repo..."
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -ErrorAction Stop
        $assetUrl = $releaseInfo.assets | Where-Object { $_.name -like $filePattern } | Select-Object -ExpandProperty browser_download_url -First 1
        if (-not $assetUrl) { Write-ColorOutput Red "Could not find asset matching '$filePattern' in the latest release of $repo."; return }
        Write-ColorOutput Green "Downloading $name from $assetUrl..."
        Start-BitsTransfer -Source $assetUrl -Destination $downloadPath -ErrorAction Stop
        if (Test-Path $downloadPath) {
            Write-ColorOutput Green "Download completed. Installing $name silently..."
            Start-Process -FilePath $downloadPath -ArgumentList "/S" -Wait -ErrorAction Stop # Or /VERYSILENT
            Write-ColorOutput Green "$name installation command issued."
        }
        else { Write-ColorOutput Red "Failed to download $name (File not found after BITS transfer)." }
    }
    catch {
        # Use -f format operator for safety
        $errorMessage = "An error occurred during download/install of '{0}': {1}" -f $name, $_.Exception.Message
        Write-ColorOutput Red $errorMessage
    }
    finally {
        Remove-Item -Path $downloadPath -ErrorAction SilentlyContinue
    }
}

# ==================================================
# WINGET & PS7 INSTALL/RESTART (RUNS ONLY IF NEEDED ON PS5.1 START)
# ==================================================
function InstallWingetAndRestartIfInitialRun {
    Write-ColorOutput Yellow "--- Attempting Winget & PowerShell 7 Installation (Initial Run) ---"
    $wingetInstalled = $false
    # REMOVED: $psInstallAttempted = $false
    $psInstallSuccess = $false
    if ($InitialRun.IsPresent) {
        Write-ColorOutput Green "Initial Run: Installing Winget dependencies and Winget..."
        try {
            $xamlPath = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.x64.appx"
            $vcLibsPath = Join-Path $env:TEMP "Microsoft.VCLibs.x64.14.00.Desktop.appx"
            $wingetBundlePath = Join-Path $env:TEMP "winget.msixbundle"
            Write-ColorOutput Cyan "Downloading UI.Xaml..."; Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $xamlPath -ErrorAction Stop
            Write-ColorOutput Cyan "Installing UI.Xaml..."; Add-AppxPackage -Path $xamlPath -ErrorAction Stop
            Write-ColorOutput Cyan "Downloading VCLibs..."; Start-BitsTransfer -Source "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Destination $vcLibsPath -ErrorAction Stop
            Write-ColorOutput Cyan "Installing VCLibs..."; Add-AppxPackage -Path $vcLibsPath -ErrorAction Stop
            Write-ColorOutput Cyan "Fetching latest Winget release..."; $latestWingetMsixBundleUri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") } | Select-Object -First 1
            if (-not $latestWingetMsixBundleUri) { throw "Could not find latest Winget msixbundle URI." }
            Install-PackageProvider -Name NuGet -Force | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -Repository PSGallery | Out-Null
            Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
            # Repair-WinGetPackageManager
            # Write-ColorOutput Cyan "Downloading Winget bundle..."; Start-BitsTransfer -Source $latestWingetMsixBundleUri -Destination $wingetBundlePath -ErrorAction Stop
            # Write-ColorOutput Cyan "Installing Winget bundle..."; Add-AppxPackage -Path $wingetBundlePath -ErrorAction Stop
            $wingetInstalled = $true; Write-ColorOutput Green "Winget installed via Add-AppxPackage successfully."
            $windowsAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
            if (Test-Path $windowsAppsPath) { Write-ColorOutput Yellow "Adding $windowsAppsPath to session PATH..."; $env:Path = "$($env:Path.TrimEnd(';'));$windowsAppsPath" -replace ';+', ';'; Start-Sleep -Seconds 5 }
        }
        catch { Write-ColorOutput Red "FATAL: Failed to install Winget: $($_.Exception.Message)"; exit 1 }
        finally { Remove-Item -Path $xamlPath, $vcLibsPath, $wingetBundlePath -ErrorAction SilentlyContinue }
    }
    else { Write-ColorOutput Magenta "Winget installation skipped (Not Initial Run or already PS7)."; return }

    if ($wingetInstalled) {
        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-ColorOutput Green "PowerShell 7 not found. Attempting installation via Winget..."
            # REMOVED: $psInstallAttempted = $true
            try {
                winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
                $psInstallSuccess = $true; Write-ColorOutput Green "PowerShell 7 installed successfully via Winget."
                Write-ColorOutput Yellow "Ensuring NuGet Package Provider..."; $pwshExe = Get-Command pwsh -EA SilentlyContinue
                if ($pwshExe) { Start-Process -FilePath $pwshExe.Source -ArgumentList "-NoProfile -Command Install-PackageProvider -Name NuGet -Force -Scope CurrentUser" -Wait }
                else { Write-ColorOutput Red "Could not find pwsh.exe after installation." }
            }
            catch { Write-ColorOutput Red "FATAL: 'winget install Microsoft.PowerShell' failed: $($_.Exception.Message)"; exit 1 }
        }
        else {
            Write-ColorOutput Magenta "PowerShell 7 seems to be already installed."
            # Simulate success if already present so restart logic doesn't trigger incorrectly
            $psInstallSuccess = $true
        }
    }

    # Check if PS7 was JUST installed (don't restart if it was already present when script started)
    $RestartNeeded = $InitialRun -and $psInstallSuccess -and (-not $IsPowerShell7)
    if ($RestartNeeded) {
        Write-ColorOutput Yellow "PowerShell 7 was just installed during Initial Run. Restarting script..."
        $CurrentScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Write-ColorOutput Red "FATAL: Cannot determine script path."; exit 1 }
        $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # NO -InitialRun
        Write-ColorOutput Cyan "Starting: pwsh $ArgList"
        try { Start-Process pwsh -ArgumentList $ArgList -ErrorAction Stop; Write-ColorOutput Green "New PS7 process started. Exiting current PS5.1 session."; exit 0 }
        catch { Write-ColorOutput Red "FATAL: Failed to start new PS7 process: $($_.Exception.Message)"; exit 1 }
    }
    else { Write-ColorOutput Cyan "No restart needed or conditions not met." }
    Write-ColorOutput Yellow "--- End of Winget & PowerShell 7 Installation ---"
}
#endregion

#region Installation Functions (Grouped by category)
# ==================================================
# INSTALLATION FUNCTIONS (Must match keys in $global:SelectionState)
# ==================================================
function InstallDependencies {
    [CmdletBinding()] param()
    Write-ColorOutput Magenta "--- Installing Core Dependencies ---"
    winget install -h Microsoft.DotNet.DesktopRuntime.6 --accept-source-agreements --accept-package-agreements -e -i
    winget install -h Microsoft.XNARedist --accept-source-agreements --accept-package-agreements -e -i
    winget install -h Microsoft.VCRedist.2015+.x86 --accept-source-agreements --accept-package-agreements -e -i
    winget install -h Microsoft.VCRedist.2015+.x64 --accept-source-agreements --accept-package-agreements -e -i
}

function QoLRegConfigurations {
    [CmdletBinding()] param()
    # (Function content as previously defined - includes keyboard layout and explorer restart)
    Write-ColorOutput Magenta "--- Applying Quality-of-Life Registry Configs ---"
    try {
        $layoutsToRemove = @("00000809", "00000409"); $preloadPath = "Registry::HKCU:\Keyboard Layout\Preload"; $substitutesPath = "Registry::HKCU:\Keyboard Layout\Substitutes"
        if (Test-Path $substitutesPath) { if (Get-ItemProperty -Path $substitutesPath -Name "00000809" -EA SilentlyContinue) { Remove-ItemProperty -Path $substitutesPath -Name "00000809" -Force; Write-ColorOutput Cyan "Removed Substitute 00000809." } }
        if (Test-Path $preloadPath) {
            $preloadEntries = Get-ItemProperty -Path $preloadPath; $properties = $preloadEntries.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' }
            foreach ($layoutToRemove in $layoutsToRemove) {
                $propToRemove = $properties | Where-Object { $_.Value -eq $layoutToRemove } | Select-Object -First 1
                if ($propToRemove) { Remove-ItemProperty -Path $preloadPath -Name $propToRemove.Name -Force; Write-ColorOutput Cyan "Removed Preload '$($propToRemove.Name)' ('$layoutToRemove')." }
                else { Write-ColorOutput Yellow "Preload '$layoutToRemove' not found." }
            }
            Write-ColorOutput Cyan "`nCurrent Preload entries:"; Get-ItemProperty -Path $preloadPath | Format-List
        }
        else { Write-ColorOutput Yellow "Keyboard Preload registry path not found." }
        Write-ColorOutput Yellow "Restarting Explorer process..."; Stop-Process -Name explorer -Force
    }
    catch { Write-ColorOutput Red "Failed during QoL Registry Config: $($_.Exception.Message)" }
}

function TakeOwnership {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Applying Take Ownership Registry ---"
    try {
        Remove-Item -Path "Registry::HKCR\*\shell\TakeOwnership" -R -Fo -EA SilentlyContinue; Remove-Item -Path "Registry::HKCR\*\shell\runas" -R -Fo -EA SilentlyContinue; Remove-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership" -R -Fo -EA SilentlyContinue; Remove-Item -Path "Registry::HKCR\Drive\shell\runas" -R -Fo -EA SilentlyContinue
        New-Item -Path "Registry::HKCR\*\shell\TakeOwnership" -Fo -EA Stop | Out-Null; Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -N "(Default)" -V "Take Ownership"-EA Stop; New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -N "HasLUAShield" -Ty String -V "" -Fo -EA Stop; New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -N "NoWorkingDirectory" -Ty String -V "" -Fo -EA Stop; New-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership" -N "NeverDefault" -Ty String -V "" -Fo -EA Stop; New-Item -Path "Registry::HKCR\*\shell\TakeOwnership\command" -Fo -EA Stop | Out-Null; $cmdValF = 'powershell -windowstyle hidden -command "Start-Process cmd -ArgumentList ''/c takeown /f \""%1\"" && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l'' -Verb runAs"'; Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership\command" -N "(Default)" -V $cmdValF -EA Stop; Set-ItemProperty -Path "Registry::HKCR\*\shell\TakeOwnership\command" -N "IsolatedCommand" -V $cmdValF -EA Stop
        New-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership" -Fo -EA Stop | Out-Null; Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -N "(Default)" -V "Take Ownership"-EA Stop; $appTo = 'NOT (System.ItemPathDisplay:="C:\Users" OR System.ItemPathDisplay:="C:\ProgramData" OR System.ItemPathDisplay:="C:\Windows" OR System.ItemPathDisplay:="C:\Windows\System32" OR System.ItemPathDisplay:="C:\Program Files" OR System.ItemPathDisplay:="C:\Program Files (x86)")'; Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -N "AppliesTo" -V $appTo -EA Stop; New-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -N "HasLUAShield" -Ty String -V "" -Fo -EA Stop; New-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -N "NoWorkingDirectory" -Ty String -V "" -Fo -EA Stop; Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership" -N "Position" -V "middle"-EA Stop; New-Item -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -Fo -EA Stop | Out-Null; $cmdValD = 'powershell -windowstyle hidden -command "$Y = ($null | choice).Substring(1,1); Start-Process cmd -ArgumentList (''/c takeown /f \""%1\"" /r /d '' + $Y + '' && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l /q'') -Verb runAs"'; Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -N "(Default)" -V $cmdValD -EA Stop; Set-ItemProperty -Path "Registry::HKCR\Directory\shell\TakeOwnership\command" -N "IsolatedCommand" -V $cmdValD -EA Stop
        New-Item -Path "Registry::HKCR\Drive\shell\runas" -Fo -EA Stop | Out-Null; Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -N "(Default)" -V "Take Ownership"-EA Stop; New-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -N "HasLUAShield" -Ty String -V "" -Fo -EA Stop; New-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -N "NoWorkingDirectory" -Ty String -V "" -Fo -EA Stop; Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -N "Position" -V "middle"-EA Stop; Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas" -N "AppliesTo" -V 'NOT (System.ItemPathDisplay:="C:\")'-EA Stop; New-Item -Path "Registry::HKCR\Drive\shell\runas\command" -Fo -EA Stop | Out-Null; $cmdValDrv = 'cmd.exe /c takeown /f "%1\" /r /d y && icacls "%1\" /grant *S-1-3-4:F /t /c'; Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas\command" -N "(Default)" -V $cmdValDrv -EA Stop; Set-ItemProperty -Path "Registry::HKCR\Drive\shell\runas\command" -N "IsolatedCommand" -V $cmdValDrv -EA Stop
        Write-ColorOutput Green "Take Ownership registry entries applied successfully."
    }
    catch { Write-ColorOutput Red "Failed to apply Take Ownership registry: $($_.Exception.Message)" }
}

function AddRegistryEntries {
    [CmdletBinding()] param()
    # (Function content as previously defined - WizTree example)
    Write-ColorOutput Magenta "--- Applying Other Registry Entries (WizTree) ---"
    try {
        $wizTreeExe = "C:\Program Files\WizTree\WizTree64.exe"
        if (Test-Path $wizTreeExe) {
            $regPathCommand = "Registry::HKLM\SOFTWARE\Classes\*\shell\WizTree\command"; $regPathIcon = "Registry::HKLM\SOFTWARE\Classes\*\shell\WizTree"
            New-Item -Path $regPathIcon -Fo -EA Stop | Out-Null; New-Item -Path $regPathCommand -Fo -EA Stop | Out-Null
            Set-ItemProperty -Path $regPathCommand -N "(Default)" -V "`"$wizTreeExe`" `"%1`"" -EA Stop; Set-ItemProperty -Path $regPathIcon -N "Icon" -V "`"$wizTreeExe`",0" -EA Stop
            Write-ColorOutput Green "WizTree context menu entry added."
        }
        else { Write-ColorOutput Yellow "WizTree not found at '$wizTreeExe'. Skipping context menu." }
    }
    catch { Write-ColorOutput Red "Failed to add WizTree registry entry: $($_.Exception.Message)" }
}

function StartServices {
    [CmdletBinding()] param()
    # (Function content as previously defined - SSH Agent example)
    Write-ColorOutput Magenta "--- Configuring Services (SSH Agent) ---"
    $services = @("ssh-agent")
    foreach ($serviceName in $services) {
        try {
            $service = Get-Service $serviceName -EA Stop
            if ($service.Status -ne 'Running') { Write-ColorOutput Cyan "Setting '$serviceName' auto & starting..."; Set-Service -Name $serviceName -StartupType Automatic -EA Stop; Start-Service -Name $serviceName -EA Stop; Write-ColorOutput Green "'$serviceName' started." }
            else { Write-ColorOutput Green "'$serviceName' already running."; if ($service.StartType -ne 'Automatic') { Write-ColorOutput Cyan "Setting '$serviceName' auto..."; Set-Service -Name $serviceName -StartupType Automatic -EA Stop } }
        }
        catch { Write-ColorOutput Red "Failed service '$serviceName': $($_.Exception.Message)" }
    }
}

function TerminalStuff {
    [CmdletBinding()] param()
    # (Function content as previously defined - Git, GH CLI, WT, Posh, Icons, Font, Clink, Profiles, Settings)
    Write-ColorOutput Magenta "--- Setting Up Terminal Environment ---"
    InstallNeededForScript # Install jq, wget first
    try {
        winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
        winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
        winget install -h 9N0DX20HK701 --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop # Windows Terminal
        Set-WindowsTerminalAsDefault
        winget install -h JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
        if (-not (Get-PackageProvider -Name NuGet -EA SilentlyContinue)) { Install-PackageProvider -Name NuGet -Force -EA Stop }
        Install-Module -Name Terminal-Icons -Repository PSGallery -Force -ErrorAction Stop; Update-Environment
        oh-my-posh font install FiraCode
        winget install -h ChrisLundquist.Clink --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
        $clinkPath = "C:\Program Files (x86)\clink"; if (Test-Path $clinkPath) { Write-ColorOutput Cyan "Adding Clink path..."; $env:Path = "$($env:Path.TrimEnd(';'));$clinkPath" -replace ';+', ';'; try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c clink set clink.logo none" -Wait -WindowStyle Hidden } catch { Write-ColorOutput Yellow "Clink set failed: $($_.Exception.Message)" }; $clinkCfgDir = Join-Path $env:LOCALAPPDATA "clink"; New-Item -Path $clinkCfgDir -ItemType Directory -Force -EA SilentlyContinue; $lua = "load(io.popen('oh-my-posh init cmd --config=""$env:POSH_THEMES_PATH\jandedobbeleer.omp.json""'):read(""*a""))()"; Set-Content -Path (Join-Path $clinkCfgDir "oh-my-posh.lua") -V $lua -EA Stop } else { Write-ColorOutput Yellow "Clink path not found." }
        PowerShellProfileSettings # Now uses AllUsersAllHosts logic
        $wtSettingsDest = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"; Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/terminal-settings.json" -Destination $wtSettingsDest -EA Stop; Write-ColorOutput Green "Terminal settings downloaded."
        SetupGit # Needs GitHubToken potentially
    }
    catch { Write-ColorOutput Red "Error during Terminal setup: $($_.Exception.Message)" }
}

function InstallBasicKit {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Installing Basic Kit ---"
    winget install -h AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
    try { Write-ColorOutput Cyan "Installing uv..."; powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" } catch { Write-ColorOutput Red "Failed uv install: $($_.Exception.Message)" }
    $uvPath = Join-Path $env:USERPROFILE ".local\bin"; if (Test-Path $uvPath) { Write-ColorOutput Cyan "Adding uv path..."; $env:PATH = "$uvPath;$env:PATH" } else { Write-ColorOutput Yellow "uv path not found." }
    winget install Microsoft.VisualStudioCode --override "/verysilent /suppressmsgboxes /mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" -e --disable-interactivity --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    DownlaodInstallGithub "PowerToys" "microsoft/PowerToys" "PowerToysUserSetup-*-x64.exe"
    winget install -h Audacity.Audacity -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h dotPDN.PaintDotNet -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Discord.Discord -e --disable-interactivity --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Foxit.FoxitReader -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h MediaArea.MediaInfo.GUI -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Xanashi.Icaros -e --source winget --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h XP8BSBGQW2DKS0 -e --force --accept-source-agreements --accept-package-agreements --ErrorAction Stop # PotPlayer
    InstallJdownloader
    winget install -h RevoUninstaller.RevoUninstaller -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Nvidia.Broadcast -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Telegram.TelegramDesktop -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h 9N8G7TSCL18R -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop # NanaZip
    winget install -h Google.QuickShare -e --disable-interactivity --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Mozilla.Firefox.DeveloperEdition -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Parsec.Parsec -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h 9NCBCSZSJRSB -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop # Spotify
    winget install --id lsd-rs.lsd -e --accept-package-agreements --accept-source-agreements --ErrorAction Stop
}

function InstallAdvanced {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Installing Advanced Kit ---"
    winget install -h Logitech.GHUB -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Microsoft.Sysinternals.ProcessExplorer -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h StefanSundin.Superf4 -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h ArcadeRenegade.SidebarDiagnostics -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h 9NBLGGH4S79B -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h AntibodySoftware.WizTree -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h 9NK1HLWHNP8S -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install Obsidian.Obsidian -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Intel.PresentMon -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Bruno.Bruno -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h qBittorrent.qBittorrent -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h WinSCP.WinSCP -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h voidtools.Everything -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h Nvidia.PhysX -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h UnifiedIntents.UnifiedRemote -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
    winget install -h HandBrake.HandBrake -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop
}

function InstallMedia {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Installing Media Apps ---"
    winget install -h Jellyfin.JellyfinMediaPlayer --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
    winget install -h XBMCFoundation.Kodi --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function InstallDevTools {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Installing Developer Tools ---"
    winget install -h Chocolatey.Chocolatey --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
    winget install -h JetBrains.Toolbox --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
    InstallPythonAndPackages
    # SetupGit called within TerminalStuff
    winget install Nvidia.CUDA --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function Gaming {
    [CmdletBinding()] param()
    # (Function content as previously defined)
    Write-ColorOutput Magenta "--- Installing Gaming Apps ---"
    function wow { Write-ColorOutput Cyan "Installing WoW..."; winget install -h Blizzard.BattleNet -e -l "C:\Program Files\Battle.net\" --accept-source-agreements --accept-package-agreements --ErrorAction Stop; winget install -h WowUp.CF -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop }
    function poe { Write-ColorOutput Cyan "Installing PoE..."; DownlaodInstallGithub "PoELurker" "C1rdec/Poe-Lurker" "PoeLurkerSetup*.exe"; DownlaodInstallGithub "AwakenedPoeTrade" "SnosMe/awakened-poe-trade" "Awakened-PoE-Trade-Setup-*.exe"; winget install -h PathofBuildingCommunity.PathofBuildingCommunity -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop }
    wow; poe
    winget install -h Valve.Steam --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
    winget install -h TeamSpeakSystems.TeamSpeakClient.Beta --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
}

function NvidiaSettings {
    [CmdletBinding()] param()
    # --- FIX HERE: Corrected Here-String Syntax ---
    Write-ColorOutput Magenta "--- Applying NVIDIA Overlay Settings ---"
    try {
        $overlayBaseDir = Join-Path $env:LOCALAPPDATA "NVIDIA Corporation\NVIDIA Overlay"
        $gallerySettingsPath = Join-Path $overlayBaseDir "GallerySettings.json"
        $shareSettingsPath = Join-Path $overlayBaseDir "ShareSettings.json"

        if (-not (Test-Path $overlayBaseDir)) { New-Item -Path $overlayBaseDir -ItemType Directory -Force }

        # Corrected: Content starts on the next line
        $gallery_settings = @"
{
    "settings": { "capEnabled": false, "capSizePercent": 100, "currentDirectoryV2": "D:\\Recording\\RAW",
                  "tempDirectory": "$($env:LOCALAPPDATA.Replace('\','\\'))\\Temp\\", "trackerUpdateState": "TrackerUpdateComplete" }
}
"@ # Corrected: Closing @" is at the start of the line

        # Corrected: Content starts on the next line
        $share_settings = @"
{ "settings": {
    "shortcuts": { "OpenIGO": [ 18, 17, 78 ], "Screenshot": [ 0 ], "PMOCOverlay": [ 18, 121 ], "OpenFreestyle": [ 0 ], "RecordToggle": [ 17, 117 ], "OpenAnsel": [ 0 ], "DVRSave": [ 18, 117 ], "DVRToggle": [ 17, 18, 117 ], "MicToggle": [ 0 ], "PTT": [ 0 ], "FreeStyleToggleStyle1": [], "FreeStyleToggleStyle2": [], "FreeStyleToggleStyle3": [], "PMOCOverlayVisibility": [ 0 ], "PMOCOverlayCycle": [ 17, 121 ], "PMOCResetAverageMetrics": [], "PMOCLoggingToggle": [] },
    "globalhighlights": { "enabled": true }, "video": { "irEnabled": false, "irBufferLength": 180 }, "micmode": { "mode": "on" } } }
"@ # Corrected: Closing @" is at the start of the line

        Set-Content -Path $gallerySettingsPath -Value $gallery_settings -Encoding UTF8 -Force -ErrorAction Stop
        Set-Content -Path $shareSettingsPath -Value $share_settings -Encoding UTF8 -Force -ErrorAction Stop
        Write-ColorOutput Green "NVIDIA Overlay Gallery and Share settings applied."

    }
    catch { Write-ColorOutput Red "Failed to apply NVIDIA settings: $($_.Exception.Message)" }
}

#endregion

#region Helper Functions (Internal Use)
# Functions like InstallPythonAndPackages, Install-PyCharm, SetupGit, LoginGitHubCLI, PowerShellProfileSettings, Set-WindowsTerminalAsDefault, InstallJdownloader etc.
# (These functions are called by the main installation functions above)
# Ensure they are defined before being called or place them logically within the script flow.
# We keep them as previously defined, including the corrected AllUsersAllHosts profile logic.

function InstallPythonAndPackages {
    Write-ColorOutput Cyan "--- Installing Python Versions and Tools via uv ---"
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-ColorOutput Red "uv command not found. Skipping Python/Tool installation."
        return
    }
    $pythonTools = @("hashcat", "ipython", "nuitka", "ruff", "pyright")
    foreach ($tool in $pythonTools) {
        Write-ColorOutput Cyan "Installing tool '$tool'..."
        try {
            uv tool install $tool
        }
        catch {
            # Use -f format operator
            $errorMessage = "Failed tool '{0}': {1}" -f $tool, $_.Exception.Message
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
    Install-PyCharm -SkipPyFileAssociation
}

function Install-PyCharm {
    param ( [string]$InstallDir = "C:\Program Files\JetBrains\PyCharm", [switch]$SkipAddToPath, [switch]$SkipContextMenu, [switch]$SkipPyFileAssociation )
    Write-ColorOutput Cyan "Installing PyCharm Professional..."; $tempConfigPath = [System.IO.Path]::Combine($env:TEMP, "pycharm_install.config"); $configContent = @"
mode=admin; launcher32=0; launcher64=1; updatePATH=$(if (-not $SkipAddToPath.IsPresent){"1"}else{"0"}); updateContextMenu=$(if (-not $SkipContextMenu.IsPresent){"1"}else{"0"}); jre32=0; regenerationSharedArchive=1; `.py`=$(if (-not $SkipPyFileAssociation.IsPresent){"1"}else{"0"})
"@ # Compacted slightly
    try { Set-Content -Path $tempConfigPath -Value $configContent -Encoding ASCII -Force -EA Stop; $installCmd = "winget install -e --id JetBrains.PyCharm.Professional --override `"/S /CONFIG=$tempConfigPath /D=$InstallDir`" --accept-source-agreements --accept-package-agreements --ErrorAction Stop"; Write-ColorOutput Cyan "Running: $installCmd"; Invoke-Expression $installCmd; Write-ColorOutput Green "PyCharm command issued." }
    catch { Write-ColorOutput Red "Failed PyCharm install: $($_.Exception.Message)" } finally { Remove-Item -Path $tempConfigPath -Force -EA SilentlyContinue }
}

function SetupGit {
    Write-ColorOutput Magenta "--- Setting Up Git ---"
    if (-not (Get-Command git -EA SilentlyContinue)) { Write-ColorOutput Red "Git not found."; return }
    try { git config --global user.email "kmeinon@gmail.com"; git config --global user.name "Kevin Meinon"; git config --global --add safe.directory '*'; Write-ColorOutput Green "Git user configured."; LoginGitHubCLI -Token $GitHubToken -EA Stop }
    catch { Write-ColorOutput Red "Failed Git setup: $($_.Exception.Message)" }
}

function LoginGitHubCLI {
    param ( [Parameter(Mandatory = $true)][string]$Token )
    Write-ColorOutput Cyan "Attempting GitHub CLI auth..."; if (-not (Get-Command gh -EA SilentlyContinue)) { Write-ColorOutput Red "gh not found."; return }
    try { $output = $Token | gh auth login --hostname "github.com" --with-token --git-protocol https 2>&1; if ($output -match 'Authentication successful' -or $output -match 'Already logged in') { Write-ColorOutput Green "GitHub CLI auth successful." } else { Write-ColorOutput Red "GitHub CLI auth failed: $output" } }
    catch { Write-ColorOutput Red "Error running gh: $($_.Exception.Message)" }
}

function PowerShellProfileSettings {
    Write-ColorOutput Magenta "--- Configuring PowerShell Profiles (All Users, All Hosts) ---"
    $commonProfileContent = @"
# Common settings for PowerShell Profile (All Users, All Hosts)
if (Get-Command oh-my-posh -EA SilentlyContinue) {
    `$themePath = Join-Path `$env:POSH_THEMES_PATH "jandedobbeleer.omp.json"
    if (Test-Path `$themePath) { oh-my-posh init pwsh --config "`$themePath" | Invoke-Expression }
    else { Write-Warning "Posh theme not found: `$themePath" }
} else { Write-Warning "oh-my-posh not found." }
if (Get-Module -ListAvailable -Name Terminal-Icons) { Import-Module -Name Terminal-Icons }
else { Write-Warning "Terminal-Icons not found." }
Set-Alias denv Deactivate -EA SilentlyContinue -Scope Global
function mklink (`$target, `$link) { New-Item -Path `$link -ItemType SymbolicLink -Value `$target -EA Stop }
"@
    $ps5ProfilePath = Join-Path $PSHOME "profile.ps1"
    $ps7ProfilePath = ""; $pwshExe = Get-Command pwsh -EA SilentlyContinue; if ($pwshExe) { $ps7InstallDir = Split-Path $pwshExe.Source -Parent; $ps7ProfilePath = Join-Path $ps7InstallDir "profile.ps1" } else { Write-ColorOutput Yellow "pwsh.exe not found." }
    Write-ColorOutput Cyan "Configuring PS 5.1 profile: $ps5ProfilePath"; try { $ps5Dir = Split-Path $ps5ProfilePath -Parent; if (-not (Test-Path $ps5Dir)) { New-Item -Path $ps5Dir -ItemType Directory -Force -EA Stop }; Set-Content -Path $ps5ProfilePath -Value $commonProfileContent -Force -Encoding UTF8 -EA Stop; Write-ColorOutput Green "PS 5.1 profile configured." } catch { Write-ColorOutput Red "Failed PS 5.1 profile: $($_.Exception.Message)" }
    if ($ps7ProfilePath -and (Test-Path (Split-Path $ps7ProfilePath -Parent))) { Write-ColorOutput Cyan "Configuring PS 7+ profile: $ps7ProfilePath"; try { Set-Content -Path $ps7ProfilePath -Value $commonProfileContent -Force -Encoding UTF8 -EA Stop; Write-ColorOutput Green "PS 7+ profile configured." } catch { Write-ColorOutput Red "Failed PS 7+ profile: $($_.Exception.Message)" } }
    elseif ($pwshExe) { Write-ColorOutput Yellow "Cannot write PS 7+ profile to '$ps7ProfilePath'." }
    Write-ColorOutput Magenta "--- Finished Configuring Profiles ---"
}

function Set-WindowsTerminalAsDefault {
    Write-ColorOutput Cyan "Setting WT as default console..."; try { if (-not (Get-Command wt -EA SilentlyContinue)) { Write-ColorOutput Yellow "wt.exe not found."; return }; $regPath = "Registry::HKCU\Console"; if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Fo | Out-Null }; if (-not (Test-Path "$regPath\%%Startup")) { New-Item -Path "$regPath\%%Startup" -Fo | Out-Null }; New-ItemProperty -Path "$regPath\%%Startup" -N "DelegationConsole" -V "{00000000-0000-0000-0000-000000000000}" -Ty String -Fo -EA Stop; New-ItemProperty -Path "$regPath\%%Startup" -N "DelegationTerminal" -V "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -Ty String -Fo -EA Stop; Write-ColorOutput Green "WT set as default (Registry)." }
    catch { Write-ColorOutput Red "Failed setting WT default: $($_.Exception.Message)" }
}

function InstallJdownloader {
    Write-ColorOutput Cyan "Installing JDownloader..."; try { winget install -h AppWork.JDownloader -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop; $cfgDest = "C:\Program Files\JDownloader\cfg\org.jdownloader.controlling.filter.LinkFilterSettings.filterlist.json"; if (Test-Path (Split-Path $cfgDest)) { Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/jdownloader.json" -Destination $cfgDest -EA Stop; Write-ColorOutput Green "JDownloader config applied." } else { Write-ColorOutput Yellow "JDownloader dir not found." } }
    catch { Write-ColorOutput Red "Failed JDownloader: $($_.Exception.Message)" }
}

function InstallNeededForScript {
    Write-ColorOutput Magenta "--- Installing Script Prerequisites (jq, wget) ---"; try { Set-PSRepository PSGallery -InstallationPolicy Trusted -EA Stop; winget install -h jqlang.jq -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop; winget install -h GerbenBosscher.Wget -e --accept-source-agreements --accept-package-agreements --ErrorAction Stop }
    catch { Write-ColorOutput Red "Failed prerequisites: $($_.Exception.Message)" }
}
#endregion

#region Selection Menu Logic
# ==================================================
# INTERACTIVE SELECTION MENU FUNCTIONS
# ==================================================
function Show-SelectionMenu {
    [CmdletBinding()] param()
    $groups = @{
        '1' = @{ Name = 'Basic'; Description = 'Core Utils, Dependencies, Basic Apps (Highly Recommended)'; Functions = @('InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit') }
        '2' = @{ Name = 'Dev'; Description = 'Basic + Developer Tools (Python, JetBrains, Choco, CUDA)'; Functions = @('InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'InstallDevTools') }
        '3' = @{ Name = 'Gaming'; Description = 'Basic + Gaming Launchers/Tools, Nvidia Config'; Functions = @('InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'Gaming', 'NvidiaSettings') }
        '4' = @{ Name = 'Media'; Description = 'Basic + Media Players (Kodi, Jellyfin)'; Functions = @('InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'InstallMedia') }
        '5' = @{ Name = 'Advanced'; Description = 'Basic + Advanced Utilities (WizTree, Everything, GHUB etc.)'; Functions = @('InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'InstallAdvanced') }
        'A' = @{ Name = 'All'; Description = 'Install Everything Defined'; Functions = $global:SelectionState.Keys }
        'C' = @{ Name = 'Custom'; Description = 'Manually select components'; Functions = @() } # Handled specially
        'X' = @{ Name = 'Exit'; Description = 'Exit without installing'; Functions = @() }
    }
    $global:SelectionState.Keys | ForEach-Object { $global:SelectionState[$_] = $false } # Clear previous
    while ($true) {
        Clear-Host; Write-ColorOutput Yellow "--- Installation Profile Selection ---"; $groups.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("[{0}] {1,-10} - {2}" -f $_.Name, $_.Value.Name, $_.Value.Description) }; Write-ColorOutput Yellow "--------------------------------------"; $choice = Read-Host "Enter selection (e.g., 1, A, C, X)"
        if ($groups.ContainsKey($choice.ToUpper())) {
            $selectedGroupKey = $choice.ToUpper(); $selectedGroup = $groups[$selectedGroupKey]; Write-ColorOutput Cyan "`nYou selected: $($selectedGroup.Name)"
            if ($selectedGroupKey -eq 'X') { Write-ColorOutput Yellow "Exiting script."; return $false }
            if ($selectedGroupKey -eq 'C') { Show-CustomSelectionMenu; return $true }
            foreach ($funcName in $selectedGroup.Functions) { if ($global:SelectionState.ContainsKey($funcName)) { $global:SelectionState[$funcName] = $true } else { Write-ColorOutput Yellow "Warn: Func '$funcName' in group '$($selectedGroup.Name)' not found." } }
            Write-ColorOutput Green "Selected for '$($selectedGroup.Name)':"; $global:SelectionState.GetEnumerator() | Where-Object { $_.Value -eq $true } | ForEach-Object { Write-Host (" - $($_.Name)") }; Write-Host ""
            $customize = Read-Host "Customize this selection? (Y/N)"; if ($customize -match '^y') { Show-CustomSelectionMenu }
            return $true
        }
        else { Write-ColorOutput Red "Invalid selection."; Start-Sleep -Seconds 2 }
    }
}

function Show-CustomSelectionMenu {
    [CmdletBinding()] param()
    while ($true) {
        Clear-Host; Write-ColorOutput Yellow "--- Custom Component Selection ---"; Write-Host "Enter number to toggle, A=All, N=None, D=Done"; Write-ColorOutput Yellow "----------------------------------"; $i = 1; $componentKeys = $global:SelectionState.Keys | Sort-Object; $keyMap = @{}
        foreach ($key in $componentKeys) { $status = if ($global:SelectionState[$key]) { "[X]" } else { "[ ]" }; Write-Host ("[{0,2}] {1,-25} {2}" -f $i, $key, $status); $keyMap[$i] = $key; $i++ }; Write-ColorOutput Yellow "----------------------------------"; $choice = Read-Host "Enter selection"
        if ($choice -match '^\d+$' -and $keyMap.ContainsKey([int]$choice)) { $selectedKey = $keyMap[[int]$choice]; $global:SelectionState[$selectedKey] = -not $global:SelectionState[$selectedKey] }
        elseif ($choice -match '^a') { $componentKeys | ForEach-Object { $global:SelectionState[$_] = $true } }
        elseif ($choice -match '^n') { $componentKeys | ForEach-Object { $global:SelectionState[$_] = $false } }
        elseif ($choice -match '^d') { Write-ColorOutput Green "Custom selection complete."; Start-Sleep -Seconds 1; return }
        else { Write-ColorOutput Red "Invalid input."; Start-Sleep -Seconds 1 }
    }
}

# --- FIX HERE: Renamed function to use approved verb 'Invoke' ---
function Invoke-SelectedFunctions {
    [CmdletBinding()] param() # Uses $global:SelectionState
    Write-ColorOutput Magenta "--- Executing Selected Installation Steps ---"; $somethingSelected = $false
    $appGroupsSelected = $global:SelectionState['InstallBasicKit'] -or $global:SelectionState['InstallAdvanced'] -or $global:SelectionState['InstallMedia'] -or $global:SelectionState['InstallDevTools'] -or $global:SelectionState['Gaming']
    if ($appGroupsSelected -and (-not $global:SelectionState['InstallDependencies'])) { Write-ColorOutput Yellow "Dependencies required. Enabling 'InstallDependencies'."; $global:SelectionState['InstallDependencies'] = $true }
    if (($global:SelectionState['InstallDevTools'] -or $global:SelectionState['Gaming']) -and (-not $global:SelectionState['TerminalStuff'])) { Write-ColorOutput Yellow "Terminal setup recommended. Enabling 'TerminalStuff'."; $global:SelectionState['TerminalStuff'] = $true }
    $executionOrder = @( 'InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'InstallAdvanced', 'InstallMedia', 'InstallDevTools', 'Gaming', 'NvidiaSettings' )
    foreach ($funcName in $executionOrder) {
        if ($global:SelectionState.ContainsKey($funcName) -and $global:SelectionState[$funcName]) {
            $somethingSelected = $true; Write-ColorOutput Cyan "==> Executing Function: $funcName <=="
            try { if (Get-Command $funcName -EA SilentlyContinue) { & $funcName -ErrorAction Stop } else { Write-ColorOutput Red "Error: Func '$funcName' selected but not defined." } }
            catch { Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!! ERROR in '$funcName': $($_.Exception.ToString()) !!!!!!!!!!!!!!!!!!!"; }
            Write-ColorOutput Cyan "==> Finished Function: $funcName <=="; Write-Host ""
        }
    }
    if (-not $somethingSelected) { Write-ColorOutput Yellow "No components were selected for installation." }
}
#endregion

# --- Main Script Execution Flow ---
# 1. Ensure PowerShell 7 if starting in PS5.1 during InitialRun
if (-not $IsPowerShell7 -and $InitialRun) {
    InstallWingetAndRestartIfInitialRun
    Write-ColorOutput Red "Script continued after Winget/PS7 install attempt in PS5.1 - Indicates failure. Exiting."; exit 1
}
# 2. Check if running in PowerShell 7+ now
if (-not $IsPowerShell7) { $IsPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7; if (-not $IsPowerShell7) { Write-ColorOutput Red "FATAL: Not in PS7+ and restart failed. Cannot continue."; exit 1 } }

# 3. Show Selection Menu
$selectionMade = Show-SelectionMenu
if (-not $selectionMade) { Write-ColorOutput Yellow "Exiting based on user selection."; exit 0 }

# 4. Execute based on selection
try {
    # --- FIX HERE: Call the renamed function ---
    Invoke-SelectedFunctions -ErrorAction Stop
    Write-ColorOutput Green "##############################################"
    Write-ColorOutput Green "Selected installations and configurations completed."
    Write-ColorOutput Green "##############################################"
}
catch {
    Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; Write-ColorOutput Red "An UNHANDLED ERROR occurred during the execution phase:"; Write-ColorOutput Red $_.Exception.ToString(); Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; exit 1
}

exit 0 # Explicitly exit with success code