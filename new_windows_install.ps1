# TODOs #
# WSL activation and installing WSL
# Selection Menu for what to install

param(
    [string]$GitHubToken,
    [switch]$PowerShell7 = $false,
    [switch]$InitialRun = $false
)

# At the beginning of your script
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PowerShell7 = $true
}

if ($InitialRun -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    # Create a flag file
    New-Item -Path "$env:TEMP\restart_pwsh.flag" -ItemType File -Force
    # Exit this PowerShell session
    exit
}

# Rest of your script goes here
# Change to user profile directory
Set-Location $env:USERPROFILE

# Check if the HKCR PSDrive already exists
if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
    # If it doesn't exist, create it
    New-PSDrive -Name "HKCR" -PSProvider Registry -Root "HKEY_CLASSES_ROOT" | Out-Null
}

function InstallAllTheThings {
    if (-not $PowerShell7) {
        InstallWinget
    }
    else {
        Write-ColorOutput Green "Running in PowerShell 7, skipping Winget installation."
    }
    InstallDependencies
    QoLRegConfigurations
    RemoveWindowsFeatures
    InstallBasicKit
    InstallAdvanced
    InstallMedia
    RemoveGameBar
    InstallDevTools
    AddRegistryEntries
    TakeOwnership
    PoEStuff
    if (Test-Path "OneDrive\Desktop\Game Macro\autostart.ahk") {
        Start-Process "OneDrive\Desktop\Game Macro\autostart.ahk"
    }
    else {
        Write-ColorOutput Yellow "autostart.ahk not found in the expected location."
    }
}

function Update-Environment {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($level in "Machine", "User") {
        [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
            if ($_.Name -eq 'Path' -and $null -ne $_.Value) {
                $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select-Object -unique) -join ';'
            }
            $_
        } | Set-Content -Path { "Env:$($_.Name)" }
    }
}

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

function RemoveWindowsFeatures {
    # Disable Windows Media Player
    Disable-WindowsOptionalFeature -Online -FeatureName "WindowsMediaPlayer" -NoRestart

    # Display the results
    Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -in @("WindowsMediaPlayer") } | Format-Table -AutoSize
}
# Create functions for different categories of installations and configurations
function InstallWinget {

    if ($InitialRun.IsPresent) {
        Write-ColorOutput Green "winget is not installed. Installing winget..."
        Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx
        Add-AppxPackage $env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx
        $latestWingetMsixBundleUri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest").assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") }
        $latestWingetMsixBundle = $latestWingetMsixBundleUri.Split("/")[-1]
        Write-ColorOutput Green "Downloading winget to artifacts directory..."
        Start-BitsTransfer -Source $latestWingetMsixBundleUri -Destination "./$latestWingetMsixBundle"
        Start-BitsTransfer -Source "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Destination Microsoft.VCLibs.x64.14.00.Desktop.appx
        Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
        Add-AppxPackage $latestWingetMsixBundle
        # Remove the installers:
        Remove-Item -Path $latestWingetMsixBundle
        Remove-Item -Path Microsoft.VCLibs.x64.14.00.Desktop.appx
        Remove-Item -Path $env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx
        Update-Environment
    }
    else {
        Write-ColorOutput Magenta "winget is already installed."
    }

    # Check if new PowerShell is installed
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-ColorOutput Green "PowerShell is not installed. Installing PowerShell..."
        winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e
        Update-Environment
        Install-PackageProvider -Name NuGet -Force
        Update-Environment
    }
    else {

        Write-ColorOutput Magenta "PowerShell is already installed."
    }

    InstallNeededForScript

    TerminalStuff

    # Check if PowerShell was just installed
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput Green "PowerShell has been installed. Restarting script in new PowerShell 7..."
        if (-not $InitialRun) {
            Start-Process wt -ArgumentList "pwsh -NoExit -File `"$PSCommandPath`" -GitHubToken `"$GitHubToken`""
            [System.Diagnostics.Process]::GetCurrentProcess().Kill()
        }
    }
}

function InstallNeededForScript {
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    winget install -h jqlang.jq --accept-source-agreements --accept-package-agreements -e
    winget install -h wget --accept-source-agreements --accept-package-agreements -e
}

function InstallBasicKit {
    winget install -h AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements -e
    powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
    $env:PATH = "C:`\Users`\Kevin`\.local`\bin;$env:PATH"
    Update-Environment
    winget install Microsoft.VisualStudioCode --override "/verysilent /suppressmsgboxes /mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Microsoft.PowerToys --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Audacity.Audacity --accept-source-agreements --accept-package-agreements -e
    winget install -h Discord.Discord --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Foxit.FoxitReader --accept-source-agreements --accept-package-agreements -e
    winget install -h MediaArea.MediaInfo.GUI --accept-source-agreements --accept-package-agreements -e
    winget install -h Valve.Steam --accept-source-agreements --accept-package-agreements -e
    winget install -h XP8BSBGQW2DKS0 --accept-source-agreements --accept-package-agreements -e --force # PotPlayer
    winget install -h AppWork.JDownloader --accept-source-agreements --accept-package-agreements -e
    winget install -h RevoUninstaller.RevoUninstaller --accept-source-agreements --accept-package-agreements -e
    winget install -h Nvidia.Broadcast --accept-source-agreements --accept-package-agreements -e
    winget install -h TeamSpeakSystems.TeamSpeakClient.Beta --accept-source-agreements --accept-package-agreements -e
    winget install -h Telegram.TelegramDesktop --accept-source-agreements --accept-package-agreements -e
    winget install -h 9N8G7TSCL18R --accept-source-agreements --accept-package-agreements -e # NanaZip
    winget install -h Google.QuickShare --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Mozilla.Firefox.DeveloperEdition --accept-source-agreements --accept-package-agreements -e
    winget install -h Parsec.Parsec --accept-source-agreements --accept-package-agreements -e
    winget install -h 9NCBCSZSJRSB --accept-source-agreements --accept-package-agreements -e # Spotify
}

function InstallAdvanced {
    winget install -h Logitech.GHUB --accept-source-agreements --accept-package-agreements -e
    winget install -h AntibodySoftware.WizTree --accept-source-agreements --accept-package-agreements -e
    winget install -h Blizzard.BattleNet --accept-source-agreements --accept-package-agreements -e
    winget install Obsidian.Obsidian
    winget install -h Intel.PresentMon --accept-source-agreements --accept-package-agreements -e
    winget install -h Insomnia.Insomnia --accept-source-agreements --accept-package-agreements -e
    winget install -h qBittorrent.qBittorrent --accept-source-agreements --accept-package-agreements -e
    winget install -h WinSCP.WinSCP --accept-source-agreements --accept-package-agreements -e
    winget install -h voidtools.Everything --accept-source-agreements --accept-package-agreements -e
    winget install -h Nvidia.PhysX --accept-source-agreements --accept-package-agreements -e
    winget install -h WowUp.CF --accept-source-agreements --accept-package-agreements -e
    winget install -h UnifiedIntents.UnifiedRemote --accept-source-agreements --accept-package-agreements -e
    winget install -h HandBrake.HandBrake --accept-source-agreements --accept-package-agreements -e
}


function TakeOwnership {
    # Remove existing keys
    Remove-Item -Path "HKCR:\*\shell\TakeOwnership" -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "HKCR:\*\shell\runas" -Recurse -ErrorAction SilentlyContinue

    # Create new keys and set values for files
    New-Item -Path "HKCR:\*\shell\TakeOwnership" -Force
    Set-ItemProperty -Path "HKCR:\*\shell\TakeOwnership" -Name "(Default)" -Value "Take Ownership"
    Remove-ItemProperty -Path "HKCR:\*\shell\TakeOwnership" -Name "Extended" -ErrorAction SilentlyContinue
    New-ItemProperty -Path "HKCR:\*\shell\TakeOwnership" -Name "HasLUAShield" -PropertyType String -Value ""
    New-ItemProperty -Path "HKCR:\*\shell\TakeOwnership" -Name "NoWorkingDirectory" -PropertyType String -Value ""
    New-ItemProperty -Path "HKCR:\*\shell\TakeOwnership" -Name "NeverDefault" -PropertyType String -Value ""

    New-Item -Path "HKCR:\*\shell\TakeOwnership\command" -Force
    $commandValue = 'powershell -windowstyle hidden -command "Start-Process cmd -ArgumentList ''/c takeown /f \""%1\"" && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l'' -Verb runAs"'
    Set-ItemProperty -Path "HKCR:\*\shell\TakeOwnership\command" -Name "(Default)" -Value $commandValue
    Set-ItemProperty -Path "HKCR:\*\shell\TakeOwnership\command" -Name "IsolatedCommand" -Value $commandValue

    # Create new keys and set values for directories
    New-Item -Path "HKCR:\Directory\shell\TakeOwnership" -Force
    Set-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "(Default)" -Value "Take Ownership"
    $appliesToValue = 'NOT (System.ItemPathDisplay:="C:\Users" OR System.ItemPathDisplay:="C:\ProgramData" OR System.ItemPathDisplay:="C:\Windows" OR System.ItemPathDisplay:="C:\Windows\System32" OR System.ItemPathDisplay:="C:\Program Files" OR System.ItemPathDisplay:="C:\Program Files (x86)")'
    Set-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "AppliesTo" -Value $appliesToValue
    Remove-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "Extended" -ErrorAction SilentlyContinue
    New-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "HasLUAShield" -PropertyType String -Value ""
    New-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "NoWorkingDirectory" -PropertyType String -Value ""
    Set-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership" -Name "Position" -Value "middle"

    New-Item -Path "HKCR:\Directory\shell\TakeOwnership\command" -Force
    $dirCommandValue = 'powershell -windowstyle hidden -command "$Y = ($null | choice).Substring(1,1); Start-Process cmd -ArgumentList (''/c takeown /f \""%1\"" /r /d '' + $Y + '' && icacls \""%1\"" /grant *S-1-3-4:F /t /c /l /q'') -Verb runAs"'
    Set-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership\command" -Name "(Default)" -Value $dirCommandValue
    Set-ItemProperty -Path "HKCR:\Directory\shell\TakeOwnership\command" -Name "IsolatedCommand" -Value $dirCommandValue

    # Create new keys and set values for drives
    New-Item -Path "HKCR:\Drive\shell\runas" -Force
    Set-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "(Default)" -Value "Take Ownership"
    Remove-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "Extended" -ErrorAction SilentlyContinue
    New-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "HasLUAShield" -PropertyType String -Value ""
    New-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "NoWorkingDirectory" -PropertyType String -Value ""
    Set-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "Position" -Value "middle"
    Set-ItemProperty -Path "HKCR:\Drive\shell\runas" -Name "AppliesTo" -Value 'NOT (System.ItemPathDisplay:="C:\")'

    New-Item -Path "HKCR:\Drive\shell\runas\command" -Force
    $driveCommandValue = 'cmd.exe /c takeown /f "%1\" /r /d y && icacls "%1\" /grant *S-1-3-4:F /t /c'
    Set-ItemProperty -Path "HKCR:\Drive\shell\runas\command" -Name "(Default)" -Value $driveCommandValue
    Set-ItemProperty -Path "HKCR:\Drive\shell\runas\command" -Name "IsolatedCommand" -Value $driveCommandValue

}


function AddRegistryEntries {
    # Add the command for WizTree to the context menu
    New-Item -Path "HKLM:\SOFTWARE\Classes\*\shell\WizTree\command" -Force |
    Set-ItemProperty -Name "(Default)" -Value "`"C:\Program Files\WizTree\WizTree64.exe`" `"%*1*`""

    # Add the icon for WizTree to the context menu
    New-Item -Path "HKLM:\SOFTWARE\Classes\*\shell\WizTree" -Force |
    Set-ItemProperty -Name "Icon" -Value "`"C:\Program Files\WizTree\WizTree64.exe`",0"
}

function InstallMedia {
    winget install -h Jellyfin.JellyfinMediaPlayer --accept-source-agreements --accept-package-agreements -e
    winget install -h XBMCFoundation.Kodi --accept-source-agreements --accept-package-agreements -e
}

function InstallDependencies {
    winget install -h Microsoft.DotNet.DesktopRuntime.6 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.XNARedist --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2015+.x86 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2015+.x64 --accept-source-agreements --accept-package-agreements -e
}

function TerminalStuff {
    # Start SSH Agent and set it to start automatically
    winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e
    winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e
    function Start-Services {
        $services = @("ssh-agent")
        foreach ($service in $services) {
            Get-Service $service | Set-Service -StartupType Automatic
            Start-Service $service
        }

    }
    Start-Services
    # Install Windows Terminal
    winget install -h 9N0DX20HK701 --accept-source-agreements --accept-package-agreements # Windows Terminal
    $env:Path += ";C:\Program Files\WindowsApps\`$((Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Filter 'Microsoft.WindowsTerminal*' -Directory).Name)\wt.exe"
    Update-Environment

    # Set Terminal as default terminal emulator
    function Set-WindowsTerminalAsDefault {
        $terminalPath = (Get-Command wt).Source

        if (-not (Test-Path $terminalPath)) {
            Write-Error "Windows Terminal (wt.exe) not found. Make sure it's installed."
            return
        }

        try {
            # Set Windows Terminal as default for console window host
            New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" -PropertyType String -Force | Out-Null

            # Set Windows Terminal as default for terminal window host
            New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -PropertyType String -Force | Out-Null

            Write-ColorOutput Green "Windows Terminal has been set as the default console host."
        }
        catch {
            Write-Error "An error occurred while setting Windows Terminal as default: $_"
        }
    }
    Update-Environment
    # Install oh-my-posh
    winget install -h JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements -e
    # Install Terminal-Icons
    Install-Module -Name Terminal-Icons -Repository PSGallery -Force
    # Install Fonts
    Update-Environment
    oh-my-posh font install FiraCode
    # Install Clink and configure it
    winget install clink
    $env:Path += ";C:\Program Files (x86)\clink"
    Update-Environment
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c clink set clink.logo none" -Wait

    # Create oh-my-posh.lua file
    $ohMyPoshLuaContent = @"
load(io.popen('oh-my-posh init cmd --config "$env:POSH_THEMES_PATH\night-owl.omp.json"'):read("*a"))()
"@ -replace '\\', '\\'
    Set-Content -Path "$env:USERPROFILE\AppData\Local\clink\oh-my-posh.lua" -Value $ohMyPoshLuaContent
    # Create PowerShell profile files
    PowerShellProfileSettings
    # Download and set up Windows Terminal settings
    Start-BitsTransfer -Source "https://raw.githubusercontent.com/Krytos/windows-install/main/terminal-settings.json" -Destination "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    Set-WindowsTerminalAsDefault
    Update-Environment
}

function QoLRegConfigurations {
    # Registry modifications

    # Disable UAC
    $UAC_Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $UAC_Path)) {
        New-Item -Path $UAC_Path -Force | Out-Null
    }
    New-ItemProperty -Path $UAC_Path -Name "ConsentPromptBehaviorAdmin" -Value 0 -PropertyType DWord -Force
    # Disable mouse acceleration
    New-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value 0 -PropertyType String -Force
    # Disable Cortana
    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
    # Open File Explorer to This PC
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -PropertyType DWord -Force
    # Enable compact mode
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "UseCompactMode" -Value 1 -PropertyType DWord -Force
    # Show hidden files
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -PropertyType DWord -Force
    # Show file extensions
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -PropertyType DWord -Force
    # Restore old context menu
    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Value "" -Force
    # Enable Clipboard History
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1
    # Disable Windows Search in the taskbar
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
    # Disable Task View in Task Bar
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
    # Find the entry for the UK keyboard layout and remove it
    $registryKey = Get-ItemProperty -Path "HKCU:\Keyboard Layout\Substitutes" -Name "00000809"
    if ($registryKey) {
        Remove-ItemProperty -Path "HKCU:\Keyboard Layout\Substitutes" -Name "00000809"
    }

    $layoutsToRemove = @("00000809", "00000409")
    $path = "HKCU:\Keyboard Layout\Preload"

    foreach ($layout in $layoutsToRemove) {
        $preload = Get-ItemProperty -Path $path
        $toRemove = $preload.PSObject.Properties | Where-Object { $_.Value -eq $layout }

        if ($toRemove) {
            Remove-ItemProperty -Path $path -Name $toRemove.Name
            Write-Host "Layout $layout removed successfully."
        }
        else {
            Write-Host "Layout $layout not found."
        }
    }

    Write-Host "`nCurrent Preload entries:"
    Get-ItemProperty -Path $path

    Stop-Process -Name explorer -Force
}

function InstallDevTools {
    # More winget installations
    winget install -h Chocolatey.Chocolatey --accept-source-agreements --accept-package-agreements -e
    winget install -h JetBrains.Toolbox --accept-source-agreements --accept-package-agreements -e
    winget pin add JetBrains.Toolbox
    InstallPythonAndPackages
    SetupGit
    winget install Nvidia.CUDA --accept-source-agreements --accept-package-agreements -e
}

function InstallPythonAndPackages {
    # Install all Python versions from 3.7 to 3.11
    $pythonVersions = @("3.7", "3.8", "3.9", "3.10", "3.11", "3.12")
    foreach ($version in $pythonVersions) {
        uv python install $version
    }

    $pythonTools = @("hashcat", "ipython", "nuitka", "ruff")
    foreach ($tool in $pythonTools) {
        uv tool install $tool
    }
    uv tool ensurepath
    function Install-PyCharm {
        param (
            [string]$InstallDir = "C:\Program Files\JetBrains\PyCharm",
            [switch]$SkipAddToPath,
            [switch]$SkipContextMenu,
            [switch]$SkipPyFileAssociation
        )

        $configContent = @"
mode=admin
launcher32=0
launcher64=1
updatePATH=`$(if (-not `$SkipAddToPath) {"1"} else {"0"})
updateContextMenu=`$(if (-not `$SkipContextMenu) {"1"} else {"0"})
jre32=0
regenerationSharedArchive=1
.py=`$(if (-not `$SkipPyFileAssociation) {"1"} else {"0"})
"@

        $tempConfigPath = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempConfigPath -Value $configContent

        $installCommand = "winget install -e --id JetBrains.PyCharm.Professional --override `"/S /CONFIG=$tempConfigPath /D=$InstallDir`" --accept-source-agreements --accept-package-agreements"

        try {
            Invoke-Expression $installCommand
        }
        finally {
            Remove-Item -Path $tempConfigPath -Force
        }
    }

    Install-PyCharm -SkipPyFileAssociation
}

function PowerShellProfileSettings {
    # Create PowerShell profile files
    $pwsh_profile_content = @"
`$env:VIRTUAL_ENV_DISABLE_PROMPT = 1
`$env:POSH_GIT_ENABLED = `$true
oh-my-posh init pwsh --config "`$env:POSH_THEMES_PATH\night-owl.omp.json" | Invoke-Expression
Import-Module -Name Terminal-Icons

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
venv

function denv {
    `$venvDirs = Get-ChildItem -Directory -Path . | Where-Object { `$_.Name -match '^\.?venv' }
    foreach (`$dir in `$venvDirs) {
        `$deactivatePath = Join-Path `$dir.Name "Scripts\deactivate.bat"
        if (Test-Path `$deactivatePath) {
            & `$deactivatePath
            Write-Host "Deactivated virtual environment" -ForegroundColor Yellow
            return
        }
    }
}
"@

    $powershell_profile_content = @"
`$env:VIRTUAL_ENV_DISABLE_PROMPT = 1
`$env:POSH_GIT_ENABLED = `$true
oh-my-posh init pwsh --config "`$env:POSH_THEMES_PATH\night-owl.omp.json" | Invoke-Expression
Import-Module -Name Terminal-Icons

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
venv

function denv {
    `$venvDirs = Get-ChildItem -Directory -Path . | Where-Object { `$_.Name -match '^\.?venv' }
    foreach (`$dir in `$venvDirs) {
        `$deactivatePath = Join-Path `$dir.Name "Scripts\deactivate.bat"
        if (Test-Path `$deactivatePath) {
            & `$deactivatePath
            Write-Host "Deactivated virtual environment" -ForegroundColor Yellow
            return
        }
    }
}
"@

    # Ensure the directories exist
    $pwshProfileDir = "$env:USERPROFILE\Documents\PowerShell"
    $psProfileDir = "$env:USERPROFILE\Documents\WindowsPowerShell"

    if (-not (Test-Path $pwshProfileDir)) {
        New-Item -Path $pwshProfileDir -ItemType Directory -Force
    }

    if (-not (Test-Path $psProfileDir)) {
        New-Item -Path $psProfileDir -ItemType Directory -Force
    }

    # Create the profile files
    Set-Content -Path "$pwshProfileDir\Microsoft.PowerShell_profile.ps1" -Value $pwsh_profile_content
    Set-Content -Path "$psProfileDir\Microsoft.PowerShell_profile.ps1" -Value $powershell_profile_content

    Write-Host "PowerShell profile files have been created successfully." -ForegroundColor Green
    Write-Host "Pwsh profile: $pwshProfileDir\Microsoft.PowerShell_profile.ps1" -ForegroundColor Cyan
    Write-Host "PowerShell profile: $psProfileDir\Microsoft.PowerShell_profile.ps1" -ForegroundColor Cyan
    Update-Environment
}



function RemoveGameBar {
    try {
        # Game DVR settings
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force

        # ms-gamebar protocol settings
        New-Item -Path "HKCR:\ms-gamebar" -Force | Out-Null
        Set-ItemProperty -Path "HKCR:\ms-gamebar" -Name "(Default)" -Value "URL:ms-gamebar" -Force
        New-ItemProperty -Path "HKCR:\ms-gamebar" -Name "URL Protocol" -Value "" -PropertyType String -Force
        New-ItemProperty -Path "HKCR:\ms-gamebar" -Name "NoOpenWith" -Value "" -PropertyType String -Force
        New-Item -Path "HKCR:\ms-gamebar\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "HKCR:\ms-gamebar\shell\open\command" -Name "(Default)" -Value "`"$env:SystemRoot\System32\systray.exe`"" -Force

        # ms-gamebarservices protocol settings
        New-Item -Path "HKCR:\ms-gamebarservices" -Force | Out-Null
        Set-ItemProperty -Path "HKCR:\ms-gamebarservices" -Name "(Default)" -Value "URL:ms-gamebarservices" -Force
        New-ItemProperty -Path "HKCR:\ms-gamebarservices" -Name "URL Protocol" -Value "" -PropertyType String -Force
        New-ItemProperty -Path "HKCR:\ms-gamebarservices" -Name "NoOpenWith" -Value "" -PropertyType String -Force
        New-Item -Path "HKCR:\ms-gamebarservices\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "HKCR:\ms-gamebarservices\shell\open\command" -Name "(Default)" -Value "`"$env:SystemRoot\System32\systray.exe`"" -Force

        Write-ColorOutput Green "Custom registry settings have been applied successfully."
    }
    catch {
        Write-Error "An error occurred while setting custom registry settings: $_"
    }
}

function SetupGit {
    # Add git to path
    $env:Path += ";C:\Program Files\Git\cmd"
    Update-Environment
    git config --global user.email "kmeinon@gmail.com"
    git config --global user.name "Kevin Meinon"
    git config --global --add safe.directory '*'
    Update-Environment
    function LoginGitHubCLI {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Token
        )

        try {

            # Authenticate using the token
            $output = $Token | gh auth login --hostname "github.com" --with-token 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput Green "Successfully authenticated with GitHub CLI"
            }
            else {
                Write-Error "Failed to authenticate with GitHub CLI: $output"
            }
        }
        catch {
            Write-Error "An error occurred while authenticating with GitHub CLI: $_"
        }
    }

    # GitHub CLI authentication
    LoginGitHubCLI -Token $GitHubToken
}

function PoEStuff {
    # Download and run PoeLurkerSetup
    function DownloadAndInstallPoeLurker {
        $downloadPath = Join-Path $env:TEMP "PoeLurkerSetup.exe"
        $url = "https://github.com/C1rdec/Poe-Lurker/releases/latest/download/PoeLurkerSetup.exe"

        try {
            # Download the file
            Write-ColorOutput Green "Downloading PoeLurker..."
            Start-BitsTransfer -Source $url -Destination $downloadPath

            # Check if the file was downloaded successfully
            if (Test-Path $downloadPath) {
                Write-ColorOutput Green "Download completed. Installing PoeLurker..."

                # Install the application
                Start-Process -FilePath $downloadPath -ArgumentList "/VERYSILENT"

                Write-ColorOutput Green "PoeLurker installation completed."
            }
            else {
                Write-Error "Failed to download PoeLurker."
            }
        }
        catch {
            Write-Error "An error occurred: $_"
        }
    }

    function DownloadAndInstallAwakenedPoeTrade {
        $repo = "SnosMe/awakened-poe-trade"
        $filePattern = "Awakened-PoE-Trade-Setup-*.exe"
        $downloadPath = Join-Path $env:TEMP "AwakenedPoeTradeSetup.exe"

        try {
            # Fetch the latest release information
            $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"

            # Find the asset URL for the Awakened-PoE-Trade-Setup-*.exe file
            $assetUrl = $releaseInfo.assets | Where-Object { $_.name -like $filePattern } | Select-Object -ExpandProperty browser_download_url -First 1

            if (-not $assetUrl) {
                Write-Error "Could not find $filePattern in the latest release."
                return
            }

            # Download the file
            Write-ColorOutput Green "Downloading Awakened PoE Trade..."
            Start-BitsTransfer -Source $assetUrl -Destination $downloadPath

            # Check if the file was downloaded successfully
            if (Test-Path $downloadPath) {
                Write-ColorOutput Green "Download completed. Installing Awakened PoE Trade..."

                # Install the application
                $installPath = "$env:USERPROFILE\AppData\Local\Awakened PoE Trade"
                Start-Process -FilePath $downloadPath -ArgumentList "/S /D=`"$installPath`"" -Wait

                if (Test-Path "C:\Utility Account\AppData\Local\Programs\Awakened PoE Trade\Awakened PoE Trade.lnk") {
                    Remove-Item "C:\Utility Account\AppData\Local\Programs\Awakened PoE Trade\Awakened PoE Trade.lnk"
                }
            }
            else {
                Write-Error "Failed to download Awakened PoE Trade."
            }
        }
        catch {
            Write-Error "An error occurred: $_"
        }
    }

    DownloadAndInstallPoeLurker
    DownloadAndInstallAwakenedPoeTrade
    winget install -h PathofBuildingCommunity.PathofBuildingCommunity --accept-source-agreements --accept-package-agreements -e
}

# Call the master function

InstallAllTheThings


Write-ColorOutput Green "##############################################"
Write-ColorOutput Green "All installations and configurations completed."
Write-ColorOutput Green "##############################################"
