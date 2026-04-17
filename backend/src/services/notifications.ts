export async function sendNotification(userId: number, message: string) {
    console.log(`Notify user ${userId}: ${message}`);
    return { ok: true, delivered: true };
}
