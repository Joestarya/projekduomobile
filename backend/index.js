const express = require('express');
const cors = require('cors');

// Migrations
require('./migrations/create_price_alerts_table');

const alertsRoutes = require('./routes/alerts');
const authRoutes = require('./routes/auth');
const qrRoutes = require('./routes/qr');
const cryptoRoutes = require('./routes/crypto');
const gameRoutes = require('./routes/game');

const app = express();
app.use(cors());
app.use(express.json());

app.use(alertsRoutes);
app.use(authRoutes);
app.use(qrRoutes);
app.use(cryptoRoutes);
app.use(gameRoutes);

const PORT = Number(process.env.PORT) || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server Backend berjalan di http://0.0.0.0:${PORT}`);
    console.log(`Endpoints:`);
    console.log(`  POST /register              - Register user`);
    console.log(`  POST /login                 - Login user`);
    console.log(`  POST /qr-scan               - Simpan QR data (encrypted)`);
    console.log(`  GET  /qr-data               - Ambil QR data (decrypted)`);
    console.log(`  GET  /crypto/prices         - Harga realtime`);
    console.log(`  GET  /crypto/prices/stream  - SSE stream`);
    console.log(`  GET  /crypto/klines         - Kline/chart data (1 symbol)`);
    console.log(`  GET  /crypto/klines/batch   - Kline/chart data (multi symbol)`);
    console.log(`  POST /crypto/predict        - AI prediction (Gemini)`);
    console.log(`  GET  /game/score            - Ambil game score [JWT]`);
    console.log(`  POST /game/score            - Simpan game score [JWT]`);
});