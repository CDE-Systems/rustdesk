<#
.SYNOPSIS
    Reapplies our custom-build patches after manually syncing this fork
    (and the libs/hbb_common submodule fork) with upstream.

.DESCRIPTION
    Run this AFTER you've manually synced:
      - CDE-Systems/rustdesk (this repo) with upstream rustdesk/rustdesk
      - CDE-Systems/hbb_common (submodule fork) with upstream rustdesk/hbb_common

    It reapplies:
      patches\0001-Add-secret-values-for-custom-build-in-flutter-build..patch
        -> .github/workflows/flutter-build.yml (RS_PUB_KEY / RENDEZVOUS_SERVER / API_SERVER)
      patches\hbb_common\0001-readded-env-var-build.patch
        -> libs/hbb_common/src/config.rs (option_env! overrides)

    If a patch fails to apply (upstream changed the same lines), it stops
    and tells you to resolve manually, then re-run.

.PARAMETER Push
    If set, pushes the resulting commits to origin (your fork) after a
    successful reapply.
#>
param(
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$RepoRoot = git rev-parse --show-toplevel
Set-Location $RepoRoot

function Test-PatchApplied($path, $marker) {
    return (Select-String -Path $path -Pattern $marker -SimpleMatch -Quiet)
}

Write-Host "== 1/2: Main repo patch (flutter-build.yml) ==" -ForegroundColor Cyan
$workflowFile = ".github\workflows\flutter-build.yml"
$mainPatch = "patches\0001-Add-secret-values-for-custom-build-in-flutter-build..patch"

if (Test-PatchApplied $workflowFile 'RENDEZVOUS_SERVER: "${{ secrets.RENDEZVOUS_SERVER }}"') {
    Write-Host "Already applied, skipping." -ForegroundColor Yellow
} else {
    git am --3way $mainPatch
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply main repo patch. Resolve conflicts (git status), then 'git am --continue', then re-run this script with the same flags."
        exit 1
    }
    Write-Host "Applied." -ForegroundColor Green
}

Write-Host "== 2/2: hbb_common submodule patch (config.rs) ==" -ForegroundColor Cyan
Push-Location "libs\hbb_common"
try {
    $subPatch = "..\..\patches\hbb_common\0001-readded-env-var-build.patch"
    if (Test-PatchApplied "src\config.rs" 'option_env!("RENDEZVOUS_SERVER")') {
        Write-Host "Already applied, skipping." -ForegroundColor Yellow
    } else {
        git am --3way $subPatch
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to apply hbb_common patch. Resolve conflicts inside libs/hbb_common (git status), then 'git am --continue', then re-run this script with the same flags."
            exit 1
        }
        Write-Host "Applied." -ForegroundColor Green
        if ($Push) {
            git push origin HEAD:main
        }
    }
} finally {
    Pop-Location
}

# Update the submodule pointer in the superproject if it moved.
git add libs\hbb_common
$pending = git diff --cached --name-only
if ($pending) {
    git commit -m "Update hbb_common submodule pointer after patch reapply"
    Write-Host "Committed updated submodule pointer." -ForegroundColor Green
}

if ($Push) {
    git push origin HEAD:master
    Write-Host "Pushed to origin." -ForegroundColor Green
} else {
    Write-Host "Done. Review with 'git log' / 'git status', then push manually (or re-run with -Push)." -ForegroundColor Cyan
}
