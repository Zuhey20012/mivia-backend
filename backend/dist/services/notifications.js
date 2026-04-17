"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendNotification = sendNotification;
async function sendNotification(userId, message) {
    console.log(`Notify user ${userId}: ${message}`);
    return { ok: true, delivered: true };
}
