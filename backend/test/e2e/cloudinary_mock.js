// Minimal stand-in for Cloudinary's Admin API (resource lookup + destroy) used by the e2e test.
const http = require("http");
const resources = new Map();
const destroyed = [];

http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    const send = (code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
    if (req.url === "/__seed" && req.method === "POST") {
      const { publicId, info } = JSON.parse(body);
      resources.set(publicId, { public_id: publicId, format: "mp4", bytes: 1000, ...info });
      return send(200, { ok: true });
    }
    if (req.url === "/__destroyed") return send(200, destroyed);
    const m = req.url.match(/^\/v1_1\/[^/]+\/resources\/(image|video)\/(upload|authenticated)\/(.+)$/);
    if (m && req.method === "GET") {
      const id = decodeURIComponent(m[3]);
      return resources.has(id) ? send(200, resources.get(id)) : send(404, { error: { message: "not found" } });
    }
    if (/\/destroy$/.test(req.url) && req.method === "POST") {
      destroyed.push(new URLSearchParams(body).get("public_id"));
      return send(200, { result: "ok" });
    }
    send(404, { error: "unknown" });
  });
}).listen(12222, () => console.log("cloudinary mock on 12222"));
