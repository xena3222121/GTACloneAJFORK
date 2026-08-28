# Autosave: commits and pushes any changes in this Godot project to GitHub.
# Runs silently on a schedule (see Task Scheduler task "GTA-Clone-Godot Autosave").
# Safe to run by hand too - it only commits if something actually changed.

$repoPath = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $repoPath "tools\autosave.log"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -Path $logPath -Value $line
}

Set-Location $repoPath

# NOTE: git (a native exe) writes routine info to stderr (e.g. CRLF warnings).
# Redirecting that into PowerShell's error stream would otherwise get logged
# as a false "error" - `*> $null` discards it without treating it as fatal.
git add -A *> $null

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Log "No changes, skipped."
    exit 0
}

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
git commit -m "Autosave: $stamp" *> $null

git push origin main *> $null
if ($LASTEXITCODE -eq 0) {
    Log "Committed and pushed ($stamp)."
} else {
    Log "Committed locally, but push failed (offline or auth issue) ($stamp)."
}
