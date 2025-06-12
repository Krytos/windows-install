$env:VIRTUAL_ENV_DISABLE_PROMPT = 1
$env:POSH_GIT_ENABLED = $true
[Console]::OutputEncoding = [Text.Encoding]::UTF8

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/config/krytos.omp.json" | Invoke-Expression
}
else {
    Write-Warning "oh-my-posh command not found. Skipping Posh initialization."
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module -Name Terminal-Icons
}
else {
    Write-Warning "Terminal-Icons module not found. Skipping import."
}

Set-Alias denv Deactivate -ErrorAction SilentlyContinue

function mklink ($target, $link) {
    New-Item -Path $link -ItemType SymbolicLink -Value $target
}

function venv {
    $venvDirs = Get-ChildItem -Directory -Path . | Where-Object { $_.Name -match '^\.?venv' }
    foreach ($dir in $venvDirs) {
        $activatePath = Join-Path $dir.Name "Scripts\Activate.ps1"
        if (Test-Path $activatePath) {
            & $activatePath
            Write-Host "Activated virtual environment in $($dir.FullName)" -ForegroundColor Green
            return
        }
    }
}

function gitclone {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The URL of the Git repository to clone.")]
        [string]$RepositoryUrl,
        [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Optional: The name or full path for the target directory.")]
        [string]$TargetDirectoryName
    )

    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    try {
        $defaultRepoName = ($RepositoryUrl.Split('/')[-1] -replace '\.git$', '')
        $actualTargetNameOrPath = ""
        $finalPathToCd = ""

        if ($PSBoundParameters.ContainsKey('TargetDirectoryName')) {
            $actualTargetNameOrPath = $TargetDirectoryName
            if ([System.IO.Path]::IsPathRooted($TargetDirectoryName)) {
                $finalPathToCd = $TargetDirectoryName
            }
            else {
                $finalPathToCd = Join-Path -Path (Get-Location).Path -ChildPath $TargetDirectoryName
            }
        }
        else {
            $finalPathToCd = Join-Path -Path (Get-Location).Path -ChildPath $defaultRepoName
        }

        if (Test-Path -Path $finalPathToCd -PathType Container) {
            Write-Warning "Target directory '$finalPathToCd' already exists. Skipping clone and attempting to CD."
        }
        else {
            $gitArgs = @("clone", $RepositoryUrl)
            if ($PSBoundParameters.ContainsKey('TargetDirectoryName')) {
                $gitArgs += $actualTargetNameOrPath
            }
            Write-Host "Attempting to clone '$RepositoryUrl' into '$($finalPathToCd)'..."
            if ($PSCmdlet.ShouldProcess($RepositoryUrl, "Clone repository")) {
                & git @gitArgs
                Write-Host "Successfully cloned."
            }
        }

        if (Test-Path -Path $finalPathToCd -PathType Container) {
            Write-Host "Changing directory to '$finalPathToCd'..."
            if ($PSCmdlet.ShouldProcess($finalPathToCd, "Set Location (cd)")) {
                Set-Location -Path $finalPathToCd
                Write-Host "Current directory: $(Get-Location)"
            }
        }
        else {
            throw "Cloned directory '$finalPathToCd' not found. Cannot change directory."
        }
    }
    catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
    }
    finally {
        $ErrorActionPreference = $ErrorActionPreferenceBackup
    }
}


venv

if (-not (Test-Path Variable:Global:__LastHistoryId)) {
    $Global:__LastHistoryId = -1
}


if (-not $Global:__OriginalPrompt) {
    $Global:__OriginalPrompt = $function:Prompt
}

function Global:__Terminal-Get-LastExitCode {

    if ($?) { return 0 }


    $LastHistoryEntry = Get-History -Count 1 -ErrorAction SilentlyContinue

    $IsPowerShellError = $false
    if ($Error.Count -gt 0 -and $LastHistoryEntry -and $Error[0].InvocationInfo) {

        if ($Error[0].InvocationInfo.HistoryId -eq $LastHistoryEntry.Id) {
            $IsPowerShellError = $true
        }
    }

    if ($IsPowerShellError) {
        return -1
    }
    return $LastExitCode
}

function prompt {

    $out = ""

    $esc = "$([char]27)"
    $bel = "$([char]7)"
    if ($Global:__LastHistoryId -ne -1) {
        $gle = __Terminal-Get-LastExitCode
        $LastHistoryEntry = Get-History -Count 1 -ErrorAction SilentlyContinue
        $currentCommandId = if ($LastHistoryEntry) { $LastHistoryEntry.Id } else { -2 }

        if ($currentCommandId -eq $Global:__LastHistoryId) {
            $out += "$esc]133;D$bel"
        }
        else {
            $out += "$esc]133;D;$gle$bel"
        }
    }

    $out += "$esc]133;A$bel"
    $loc = $executionContext.SessionState.Path.CurrentLocation.Path
    $out += "$esc]9;9;`"$loc`"$bel"

    $out += $Global:__OriginalPrompt.Invoke()
    $out += "$esc]133;B$bel"
    $CurrentPromptLastHistoryEntry = Get-History -Count 1 -ErrorAction SilentlyContinue
    $Global:__LastHistoryId = if ($CurrentPromptLastHistoryEntry) { $CurrentPromptLastHistoryEntry.Id } else { $Global:__LastHistoryId } # Keep old if no new history

    return $out
}