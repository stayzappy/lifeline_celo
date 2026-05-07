const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const today = new Date().toISOString().split("T")[0];

function safe(cmd) {
  try {
    return execSync(cmd).toString().trim();
  } catch {
    return "N/A";
  }
}

const commitCount = safe("git rev-list --count HEAD");
const branch = safe("git branch --show-current");
const nodeVersion = process.version;

const report = `# Daily Operational Report

Date: ${today}

## Repository Status
- Branch: ${branch}
- Total Commits: ${commitCount}
- Node Version: ${nodeVersion}

## Generated At
${new Date().toISOString()}
`;

const dir = path.join(__dirname, "..", "reports");

if (!fs.existsSync(dir)) {
  fs.mkdirSync(dir, { recursive: true });
}

fs.writeFileSync(
  path.join(dir, `${today}.md`),
  report
);

console.log("Daily report generated.");
