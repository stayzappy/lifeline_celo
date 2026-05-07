$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "Running operational workflows..."

npm run daily
npm run benchmark
npm run ecosystem
npm run deploylog

git add .

git commit -m "chore: operational reports update ($timestamp)"

git push

Write-Host "Operational update complete."
