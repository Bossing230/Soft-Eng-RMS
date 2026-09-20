# Builds the Flutter web app for GitHub Pages, pointed at the deployed backend,
# and copies it into docs/. Run from the project root (the folder with pubspec.yaml):
#
#   powershell -ExecutionPolicy Bypass -File .\build-web.ps1
#
# Then publish it:
#   git add docs
#   git commit -m "Rebuild web app"
#   git push

# Your Render backend address (no trailing slash, no /api):
$Backend = "https://soft-eng-rms-backend.onrender.com"

if ($Backend -like "*YOUR-APP*") {
    Write-Error "Open build-web.ps1 and set `$Backend to your real Render address first."
    exit 1
}

flutter build web --release --base-href /Soft-Eng-RMS/ "--dart-define=API_BASE_URL=$Backend/api" "--dart-define=SOCKET_URL=$Backend"
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build failed, so docs/ was not changed."
    exit 1
}

Copy-Item build\web\* docs\ -Recurse -Force
Write-Host "Built with backend $Backend and copied to docs/. Next: git add docs, git commit, git push."