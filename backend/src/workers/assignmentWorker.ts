import { Worker } from 'bullmq';
import IORedis from 'ioredis';
import { assignCourierToOrder } from '../services/assignment';
import { calculateETA } from '../services/eta';

const connection = new IORedis(process.env.REDIS_URL || 'redis://localhost:6379');

new Worker('assignments', async (job: any) => {
    try {
        const { orderId } = job?.data ?? {};
        if (!orderId) {
            console.warn('assignmentWorker: missing orderId in job', job?.id);
            return;
        }
        const courier = await assignCourierToOrder(Number(orderId));
        const eta = calculateETA(3.2);
        console.log('Worker assigned courier', courier, 'ETA', eta);
    } catch (err) {
        console.error('assignmentWorker error', err);
    }
}, { connection });

console.log('Assignment worker started');
