// Minimal stand-in for Cloudinary's Admin API (resource lookup + destroy) and the signed server-side upload
// from a remote URL (catalogue import) used by the e2e test.
const http = require("http");
const crypto = require("crypto");
const SECRET = "cld_test_secret"; // test.env CLOUDINARY_API_SECRET
const resources = new Map();
const destroyed = [];
const uploads = [];

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
    if (req.url === "/__uploads") return send(200, uploads);
    // Signed upload of a remote file: signature = sha1(sorted params without file/api_key/signature + secret)
    if (/^\/v1_1\/[^/]+\/image\/upload$/.test(req.url) && req.method === "POST") {
      const form = new URLSearchParams(body);
      const params = [...form.entries()].filter(([k]) => !["file", "api_key", "signature", "resource_type", "cloud_name"].includes(k));
      const toSign = params.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => `${k}=${v}`).join("&");
      const expected = crypto.createHash("sha1").update(toSign + SECRET).digest("hex");
      if (form.get("signature") !== expected) return send(401, { error: { message: "Invalid Signature" } });
      const file = form.get("file") || "";
      if (!/^https:\/\//.test(file) || /broken/.test(file)) return send(400, { error: { message: "Resource not found" } });
      const publicId = form.get("public_id");
      uploads.push({ public_id: publicId, file });
      resources.set(publicId, { public_id: publicId, format: "jpg", bytes: 1000, width: 800, height: 1000 });
      return send(200, { public_id: publicId, version: 1700000000, format: "jpg", secure_url: `https://res.cloudinary.com/testcloud/image/upload/v1700000000/${publicId}.jpg` });
    }
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
