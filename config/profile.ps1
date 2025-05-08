$env:VIRTUAL_ENV_DISABLE_PROMPT = 1
# $env:POSH_GIT_ENABLED = $true
[Console]::OutputEncoding = [Text.Encoding]::UTF8
# oh-my-posh init pwsh --config "~\krytos.omp.json" | Invoke-Expression
oh-my-posh init pwsh --config "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/easy-term.omp.json" | Invoke-Expression
Import-Module -Name Terminal-Icons

Set-Alias denv Deactivate

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
venv

function gitclone {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The URL of the Git repository to clone.")]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Optional: The name or full path for the target directory. If not specified, it's derived from the repository URL.")]
        [string]$TargetDirectoryName
    )

    # Stop on first error for this function's scope
    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    try {
        # Determine the name of the directory Git will create/use
        $defaultRepoName = ($RepositoryUrl.Split('/')[-1] -replace '\.git$', '')

        $actualTargetNameOrPath = "" # This is what 'git clone' will use as its second argument, if provided
        $finalPathToCd = ""          # This is the absolute path we will 'cd' into

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
            # No TargetDirectoryName specified, git clones into a dir named after the repo in the current location
            # No second argument for git clone in this case.
            $finalPathToCd = Join-Path -Path (Get-Location).Path -ChildPath $defaultRepoName
        }

        Write-Verbose "Repository URL: $RepositoryUrl"
        Write-Verbose "Default derived repository name: $defaultRepoName"
        if ($PSBoundParameters.ContainsKey('TargetDirectoryName')) {
            Write-Verbose "User-specified target: $TargetDirectoryName"
        }
        Write-Verbose "Final path to change into: $finalPathToCd"

        if (Test-Path -Path $finalPathToCd -PathType Container) {
            Write-Warning "Target directory '$finalPathToCd' already exists. Skipping clone and attempting to CD."
        }
        else {
            $gitArgs = @("clone", $RepositoryUrl)
            if ($PSBoundParameters.ContainsKey('TargetDirectoryName')) {
                $gitArgs += $actualTargetNameOrPath
            }

            Write-Host "Attempting to clone '$RepositoryUrl' into '$($finalPathToCd)'..."
            if ($PSCmdlet.ShouldProcess($RepositoryUrl, "Clone repository and place into '$($finalPathToCd)'")) {
                # & git @gitArgs # Using Start-Process for better error handling of external commands
                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = "git"
                $processInfo.Arguments = $gitArgs -join " "
                $processInfo.RedirectStandardError = $true
                $processInfo.RedirectStandardOutput = $true
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                $process.Start() | Out-Null
                $process.WaitForExit()

                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()

                if ($stdout) { Write-Verbose "Git STDOUT: $stdout" }

                if ($process.ExitCode -ne 0) {
                    throw "Git clone failed with exit code $($process.ExitCode). STDERR: $stderr"
                }
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
        if ($_.Exception.InnerException) {
            Write-Error "Inner Exception: $($_.Exception.InnerException.Message)"
        }
        # You might want to throw again if this function is part of a larger script
        # that needs to know about the failure.
        # throw $_
    }
    finally {
        # Restore original ErrorActionPreference
        $ErrorActionPreference = $ErrorActionPreferenceBackup
    }
}

# then stash away the prompt() that oh-my-posh sets
$Global:__OriginalPrompt = $function:Prompt

function Global:__Terminal-Get-LastExitCode {
    if ($? -eq $True) { return 0 }
    $LastHistoryEntry = $(Get-History -Count 1)
    $IsPowerShellError = $Error[0].InvocationInfo.HistoryId -eq $LastHistoryEntry.Id
    if ($IsPowerShellError) { return -1 }
    return $LastExitCode
}

function prompt {
    $gle = $(__Terminal-Get-LastExitCode);
    $LastHistoryEntry = $(Get-History -Count 1)
    if ($Global:__LastHistoryId -ne -1) {
        if ($LastHistoryEntry.Id -eq $Global:__LastHistoryId) {
            $out += "`e]133;D`a"
        }
        else {
            $out += "`e]133;D;$gle`a"
        }
    }
    $loc = $($executionContext.SessionState.Path.CurrentLocation);
    $out += "`e]133;A$([char]07)";
    $out += "`e]9;9;`"$loc`"$([char]07)";

    $out += $Global:__OriginalPrompt.Invoke(); # <-- This line adds the original prompt back

    $out += "`e]133;B$([char]07)";
    $Global:__LastHistoryId = $LastHistoryEntry.Id
    return $out
}