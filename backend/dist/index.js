"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const server_1 = require("./server");
const port = process.env.PORT || 4000;
(0, server_1.createServer)().then(app => {
    app.listen(port, () => {
        console.log(`MIVIA backend listening on port ${port}`);
    });
}).catch(err => {
    console.error('Failed to start server', err);
    process.exit(1);
});
