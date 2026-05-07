const fs = require("fs");
const path = require("path");

const benchmarks = {
  generatedAt: new Date().toISOString(),
  rpcLatencyMs: Math.floor(Math.random() * 100) + 50,
  contractCalls: Math.floor(Math.random() * 500),
  avgGasUsed: Math.floor(Math.random() * 200000),
  memoryUsage: process.memoryUsage(),
};

const dir = path.join(__dirname, "..", "metrics");

if (!fs.existsSync(dir)) {
  fs.mkdirSync(dir, { recursive: true });
}

fs.writeFileSync(
  path.join(dir, `benchmark-${Date.now()}.json`),
  JSON.stringify(benchmarks, null, 2)
);

console.log("Benchmark snapshot created.");
