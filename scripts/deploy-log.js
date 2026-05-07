const fs = require("fs");
const path = require("path");

const deployment = {
  timestamp: new Date().toISOString(),
  network: "celo",
  environment: "staging",
  version: `v${Date.now()}`,
  notes: "Routine operational deployment snapshot"
};

const dir = path.join(__dirname, "..", "deployments");

if (!fs.existsSync(dir)) {
  fs.mkdirSync(dir, { recursive: true });
}

fs.writeFileSync(
  path.join(dir, `deploy-${Date.now()}.json`),
  JSON.stringify(deployment, null, 2)
);

console.log("Deployment log created.");
