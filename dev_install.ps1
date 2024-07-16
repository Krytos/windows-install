param(
    [string]$GitHubToken,
    [switch]$PowerShell7 = $false
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
    RemoveWindowsFeatures
    InstallBasicKit
    InstallAdvanced
    QoLRegConfigurations
    RemoveGameBar
    InstallDevTools
    AddRegistryEntries
      
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
        [Environment]::GetEnvironmentVariables($level).GetEnumerator() | % {
            if ($_.Name -eq 'Path' -and $_.Value -ne $null) {
                $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select -unique) -join ';'
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

    # Disable PowerShell v2
    Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2" -NoRestart
    Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2Root" -NoRestart

    # Display the results
    Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -in @("WindowsMediaPlayer", "MicrosoftWindowsPowerShellV2", "MicrosoftWindowsPowerShellV2Root") } | Format-Table -AutoSize
}
# Create functions for different categories of installations and configurations
function InstallWinget {
    # Check if winget is installed
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-ColorOutput Green "winget is not installed. Installing winget..."
        Start-BitsTransfer -Source https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx -Destination $env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx
        Add-AppxPackage $env:TEMP\Microsoft.UI.Xaml.2.8.x64.appx
        $latestWingetMsixBundleUri = $(Invoke-RestMethod https://api.github.com/repos/microsoft/winget-cli/releases/latest).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") }
        $latestWingetMsixBundle = $latestWingetMsixBundleUri.Split("/")[-1]
        Write-ColorOutput Green "Downloading winget to artifacts directory..."
        Start-BitsTransfer -Source $latestWingetMsixBundleUri -Destination "./$latestWingetMsixBundle"
        Start-BitsTransfer -Source https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -Destination Microsoft.VCLibs.x64.14.00.Desktop.appx
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
    winget install -h python3 --accept-source-agreements --accept-package-agreements -e
    $env:Path += ";$env:USERPROFILE\AppData\Local\Programs\Python\$((Get-ChildItem -Path "$env:USERPROFILE\AppData\Local\Programs\Python" -Directory).Name)\Scripts"
    winget install Microsoft.VisualStudioCode --override "/verysilent /suppressmsgboxes /mergetasks='!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'" --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Microsoft.PowerToys --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Foxit.FoxitReader --accept-source-agreements --accept-package-agreements -e
    winget install -h XP8BSBGQW2DKS0 --accept-source-agreements --accept-package-agreements -e --force # PotPlayer
    winget install -h Nvidia.Broadcast --accept-source-agreements --accept-package-agreements -e
    winget install -h Telegram.TelegramDesktop --accept-source-agreements --accept-package-agreements -e
    winget install -h 9N8G7TSCL18R --accept-source-agreements --accept-package-agreements -e # NanaZip
    winget install -h Google.QuickShare --accept-source-agreements --accept-package-agreements -e --disable-interactivity
    winget install -h Mozilla.Firefox.DeveloperEdition --accept-source-agreements --accept-package-agreements -e
    winget install -h Parsec.Parsec --accept-source-agreements --accept-package-agreements -e
    Install-Spotify
}

function InstallAdvanced {
    winget install -h AntibodySoftware.WizTree --accept-source-agreements --accept-package-agreements -e
    winget install -h Obsidian.Obsidian --accept-source-agreements --accept-package-agreements -e
    winget install -h Insomnia.Insomnia --accept-source-agreements --accept-package-agreements -e
    winget install -h WinSCP.WinSCP --accept-source-agreements --accept-package-agreements -e
    winget install -h voidtools.Everything --accept-source-agreements --accept-package-agreements -e
    winget install Nvidia.CUDA --accept-source-agreements --accept-package-agreements -e
}

function AddRegistryEntries {
    # Add the command for WizTree to the context menu
    New-Item -Path "HKLM:\SOFTWARE\Classes\*\shell\WizTree\command" -Force |
    Set-ItemProperty -Name "(Default)" -Value "`"C:\Program Files\WizTree\WizTree64.exe`" `"%*1*`""

    # Add the icon for WizTree to the context menu
    New-Item -Path "HKLM:\SOFTWARE\Classes\*\shell\WizTree" -Force |
    Set-ItemProperty -Name "Icon" -Value "`"C:\Program Files\WizTree\WizTree64.exe`",0"
}

function Install-Spotify {
    $spotifyInstallerUrl = 'https://download.scdn.co/SpotifySetup.exe'
    $installerPath = Join-Path $env:TEMP 'SpotifySetup.exe'

    try {
        # Download Spotify installer
        Write-Host "Downloading Spotify installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $spotifyInstallerUrl -OutFile $installerPath

        # Run the installer
        Write-Host "Running Spotify installer..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $installerPath -ArgumentList '/Silent' -PassThru

        # Check the exit code
        if ($process.ExitCode -eq 0) {
            Write-Host "Spotify installation completed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Spotify installation might have encountered an issue. Exit code: $($process.ExitCode)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "An error occurred during Spotify installation: $_" -ForegroundColor Red
    }
    finally {
        # Clean up the installer file
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force
        }
    }
}

function InstallDependencies {
    winget install -h Microsoft.VCRedist.2010.x86 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2012.x64 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.DotNet.DesktopRuntime.6 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2013.x86 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2013.x64 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2010.x64 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.XNARedist --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2012.x86 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2015+.x86 --accept-source-agreements --accept-package-agreements -e
    winget install -h Microsoft.VCRedist.2015+.x64 --accept-source-agreements --accept-package-agreements -e
}

function TerminalStuff {
    # Install Windows Terminal
    winget install -h "windows terminal" --accept-source-agreements --accept-package-agreements --source "msstore"
    $env:Path += ";C:\Program Files\WindowsApps\$((Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Filter 'Microsoft.WindowsTerminal*' -Directory).Name)\wt.exe"
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
    InstallFonts
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
    Start-BitsTransfer -Source "https://gist.githubusercontent.com/Krytos/955066c26557eaad51e02d1cee8163a6/raw/518bb5f296e80efebb5b6c31ee170b75a7a3734a/terminal-settings.json" -Destination "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    Set-WindowsTerminalAsDefault
    Update-Environment
}

function QoLRegConfigurations {
    # Registry modifications
    # Disable mouse acceleration
    New-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -PropertyType String -Force
    # Disable Cortana
    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
    # Disable UAC
    New-ItemProperty -Path "HKCR:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0 -PropertyType DWord -Force
    # Open File Explorer to This PC
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -PropertyType DWord -Force
    # Enable compact mode
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "UseCompactMode" -Value 1 -PropertyType DWord -Force
    # Show hidden files
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -PropertyType DWord -Force
    # Show file extensions
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -PropertyType DWord -Force
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
}

function InstallPythonAndPackages {
    # Install all Python versions from 3.7 to 3.11
    $pythonVersions = @("3.7", "3.8", "3.9", "3.10", "3.11")
    foreach ($version in $pythonVersions) {
        winget install -h Python.Python.$version --accept-source-agreements --accept-package-agreements -e
    }

    # Install Python packages
    Update-Environment
    py -3.12 -m pip install pipx
    & pipx install poetry ipython hashcat ruff pyright pytest
    & pipx ensurepath

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
updatePATH=$(if (-not $SkipAddToPath) {"1"} else {"0"})
updateContextMenu=$(if (-not $SkipContextMenu) {"1"} else {"0"})
jre32=0
regenerationSharedArchive=1
.py=$(if (-not $SkipPyFileAssociation) {"1"} else {"0"})
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
    $profileContent = @"
`$env:POSH_GIT_ENABLED = `$true
oh-my-posh init pwsh --config $env:POSH_THEMES_PATH/night-owl.omp.json | Invoke-Expression
Import-Module -Name Terminal-Icons
"@

    $profilePaths = @(
        # "$env:USERPROFILE\OneDrive\Documents\PowerShell\profile.ps1",
        # "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        # "$env:USERPROFILE\OneDrive\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        "C:\Program Files\PowerShell\7\Profile.ps1"
    )

    foreach ($path in $profilePaths) {
        Set-Content -Path $path -Value $profileContent
    }
    Update-Environment
}

function InstallFonts {
    # Download and install FiraCode Nerd Font
    Set-Location $env:USERPROFILE"\"Downloads
    Start-BitsTransfer -Source "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.1/FiraCode.zip" -Destination "FiraCode.zip"
    Expand-Archive -Path "FiraCode.zip" -DestinationPath "fonts"
    $fontFiles = @(
        "FiraCodeNerdFont-Bold.ttf",
        "FiraCodeNerdFont-Light.ttf",
        "FiraCodeNerdFont-Medium.ttf",
        "FiraCodeNerdFont-Regular.ttf",
        "FiraCodeNerdFont-SemiBold.ttf",
        "FiraCodeNerdFont-Retina.ttf"
    )

    foreach ($fontFile in $fontFiles) {
        Copy-Item "fonts\$fontFile" "$env:SystemRoot\Fonts"
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "Fira Code Nerd ($($fontFile -replace '.ttf',''))" -Value $fontFile -PropertyType String -Force
    }

    Remove-Item -Path "fonts" -Recurse -Force
    Remove-Item -Path "FiraCode.zip" -Force
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
    winget install -h Git.Git --accept-source-agreements --accept-package-agreements -e
    winget install -h GitHub.cli --accept-source-agreements --accept-package-agreements -e
    # Add git to path
    $env:Path += ";C:\Program Files\Git\cmd"
    Update-Environment
    git config --global user.email "kmeinon@gmail.com"
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
                                       
# Call the master function

InstallAllTheThings


Write-ColorOutput Green "##############################################"
Write-ColorOutput Green "All installations and configurations completed."
Write-ColorOutput Green "##############################################"


# Add PyCharm context menu entries
# New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\Open as PyCharm Project\command" -Force | Out-Null
# Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\Open as PyCharm Project\command" -Name "(Default)" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`" `"%V`""
# New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\Open as PyCharm Project" -Name "Icon" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`", 0"

# New-Item -Path "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\Open PyCharm here\command" -Force | Out-Null
# Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\Open PyCharm here\command" -Name "(Default)" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`" `"%V`""
# New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\Open PyCharm here" -Name "Icon" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`", 0"

# New-Item -Path "Registry::HKEY_CLASSES_ROOT\*\shell\Open with PyCharm\command" -Force | Out-Null
# Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\*\shell\Open with PyCharm\command" -Name "(Default)" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`" `"%1`""
# New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\*\shell\Open with PyCharm" -Name "Icon" -Value "`"C:\Users\Kevin\AppData\Local\Programs\PyCharm Professional\bin\pycharm64.exe`", 0"
