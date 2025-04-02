function InstallWingetAndRestartIfInitialRun {
     Write-ColorOutput Yellow "--- Attempting Winget & PowerShell 7 Installation (Initial Run) ---"
    $wingetInstalled = $false
    $psInstallSuccess = $false

    # Check for pre-installed Terminal
    # ... (Keep this check as before) ...
    Write-ColorOutput Cyan "Checking for existing Windows Terminal installation..."
    try { if (Get-AppxPackage -Name "Microsoft.WindowsTerminal" -EA SilentlyContinue) { Write-ColorOutput Green "Windows Terminal appears to be pre-installed."; $global:TerminalAlreadyInstalled = $true } else { Write-ColorOutput Yellow "Windows Terminal not detected."; $global:TerminalAlreadyInstalled = $false } }
    catch { Write-ColorOutput Yellow "Could not check for Windows Terminal: $($_.Exception.Message)"; $global:TerminalAlreadyInstalled = $false }


    if ($InitialRun.IsPresent) {
        Write-ColorOutput Green "Initial Run: Installing prerequisites..."
        # --- 1. Install Latest VC++ Redistributable (Provides VCLibs) ---
        $vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe" # Link to latest VS 2015-2022 x64
        $vcRedistPath = Join-Path $env:TEMP "vc_redist.x64.exe"
        try {
            Write-ColorOutput Cyan "Downloading latest VC++ Redistributable..."
            Start-BitsTransfer -Source $vcRedistUrl -Destination $vcRedistPath -ErrorAction Stop
            Write-ColorOutput Cyan "Installing VC++ Redistributable silently..."
            # Use /quiet for silent, /norestart to prevent unexpected reboots
            Start-Process -FilePath $vcRedistPath -ArgumentList "/install /quiet /norestart" -Wait -ErrorAction Stop
            Write-ColorOutput Green "VC++ Redistributable installation complete."
        } catch {
             Write-ColorOutput Red "FATAL: Failed to download or install VC++ Redistributable: $($_.Exception.Message)"
             Write-ColorOutput Red "This provides necessary VCLibs. Script cannot continue. Exiting."
             exit 1
        } finally {
             Remove-Item -Path $vcRedistPath -ErrorAction SilentlyContinue
        }

        # --- 2. Install UI.Xaml ---
        Write-ColorOutput Green "Installing Winget dependencies (UI.Xaml)..."
        $xamlPath = Join-Path $env:TEMP "Microsoft.UI.Xaml.2.8.x64.appx"
        try {
            Write-ColorOutput Cyan "Downloading UI.Xaml..."
            Start-BitsTransfer -Source "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -Destination $xamlPath -EA Stop
            Write-ColorOutput Cyan "Installing UI.Xaml..."
            Add-AppxPackage -Path $xamlPath -EA Stop
            Write-ColorOutput Green "UI.Xaml installed successfully."
        } catch {
             # Catch the specific error if possible
            if ($_.Exception.HResult -eq [int]0x80073D02) { Write-ColorOutput Red "FATAL: Failed UI.Xaml install (0x80073D02) - Resources likely in use (e.g., Windows Terminal components)." }
            else { Write-ColorOutput Red "FATAL: Failed UI.Xaml install: $($_.Exception.Message)" }
            Write-ColorOutput Red "Script cannot continue. Exiting."; exit 1
        } finally { Remove-Item -Path $xamlPath -EA SilentlyContinue }


        # --- 3. Install Winget ---
         Write-ColorOutput Green "Installing Winget package..."
         $wingetBundlePath = Join-Path $env:TEMP "winget.msixbundle"
         try {
            Write-ColorOutput Cyan "Fetching Winget..."; $uri = $(Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing).assets.browser_download_url | Where-Object { $_.EndsWith(".msixbundle") } | Select -First 1
            if (-not $uri) { throw "Could not find Winget URI." }
            Write-ColorOutput Cyan "Downloading Winget..."; Start-BitsTransfer -Source $uri -Destination $wingetBundlePath -EA Stop
            Write-ColorOutput Cyan "Installing Winget..."; Add-AppxPackage -Path $wingetBundlePath -EA Stop
            $wingetInstalled = $true; Write-ColorOutput Green "Winget installed successfully."
            # PATH update attempt
            $winAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"; if (Test-Path $winAppsPath) { Write-ColorOutput Yellow "Adding WinApps to session PATH..."; $env:Path = "$($env:Path.TrimEnd(';'));$winAppsPath" -replace ';+', ';'; Start-Sleep -Seconds 5 }
        } catch {
            # Catch the VCLibs dependency error specifically if it still occurs
            if ($_.Exception.HResult -eq [int]0x80073CF3) { Write-ColorOutput Red "FATAL: Failed Winget install (0x80073CF3) - Dependency validation failed (VCLibs issue?). Ensure VC++ Redist installed correctly." }
            else { Write-ColorOutput Red "FATAL: Failed Winget install: $($_.Exception.Message)" }
             Write-ColorOutput Red "Script cannot continue. Exiting."; exit 1
        } finally { Remove-Item -Path $wingetBundlePath -EA SilentlyContinue }

    } else { Write-ColorOutput Magenta "Winget install skipped (Not Initial Run)."; return }

    # --- Install PS7 ---
    # ... (Keep this section exactly as before) ...
    if ($wingetInstalled) {
        if (-not (Get-Command pwsh -EA SilentlyContinue)) {
            Write-ColorOutput Green "PS7 not found. Installing via Winget...";
            try { winget install -h Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e --EA Stop; $psInstallSuccess = $true; Write-ColorOutput Green "PS7 installed." }
            catch { Write-ColorOutput Red "FATAL: 'winget install PS7' failed: $($_.Exception.Message)"; exit 1 }
            $pwshExe = Get-Command pwsh -EA SilentlyContinue; if ($pwshExe) { Start-Process -FilePath $pwshExe.Source -Args "-NoP -Command Install-PackageProvider -Name NuGet -Force -Scope CU" -Wait } else { Write-ColorOutput Red "pwsh.exe not found after install." }
        } else { Write-ColorOutput Magenta "PS7 already installed."; $psInstallSuccess = $true }
    }


    # --- Restart Logic ---
    # ... (Keep this section exactly as before) ...
    $RestartNeeded = $InitialRun -and $psInstallSuccess -and (-not $IsPowerShell7)
    if ($RestartNeeded) {
        Write-ColorOutput Yellow "PowerShell 7 was just installed during Initial Run. Restarting script..."
        $CurrentScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Write-ColorOutput Red "FATAL: Cannot determine script path."; exit 1 }
        $ArgList = "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$CurrentScriptPath`"", "-GitHubToken", "`"$GitHubToken`"" # NO -InitialRun
        Write-ColorOutput Cyan "Starting: pwsh $ArgList"
        try { Start-Process pwsh -ArgumentList $ArgList -ErrorAction Stop; Write-ColorOutput Green "New PS7 process started. Exiting current PS5.1 session."; exit 0 }
        catch { Write-ColorOutput Red "FATAL: Failed to start new PS7 process: $($_.Exception.Message)"; exit 1 }
    } else { Write-ColorOutput Cyan "No restart needed or conditions not met." }
    Write-ColorOutput Yellow "--- End of Winget & PowerShell 7 Installation ---"
}
