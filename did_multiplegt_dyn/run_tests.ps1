# run_tests.ps1 -- PowerShell entry point; runs run_tests.sh with Git Bash.
# Same options as run_tests.sh, e.g.
#   .\run_tests.ps1 --stata-ado installed --r-pkg installed --py-pkg installed
$bash = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) { $bash = (Get-Command bash -ErrorAction SilentlyContinue).Source }
if (-not $bash) { Write-Error "Git Bash not found. Install Git for Windows or run run_tests.sh from a bash shell."; exit 2 }
& $bash "$PSScriptRoot/run_tests.sh" @args
exit $LASTEXITCODE
