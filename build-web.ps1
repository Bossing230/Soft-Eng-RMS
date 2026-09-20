# Builds the Flutter web app for GitHub Pages, pointed at the deployed backend,
# and copies it into docs/. Run from the project root (the folder with pubspec.yaml):
#
#   powershell -ExecutionPolicy Bypass -File .\build-web.ps1
#
# Then publish it:
#   git add docs
#   git commit -m "Rebuild web app"
#   git push
#
# Afterwards, open https://bossing230.github.io/Soft-Eng-RMS/build-info.txt
# to see which build is really published (it shows the time of the last build).

# Your Render backend address (no trailing slash, no /api):
$Backend = "https://soft-eng-rms-backend.onrender.com"

if ($Backend -like "*YOUR-APP*") {
    Write-Error "Open build-web.ps1 and set `$Backend to your real Render address first."
    exit 1
}

$buildArgs = @(
    "build", "web", "--release",
    "--base-href", "/Soft-Eng-RMS/",
    "--dart-define=API_BASE_URL=$Backend/api",
    "--dart-define=SOCKET_URL=$Backend"
)

# Turn off Flutter's offline cache (the service worker). With it on, browsers keep
# showing the previous version of the site after a deploy. Not every Flutter
# version has this option, so check before using it.
$help = flutter build web --help 2>&1 | Out-String
if ($help -match "pwa-strategy") {
    $buildArgs += "--pwa-strategy=none"
} else {
    Write-Warning "This Flutter version has no --pwa-strategy option, so the default offline cache stays on."
}

flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build failed, so docs/ was not changed."
    exit 1
}

Copy-Item build\web\* docs\ -Recurse -Force

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Set-Content -Path docs\build-info.txt -Value @("Built: $stamp", "Backend: $Backend")

Write-Host ""
Write-Host "Built at $stamp with backend $Backend and copied to docs/."
Write-Host "Next: git add docs, git commit, git push. Then open .../Soft-Eng-RMS/build-info.txt to confirm it is live."