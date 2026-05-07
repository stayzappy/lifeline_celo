Write-Host "Setting up advanced operational automation..."

# ---------------------------------------------------
# Create folders
# ---------------------------------------------------

$folders = @(
    "scripts",
    "reports",
    "metrics",
    "ecosystem",
    "deployments"
)

foreach ($folder in $folders) {
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Host "Created folder: $folder"
    }
}

# ---------------------------------------------------
# Ensure package.json exists
# ---------------------------------------------------

if (!(Test-Path "package.json")) {
    npm init -y | Out-Null
    Write-Host "Created package.json"
}

# ---------------------------------------------------
# flutter-metrics.js
# ---------------------------------------------------

$flutterMetrics = @'
const fs = require("fs");
const path = require("path");

const metrics = {
  generatedAt: new Date().toISOString(),
  buildExists: fs.existsSync("build/web"),
  reportFiles: fs.readdirSync("reports").length,
  metricsFiles: fs.readdirSync("metrics").length,
};

fs.writeFileSync(
  path.join("metrics", "flutter-metrics.json"),
  JSON.stringify(metrics, null, 2)
);

console.log("Flutter metrics generated.");
'@

Set-Content -Path "scripts/flutter-metrics.js" -Value $flutterMetrics

# ---------------------------------------------------
# git-metrics.js
# ---------------------------------------------------

$gitMetrics = @'
const fs = require("fs");
const { execSync } = require("child_process");

function safe(cmd) {
  try {
    return execSync(cmd).toString().trim();
  } catch {
    return "N/A";
  }
}

const analytics = {
  generatedAt: new Date().toISOString(),
  totalCommits: safe("git rev-list --count HEAD"),
  branch: safe("git branch --show-current"),
  lastCommit: safe("git log -1 --pretty=%B"),
  trackedFiles: safe("git ls-files | wc -l"),
};

fs.writeFileSync(
  "metrics/git-analytics.json",
  JSON.stringify(analytics, null, 2)
);

console.log("Git analytics generated.");
'@

Set-Content -Path "scripts/git-metrics.js" -Value $gitMetrics

# ---------------------------------------------------
# celo-metrics.js
# ---------------------------------------------------

$celoMetrics = @'
const fs = require("fs");
const https = require("https");

const payload = JSON.stringify({
  jsonrpc: "2.0",
  method: "eth_blockNumber",
  params: [],
  id: 1
});

const options = {
  hostname: "forno.celo.org",
  path: "/",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": payload.length
  }
};

const req = https.request(options, (res) => {
  let data = "";

  res.on("data", (chunk) => {
    data += chunk;
  });

  res.on("end", () => {
    const parsed = JSON.parse(data);

    const metrics = {
      generatedAt: new Date().toISOString(),
      latestBlockHex: parsed.result
    };

    fs.writeFileSync(
      "metrics/celo-metrics.json",
      JSON.stringify(metrics, null, 2)
    );

    console.log("CELO metrics generated.");
  });
});

req.write(payload);
req.end();
'@

Set-Content -Path "scripts/celo-metrics.js" -Value $celoMetrics

# ---------------------------------------------------
# generate-report.js
# ---------------------------------------------------

$generateReport = @'
const fs = require("fs");

const report = `
# Operational Report

Generated: ${new Date().toISOString()}

## Included Reports
- Flutter metrics
- Git analytics
- CELO telemetry
- Flutter analysis
- Flutter tests
- Web build

## Repository Status
Operational automation active.
`;

fs.writeFileSync(
  "reports/operational-report.md",
  report
);

console.log("Operational report generated.");
'@

Set-Content -Path "scripts/generate-report.js" -Value $generateReport

# ---------------------------------------------------
# Update package.json
# ---------------------------------------------------

$json = Get-Content "package.json" -Raw | ConvertFrom-Json

if (-not $json.scripts) {
    $json | Add-Member -MemberType NoteProperty -Name scripts -Value ([PSCustomObject]@{})
}

$json.scripts | Add-Member -Force -MemberType NoteProperty -Name fluttermetrics -Value "node scripts/flutter-metrics.js"
$json.scripts | Add-Member -Force -MemberType NoteProperty -Name gitmetrics -Value "node scripts/git-metrics.js"
$json.scripts | Add-Member -Force -MemberType NoteProperty -Name celometrics -Value "node scripts/celo-metrics.js"
$json.scripts | Add-Member -Force -MemberType NoteProperty -Name report -Value "node scripts/generate-report.js"

$json | ConvertTo-Json -Depth 10 | Set-Content "package.json"

Write-Host "Updated package.json"

# ---------------------------------------------------
# github.ps1
# ---------------------------------------------------

$githubPs1 = @'
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
'@

Set-Content -Path "github.ps1" -Value $githubPs1

Write-Host ""
Write-Host "=========================================="
Write-Host "Advanced operational automation installed"
Write-Host "=========================================="
Write-Host ""
Write-Host "Run with:"
Write-Host ".\github.ps1"