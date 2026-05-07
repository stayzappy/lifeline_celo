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
