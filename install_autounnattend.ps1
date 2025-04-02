# TODOs #
# ... (your todos) ...

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,
    [switch]$InitialRun = $false
)

# ==================================================
# UTILITY FUNCTIONS (Define BEFORE use)
# ==================================================
function Write-ColorOutput($ForegroundColor, $Message) {
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# ==================================================
# GLOBAL STATE
# ==================================================
$global:TerminalAlreadyInstalled = $false # Flag to check if Terminal is inbox
$global:SelectionState = @{ # State for interactive selection
    # Core Functions
    'InstallDependencies' = $false; 'QoLRegConfigurations' = $false; 'TakeOwnership' = $false
    'AddRegistryEntries' = $false; 'StartServices' = $false; 'TerminalStuff' = $false
    # Application/Tool Groups
    'InstallBasicKit' = $false; 'InstallAdvanced' = $false; 'InstallMedia' = $false
    'InstallDevTools' = $false; 'Gaming' = $false; 'NvidiaSettings' = $false
}

# ==================================================
# MAIN SCRIPT LOGIC STARTS HERE
# ==================================================
# Determine if running in PowerShell 7+
$IsPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
Write-ColorOutput Cyan "Running in PowerShell Version: $($PSVersionTable.PSVersion.ToString()) (IsPS7: $IsPowerShell7)"
Write-ColorOutput Cyan "InitialRun flag: $InitialRun"

# Change to user profile directory
try { Set-Location $env:USERPROFILE -EA Stop; Write-ColorOutput Cyan "Current Location: $(Get-Location)" }
catch { Write-ColorOutput Red "FATAL: Could not change location to $env:USERPROFILE. Exiting."; exit 1 }

# Check for HKCR drive
if (-not (Get-PSDrive -Name HKCR -EA SilentlyContinue)) { Write-ColorOutput Yellow "Creating HKCR PSDrive..."; try { New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" -EA Stop | Out-Null } catch { Write-ColorOutput Red "FATAL: Could not create HKCR PSDrive."; exit 1 } }


#region Core Functions (Utility, Winget/PS7 Install, etc.)
# ... (Keep Update-Environment and DownlaodInstallGithub functions here as before) ...
function Update-Environment {
    Write-ColorOutput Cyan "Attempting to update environment variables for current session..."
    try {
         $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine", [System.EnvironmentVariableTarget]::Machine)
         $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User", [System.EnvironmentVariableTarget]::User)
         $env:Path = ($machinePath.TrimEnd(';') + ";" + $userPath.TrimEnd(';')) -replace ';+', ';'
         $env:Path = $env:Path # Reload PATH into current session
         Write-ColorOutput Cyan "Session PATH updated (best effort)."
    } catch {
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
        } else { Write-ColorOutput Red "Failed to download $name (File not found after BITS transfer)." }
    } catch {
        $errorMessage = "An error occurred during download/install of '{0}': {1}" -f $name, $_.Exception.Message
        Write-ColorOutput Red $errorMessage
    } finally {
        Remove-Item -Path $downloadPath -ErrorAction SilentlyContinue
    }
}

# ==================================================
# WINGET & PS7 INSTALL/RESTART (RUNS ONLY IF NEEDED ON PS5.1 START)
# ==================================================
function InstallWingetAndRestartIfInitialRun {
     Write-ColorOutput Yellow "--- Attempting Winget & PowerShell 7 Installation (Initial Run) ---"
    $wingetInstalled = $false
    $psInstallSuccess = $false

    # --- Check for pre-installed Terminal FIRST ---
    Write-ColorOutput Cyan "Checking for existing Windows Terminal installation..."
    try {
        if (Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue) {
            Write-ColorOutput Green "Windows Terminal appears to be pre-installed."
            $global:TerminalAlreadyInstalled = $true
        } else {
            Write-ColorOutput Yellow "Windows Terminal not detected."
            $global:TerminalAlreadyInstalled = $false
        }
    } catch {
         Write-ColorOutput Yellow "Could not definitively check for Windows Terminal: $($_.Exception.Message)"
         # Assume not installed if check fails? Or assume installed? Safer to assume not.
         $global:TerminalAlreadyInstalled = $false
    }

    # --- Attempt Winget/Dependency Install (Might still fail if Terminal components are in use) ---
    if ($InitialRun.IsPresent) {
        Write-ColorOutput Green "Initial Run: Installing Winget dependencies and Winget..."
        try {
            # ... (xamlPath, vcLibsPath, wingetBundlePath definitions) ...
            $xamlPath = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.x64.appx"
            $vcLibsPath = Join-Path $env:TEMP "Microsoft.VCLibs.x64.14.00.Desktop.appx"
            $wingetBundlePath = Join-Path $env:TEMP "winget.msixbundle"

            Write-ColorOutput Cyan "Downloading UI.Xaml..."
            Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $xamlPath -EA Stop
            Write-ColorOutput Cyan "Installing UI.Xaml..."
            # This Add-AppxPackage might still fail with 0x80073D02 if WT components are locked
            Add-AppxPackage -Path $xamlPath -EA Stop
            Write-ColorOutput Cyan "Downloading VCLibs..."; Start-BitsTransfer -Source "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Destination $vcLibsPath -EA Stop
            Write-ColorOutput Cyan "Installing VCLibs..."; Add-AppxPackage -Path $vcLibsPath -EA Stop
            Write-ColorOutput Cyan "Fetching Winget..."; $uri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") } | Select -First 1
            if (-not $uri) { throw "Could not find Winget URI." }
            Write-ColorOutput Cyan "Downloading Winget..."; Start-BitsTransfer -Source $uri -Destination $wingetBundlePath -EA Stop
            Write-ColorOutput Cyan "Installing Winget..."; Add-AppxPackage -Path $wingetBundlePath -EA Stop
            $wingetInstalled = $true; Write-ColorOutput Green "Winget installed successfully."
            # PATH update attempt
            $winAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"; if (Test-Path $winAppsPath) { Write-ColorOutput Yellow "Adding WinApps to session PATH..."; $env:Path = "$($env:Path.TrimEnd(';'));$winAppsPath" -replace ';+', ';'; Start-Sleep -Seconds 5 }
        } catch {
            # Catch the specific error if possible
            if ($_.Exception.HResult -eq [int]0x80073D02) {
                 Write-ColorOutput Red "FATAL: Failed Winget/Dependency install (0x80073D02) - Resources likely in use (e.g., Windows Terminal components)."
                 Write-ColorOutput Red "       Details: $($_.Exception.Message)"
            } else {
                 Write-ColorOutput Red "FATAL: Failed Winget/Dependency install: $($_.Exception.Message)"
            }
            Write-ColorOutput Red "Script cannot continue. Exiting."; exit 1
        } finally { Remove-Item -Path $xamlPath, $vcLibsPath, $wingetBundlePath -EA SilentlyContinue }
    } else { Write-ColorOutput Magenta "Winget install skipped (Not Initial Run)."; return }

    # --- Install PS7 ---
    if ($wingetInstalled) {
        if (-not (Get-Command pwsh -EA SilentlyContinue)) {
            Write-ColorOutput Green "PS7 not found. Installing via Winget...";
            try { winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e --EA Stop; $psInstallSuccess = $true; Write-ColorOutput Green "PS7 installed." }
            catch { Write-ColorOutput Red "FATAL: 'winget install PS7' failed: $($_.Exception.Message)"; exit 1 }
            # Install NuGet Provider
            $pwshExe = Get-Command pwsh -EA SilentlyContinue; if ($pwshExe) { Start-Process -FilePath $pwshExe.Source -Args "-NoP -Command Install-PackageProvider -Name NuGet -Force -Scope CU" -Wait } else { Write-ColorOutput Red "pwsh.exe not found after install." }
        } else { Write-ColorOutput Magenta "PS7 already installed."; $psInstallSuccess = $true }
    }

    # --- Restart Logic ---
    $RestartNeeded = $InitialRun -and $psInstallSuccess -and (-not $IsPowerShell7)
    if ($RestartNeeded) {
        # ... (Restart logic remains the same as previous version) ...
         Write-ColorOutput Yellow "PowerShell 7 was just installed during Initial Run. Restarting script..."
        $CurrentScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Write-ColorOutput Red "FATAL: Cannot determine script path."; exit 1 }
        $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # NO -InitialRun
        Write-ColorOutput Cyan "Starting: pwsh $ArgList"
        try { Start-Process pwsh -ArgumentList $ArgList -ErrorAction Stop; Write-ColorOutput Green "New PS7 process started. Exiting current PS5.1 session."; exit 0 }
        catch { Write-ColorOutput Red "FATAL: Failed to start new PS7 process: $($_.Exception.Message)"; exit 1 }
    } else { Write-ColorOutput Cyan "No restart needed or conditions not met." }
    Write-ColorOutput Yellow "--- End of Winget & PowerShell 7 Installation ---"
}
#endregion

#region Installation Functions (Grouped by category)
# ... (Keep ALL your installation functions: InstallDependencies, QoLRegConfigurations, TakeOwnership, AddRegistryEntries, StartServices, InstallBasicKit, InstallAdvanced, InstallMedia, InstallDevTools, Gaming, NvidiaSettings etc. here) ...
# !!! IMPORTANT: Modify TerminalStuff function below !!!
#endregion

#region Helper Functions (Internal Use)
# ... (Keep InstallPythonAndPackages, Install-PyCharm, SetupGit, LoginGitHubCLI, PowerShellProfileSettings, Set-WindowsTerminalAsDefault, InstallJdownloader, InstallNeededForScript etc. here) ...
# !!! IMPORTANT: Modify TerminalStuff function below !!!
#endregion

# --- MODIFIED TerminalStuff FUNCTION ---
function TerminalStuff {
    [CmdletBinding()] param()
    Write-ColorOutput Magenta "--- Setting Up Terminal Environment ---"
    InstallNeededForScript # Install jq, wget first
    try {
         # --- Check if Terminal needs installing via Winget ---
         if (-not $global:TerminalAlreadyInstalled) {
             Write-ColorOutput Cyan "Windows Terminal not detected as pre-installed. Installing via Winget..."
             winget install -h 9N0DX20HK701 --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop # Windows Terminal
         } else {
             Write-ColorOutput Green "Skipping Windows Terminal installation (already installed)."
         }

         # --- Continue with rest of Terminal setup ---
         winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
         winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop

         Set-WindowsTerminalAsDefault # Call internal function

         winget install -h JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
         if (-not (Get-PackageProvider -Name NuGet -EA SilentlyContinue)) { Install-PackageProvider -Name NuGet -Force -EA Stop }
         Install-Module -Name Terminal-Icons -Repository PSGallery -Force -ErrorAction Stop; Update-Environment
         oh-my-posh font install FiraCode

         winget install -h ChrisLundquist.Clink --accept-source-agreements --accept-package-agreements -e --ErrorAction Stop
         $clinkPath = "C:\Program Files (x86)\clink"; if (Test-Path $clinkPath) { Write-ColorOutput Cyan "Adding Clink path..."; $env:Path = "$($env:Path.TrimEnd(';'));$clinkPath" -replace ';+', ';'; try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c clink set clink.logo none" -Wait -WindowStyle Hidden } catch { Write-ColorOutput Yellow "Clink set failed: $($_.Exception.Message)"}; $clinkCfgDir = Join-Path $env:LOCALAPPDATA "clink"; New-Item -Path $clinkCfgDir -ItemType Directory -Force -EA SilentlyContinue; $lua="load(io.popen('oh-my-posh init cmd --config=""$env:POSH_THEMES_PATH\jandedobbeleer.omp.json""'):read(""*a""))()"; Set-Content -Path (Join-Path $clinkCfgDir "oh-my-posh.lua") -V $lua -EA Stop } else { Write-ColorOutput Yellow "Clink path not found."}

        PowerShellProfileSettings

        $wtSettingsDest = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"; Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/terminal-settings.json" -Destination $wtSettingsDest -EA Stop; Write-ColorOutput Green "Terminal settings downloaded."

        SetupGit # Pass $GitHubToken if needed or ensure it's accessible

    } catch {
        Write-ColorOutput Red "An error occurred during Terminal setup: $($_.Exception.Message)"
    }
}


#region Selection Menu Logic
# ... (Keep Show-SelectionMenu, Show-CustomSelectionMenu, Invoke-SelectedFunctions here as before) ...
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
            Write-ColorOutput Green "Selected for '$($selectedGroup.Name)':"; $global:SelectionState.GetEnumerator() | Where-Object {$_.Value -eq $true} | ForEach-Object {Write-Host (" - $($_.Name)")}; Write-Host ""
            $customize = Read-Host "Customize this selection? (Y/N)"; if ($customize -match '^y') { Show-CustomSelectionMenu }
            return $true
        } else { Write-ColorOutput Red "Invalid selection."; Start-Sleep -Seconds 2 }
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

function Invoke-SelectedFunctions {
    [CmdletBinding()] param() # Uses $global:SelectionState
    Write-ColorOutput Magenta "--- Executing Selected Installation Steps ---"; $somethingSelected = $false
    # Prerequisite checks
    $appGroupsSelected = $global:SelectionState['InstallBasicKit'] -or $global:SelectionState['InstallAdvanced'] -or $global:SelectionState['InstallMedia'] -or $global:SelectionState['InstallDevTools'] -or $global:SelectionState['Gaming']
    if ($appGroupsSelected -and (-not $global:SelectionState['InstallDependencies'])) { Write-ColorOutput Yellow "Dependencies required. Enabling 'InstallDependencies'."; $global:SelectionState['InstallDependencies'] = $true }
    if (($global:SelectionState['InstallDevTools'] -or $global:SelectionState['Gaming']) -and (-not $global:SelectionState['TerminalStuff'])) { Write-ColorOutput Yellow "Terminal setup recommended. Enabling 'TerminalStuff'."; $global:SelectionState['TerminalStuff'] = $true }
    # Execution Order
    $executionOrder = @( 'InstallDependencies', 'QoLRegConfigurations', 'TakeOwnership', 'AddRegistryEntries', 'StartServices', 'TerminalStuff', 'InstallBasicKit', 'InstallAdvanced', 'InstallMedia', 'InstallDevTools', 'Gaming', 'NvidiaSettings' )
    foreach ($funcName in $executionOrder) {
        if ($global:SelectionState.ContainsKey($funcName) -and $global:SelectionState[$funcName]) {
            $somethingSelected = $true; Write-ColorOutput Cyan "==> Executing Function: $funcName <=="
            try { if (Get-Command $funcName -EA SilentlyContinue) { & $funcName -ErrorAction Stop } else { Write-ColorOutput Red "Error: Func '$funcName' selected but not defined." } }
            catch { $errorMessage = "!!!!!!!!!!!!!!!!!!! ERROR in '{0}': {1} !!!!!!!!!!!!!!!!!!!" -f $funcName, $_.Exception.ToString(); Write-ColorOutput Red $errorMessage; } # Use -f here too
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
try { Invoke-SelectedFunctions -ErrorAction Stop }
catch { Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; Write-ColorOutput Red "An UNHANDLED ERROR occurred during the execution phase:"; Write-ColorOutput Red $_.Exception.ToString(); Write-ColorOutput Red "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; exit 1 }

exit 0 # Explicitly exit with success code
