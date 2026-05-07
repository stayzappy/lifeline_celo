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
