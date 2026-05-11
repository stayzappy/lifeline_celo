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
  trackedFiles: safe('git ls-files').split('\n').length,
};

fs.writeFileSync(
  "metrics/git-analytics.json",
  JSON.stringify(analytics, null, 2)
);

console.log("Git analytics generated.");
