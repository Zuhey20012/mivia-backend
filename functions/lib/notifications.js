"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendOrderDispatchedAlerts = sendOrderDispatchedAlerts;
const admin = __importStar(require("firebase-admin"));
const twilio_1 = __importDefault(require("twilio"));
const mail_1 = __importDefault(require("@sendgrid/mail"));
const twilioAccountSid = process.env.TWILIO_ACCOUNT_SID;
const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
const twilioClient = twilioAccountSid && twilioAuthToken ? (0, twilio_1.default)(twilioAccountSid, twilioAuthToken) : null;
if (process.env.SENDGRID_API_KEY) {
    mail_1.default.setApiKey(process.env.SENDGRID_API_KEY);
}
/**
 * Multi-Channel Messaging Hub (FCM, SMS & SMTP)
 * Partitions operational messages across high-speed push (<300ms),
 * SMS fallback for arrival/gate alerts, and legally compliant tax invoices.
 */
async function sendOrderDispatchedAlerts(order) {
    // 1. Silent Data Push to update customer tracking screen HUD (< 300 ms)
    if (order.customerFcmToken) {
        try {
            await admin.messaging().send({
                token: order.customerFcmToken,
                notification: {
                    title: "Courier En Route! ⚡",
                    body: `${order.courierName} is heading to your dropoff location.`,
                },
                data: {
                    orderId: order.id,
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: { priority: "high" },
            });
        }
        catch (e) {
            console.warn("FCM push dispatch notice:", e);
        }
    }
    // 2. High-Priority SMS Fallback via Twilio (1-3s)
    if (order.customerPhone && twilioClient && process.env.TWILIO_SENDER_NUMBER) {
        try {
            await twilioClient.messages.create({
                body: `[Malvoya] Your courier ${order.courierName} has picked up order #${order.id}. Track live in app.`,
                from: process.env.TWILIO_SENDER_NUMBER,
                to: order.customerPhone,
            });
        }
        catch (e) {
            console.warn("Twilio SMS dispatch notice:", e);
        }
    }
    // 3. Legally compliant tax receipt via SendGrid (5-15s)
    if (order.customerEmail && process.env.SENDGRID_API_KEY) {
        try {
            await mail_1.default.send({
                to: order.customerEmail,
                from: process.env.RECEIPTS_SENDER_EMAIL || "receipts@malvoya.com",
                subject: `Your Malvoya Tax Invoice & Receipt for Order #${order.id}`,
                html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; color: #1e1e2d; padding: 24px; border: 1px solid #e2e8f0; border-radius: 12px;">
            <h2 style="color: #0f172a; margin-top: 0;">Thank you for your Malvoya order!</h2>
            <p style="color: #475569;">Your luxury boutique delivery is fulfilled and on its way.</p>
            <div style="background-color: #f8fafc; padding: 16px; border-radius: 8px; margin: 16px 0;">
              <p style="margin: 4px 0;"><strong>Order ID:</strong> #${order.id}</p>
              <p style="margin: 4px 0;"><strong>Assigned Courier:</strong> ${order.courierName}</p>
              <p style="margin: 4px 0;"><strong>Boutique Items:</strong> ${order.itemSummary}</p>
              <p style="margin: 4px 0; font-size: 16px; color: #0f172a;"><strong>Total Charged:</strong> ${order.totalFormatted} <span style="font-size: 12px; color: #64748b;">(Finnish ALV 25.5% Included)</span></p>
            </div>
            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;" />
            <p style="font-size: 11px; color: #94a3b8; line-height: 1.5;">
              Malvoya Oy • Mannerheimintie, Helsinki, Finland • Business ID: FI3392819-2<br/>
              PSD2 SCA Compliant • Zero-Touch Card Tokenization via Google Pay & Stripe Connect
            </p>
          </div>
        `,
            });
        }
        catch (e) {
            console.warn("SendGrid email dispatch notice:", e);
        }
    }
}
//# sourceMappingURL=notifications.js.map