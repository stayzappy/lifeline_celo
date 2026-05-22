$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "Running Flutter analysis..."

flutter analyze *> reports/flutter-analysis.txt

Write-Host "Running Flutter tests..."

flutter test *> reports/test-results.txt

Write-Host "Building Flutter web..."

flutter build web *> reports/build-output.txt

Write-Host "Generating metrics..."

npm run fluttermetrics
npm run gitmetrics
npm run celometrics
npm run report

Write-Host "Git operations..."

git add .

git commit -m "chore: operational telemetry update ($timestamp)"

git push

Write-Host "Operational workflow complete."
