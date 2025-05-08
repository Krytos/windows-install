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



function DownlaodInstallGithub($name, $repo, $filePattern) {

    $downloadPath = Join-Path $env:TEMP "$($filePattern.Split("*")[0].TrimEnd("-")).exe"

    try {
        # Fetch the latest release information
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"

        $assetUrl = $releaseInfo.assets | Where-Object { $_.name -like $filePattern } | Select-Object -ExpandProperty browser_download_url -First 1

        if (-not $assetUrl) {
            Write-Error "Could not find $filePattern in the latest release."
            return
        }

        # Download the file
        Write-ColorOutput Green "Downloading $name..."
        Start-BitsTransfer -Source $assetUrl -Destination $downloadPath

        # Check if the file was downloaded successfully
        if (Test-Path $downloadPath) {
            Write-ColorOutput Green "Download completed. Installing $name..."
            Start-Process -FilePath $downloadPath -ArgumentList "/S" -Wait
        }
        else {
            Write-Error "Failed to download $name."
        }
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}



DownlaodInstallGithub "PowerToys" "microsoft/PowerToys" "PowerToysUserSetup-*-x64.exe"