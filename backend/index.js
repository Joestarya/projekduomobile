const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
require('dotenv').config({ override: true });
const db = require('./db');

const app = express();
app.use(cors());
app.use(express.json());


const DEFAULT_BINANCE_BASE_URLS = [
    'https://api.binance.com/api/v3/ticker/price',
    'https://data-api.binance.vision/api/v3/ticker/price',
];

const BINANCE_BASE_URLS = (process.env.BINANCE_BASE_URLS || '')
    .split(',')
    .map((url) => url.trim())
    .filter(Boolean);

if (BINANCE_BASE_URLS.length === 0) {
    BINANCE_BASE_URLS.push(...DEFAULT_BINANCE_BASE_URLS);
}

const SECRET_KEY = process.env.JWT_SECRET;
if (!SECRET_KEY) {
    throw new Error('JWT_SECRET belum diset. Tambahkan di file .env backend.');
}

// ==========================================
// CACHE IN-MEMORY (Solusi real-time tanpa
// hammering Binance setiap request masuk)
// ==========================================
let priceCache = {
    data: [],
    updatedAt: null,
    isFetching: false,
};

const CACHE_TTL_MS = 1500; // Update cache setiap 1.5 detik

async function getPriceFromBinance(symbol) {
    let lastError = null;
    for (const baseUrl of BINANCE_BASE_URLS) {
        try {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 4000);

            const response = await fetch(`${baseUrl}?symbol=${symbol}`, {
                signal: controller.signal,
            });
            clearTimeout(timeout);

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            const data = await response.json();
            const price = Number(data.price);
            if (!Number.isFinite(price)) throw new Error('Data harga tidak valid');

            return price;
        } catch (error) {
            lastError = `${baseUrl} -> ${error.message}`;
        }
    }
    throw new Error(`Semua endpoint Binance gagal untuk ${symbol}. ${lastError || ''}`.trim());
}

/**
 * Refresh cache harga di background.
 * Dipanggil secara periodik agar endpoint /crypto/prices
 * selalu merespons dengan data terbaru tanpa nunggu fetch.
 */
async function refreshPriceCache() {
    if (priceCache.isFetching) return;
    priceCache.isFetching = true;

    try {
        const [btcPrice, ethPrice] = await Promise.all([
            getPriceFromBinance('BTCUSDT'),
            getPriceFromBinance('ETHUSDT'),
        ]);

        priceCache.data = [
            { name: 'Bitcoin', symbol: 'BTC', pair: 'BTCUSDT', price: btcPrice },
            { name: 'Ethereum', symbol: 'ETH', pair: 'ETHUSDT', price: ethPrice },
        ];
        priceCache.updatedAt = new Date().toISOString();
    } catch (err) {
        console.error('[PriceCache] Gagal refresh:', err.message);
    } finally {
        priceCache.isFetching = false;
    }
}

// Jalankan refresh cache saat server start & setiap 1.5 detik
refreshPriceCache();
setInterval(refreshPriceCache, CACHE_TTL_MS);

// ==========================================
// 1. ENDPOINT REGISTER
// ==========================================
app.post('/register', async (req, res) => {
    const { username, password, full_name } = req.body;

    if (!username || !password) {
        return res.status(400).json({ message: 'Username dan Password wajib diisi!' });
    }

    try {
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        const query = 'INSERT INTO users (username, password, full_name) VALUES (?, ?, ?)';
        db.query(query, [username, hashedPassword, full_name], (err) => {
            if (err) {
                if (err.code === 'ER_DUP_ENTRY') {
                    return res.status(400).json({ message: 'Username sudah terpakai!' });
                }
                return res.status(500).json({ error: err.message });
            }
            res.status(201).json({ message: 'Registrasi berhasil, silakan login.' });
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ==========================================
// 2. ENDPOINT LOGIN
// ==========================================
app.post('/login', (req, res) => {
    const { username, password } = req.body;

    const query = 'SELECT * FROM users WHERE username = ?';
    db.query(query, [username], async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });

        if (results.length === 0) {
            return res.status(401).json({ message: 'Username tidak ditemukan!' });
        }

        const user = results[0];
        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) {
            return res.status(401).json({ message: 'Password salah!' });
        }

        const token = jwt.sign(
            { id: user.id, username: user.username },
            SECRET_KEY,
            { expiresIn: '1h' }
        );

        res.json({
            message: 'Login berhasil!',
            token,
            user: { id: user.id, username: user.username, full_name: user.full_name },
        });
    });
});

// ==========================================
// 3. ENDPOINT GET HARGA — DARI CACHE
// Respons instan karena data sudah di-cache
// ==========================================
app.get('/crypto/prices', (_req, res) => {
    if (!priceCache.updatedAt) {
        // Cache belum siap (baru start), tunggu sebentar lalu coba lagi
        return res.status(503).json({
            message: 'Server sedang inisialisasi, coba lagi dalam 2 detik.',
        });
    }

    res.json({
        source: 'binance',
        quoteAsset: 'USDT',
        updatedAt: priceCache.updatedAt,
        data: priceCache.data,
    });
});

const sseClients = new Set();

app.get('/crypto/prices/stream', (req, res) => {
    // Set headers untuk SSE
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // Penting untuk Nginx
    res.flushHeaders();

    // Kirim data awal
    const sendData = () => {
        if (priceCache.updatedAt) {
            const payload = JSON.stringify({
                source: 'binance',
                quoteAsset: 'USDT',
                updatedAt: priceCache.updatedAt,
                data: priceCache.data,
            });
            res.write(`data: ${payload}\n\n`);
        }
    };

    sendData();
    sseClients.add(sendData);

    // Heartbeat setiap 30 detik (cegah timeout)
    const heartbeat = setInterval(() => {
        res.write(': ping\n\n');
    }, 30000);

    // Cleanup saat client disconnect
    req.on('close', () => {
        sseClients.delete(sendData);
        clearInterval(heartbeat);
    });
});

// Broadcast ke semua SSE client setiap kali cache di-update
setInterval(() => {
    if (sseClients.size > 0 && priceCache.updatedAt) {
        const payload = JSON.stringify({
            source: 'binance',
            quoteAsset: 'USDT',
            updatedAt: priceCache.updatedAt,
            data: priceCache.data,
        });
        for (const send of sseClients) {
            try {
                send(payload);
            } catch (_) {
                sseClients.delete(send);
            }
        }
    }
}, CACHE_TTL_MS);

// ==========================================
// SERVER START
// ==========================================
const PORT = Number(process.env.PORT) || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server Backend TPM berjalan di http://0.0.0.0:${PORT}`);
    console.log(`SSE stream tersedia di http://0.0.0.0:${PORT}/crypto/prices/stream`);
});