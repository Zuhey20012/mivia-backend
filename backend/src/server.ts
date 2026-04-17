import express from 'express';
import cors from 'cors';
import health from './routes/health';
import products from './routes/products';
import vendors from './routes/vendors';
import orders from './routes/orders';
import rentals from './routes/rentals';
import couriers from './routes/couriers';

export async function createServer() {
    const app = express();
    app.use(cors());
    app.use(express.json());

    app.use('/health', health);
    app.use('/products', products);
    app.use('/vendors', vendors);
    app.use('/orders', orders);
    app.use('/rentals', rentals);
    app.use('/couriers', couriers);

    return app;
}
