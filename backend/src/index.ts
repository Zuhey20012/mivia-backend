import 'dotenv/config';
import { createServer } from './server';

const port = process.env.PORT || 4000;

createServer().then(app => {
    app.listen(port, () => {
        console.log(`MIVIA backend listening on port ${port}`);
    });
}).catch(err => {
    console.error('Failed to start server', err);
    process.exit(1);
});
