const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
require('dotenv').config({ override: true });
const db = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

// ==========================================
// BINANCE CONFIG
// ==========================================
const DEFAULT_BINANCE_BASE_URLS = [
    'https://api.binance.com/api/v3',
    'https://data-api.binance.vision/api/v3',
];

const BINANCE_BASE_URLS = (process.env.BINANCE_BASE_URLS || '')
    .split(',')
    .map((url) => url.trim().replace(/\/+$/, ''))
    .filter(Boolean);

if (BINANCE_BASE_URLS.length === 0) {
    BINANCE_BASE_URLS.push(...DEFAULT_BINANCE_BASE_URLS);
}

const SECRET_KEY = process.env.JWT_SECRET;
if (!SECRET_KEY) {
    throw new Error('JWT_SECRET belum diset. Tambahkan di file .env backend.');
}

// ==========================================
// CACHE IN-MEMORY
// ==========================================
let priceCache = {
    data: [],
    updatedAt: null,
    isFetching: false,
};

// Cache sparkline/kline per symbol: { BTCUSDT: [prices...], ... }
let klineCache = {};
let klineCacheUpdatedAt = {};
const KLINE_CACHE_TTL_MS = 5 * 60 * 1000; // 5 menit

const CACHE_TTL_MS = 1500;

// ==========================================
// HELPER: Fetch dengan fallback multi-URL
// ==========================================
async function fetchBinance(path) {
    let lastError = null;
    for (const baseUrl of BINANCE_BASE_URLS) {
        try {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 5000);
            const response = await fetch(`${baseUrl}${path}`, { signal: controller.signal });
            clearTimeout(timeout);
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return await response.json();
        } catch (error) {
            lastError = `${baseUrl} -> ${error.message}`;
        }
    }
    throw new Error(`Semua endpoint Binance gagal. ${lastError || ''}`.trim());
}

// ==========================================
// PRICE CACHE
// ==========================================
async function refreshPriceCache() {
    if (priceCache.isFetching) return;
    priceCache.isFetching = true;

    const ASSETS = [
        { symbol: 'BTCUSDT', name: 'Bitcoin', short: 'BTC' },
        { symbol: 'ETHUSDT', name: 'Ethereum', short: 'ETH' },
        { symbol: 'BNBUSDT', name: 'BNB', short: 'BNB' },
        { symbol: 'SOLUSDT', name: 'Solana', short: 'SOL' },
    ];

    try {
        // Fetch harga sekarang + 24hr stats sekaligus
        const [tickerData] = await Promise.all([
            fetchBinance(`/ticker/24hr?symbols=${JSON.stringify(ASSETS.map((a) => a.symbol))}`),
        ]);

        const parsed = Array.isArray(tickerData) ? tickerData : [tickerData];

        priceCache.data = parsed
            .map((t) => {
                const meta = ASSETS.find((a) => a.symbol === t.symbol);
                if (!meta) return null;
                return {
                    name: meta.name,
                    symbol: meta.short,
                    pair: t.symbol,
                    price: parseFloat(t.lastPrice),
                    changePercent: parseFloat(t.priceChangePercent),
                    high24h: parseFloat(t.highPrice),
                    low24h: parseFloat(t.lowPrice),
                    volume24h: parseFloat(t.volume),
                };
            })
            .filter(Boolean);

        priceCache.updatedAt = new Date().toISOString();
    } catch (err) {
        console.error('[PriceCache] Gagal refresh:', err.message);
    } finally {
        priceCache.isFetching = false;
    }
}

// ==========================================
// KLINE/SPARKLINE CACHE
// ==========================================
async function refreshKlineCache(symbol, interval = '1h', limit = 24) {
    const cacheKey = `${symbol}_${interval}_${limit}`;
    const now = Date.now();

    // Cek apakah perlu refresh
    if (
        klineCache[cacheKey] &&
        klineCacheUpdatedAt[cacheKey] &&
        now - klineCacheUpdatedAt[cacheKey] < KLINE_CACHE_TTL_MS
    ) {
        return klineCache[cacheKey];
    }

    try {
        const data = await fetchBinance(
            `/klines?symbol=${symbol}&interval=${interval}&limit=${limit}`
        );

        if (!Array.isArray(data)) throw new Error('Format kline tidak valid');

        // Binance kline format: [openTime, open, high, low, close, volume, ...]
        const klines = data.map((k) => ({
            openTime: k[0],
            open: parseFloat(k[1]),
            high: parseFloat(k[2]),
            low: parseFloat(k[3]),
            close: parseFloat(k[4]),
            volume: parseFloat(k[5]),
        }));

        klineCache[cacheKey] = klines;
        klineCacheUpdatedAt[cacheKey] = now;

        return klines;
    } catch (err) {
        console.error(`[KlineCache] Gagal refresh ${symbol}:`, err.message);
        return klineCache[cacheKey] || [];
    }
}

// Pre-warm cache saat startup
async function warmUpKlineCache() {
    const symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
    for (const sym of symbols) {
        await refreshKlineCache(sym).catch(() => {});
    }
}

// Jalankan saat server start
refreshPriceCache();
setInterval(refreshPriceCache, CACHE_TTL_MS);
warmUpKlineCache();

// Refresh kline cache setiap 5 menit
setInterval(() => {
    const symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
    symbols.forEach((sym) => refreshKlineCache(sym).catch(() => {}));
}, KLINE_CACHE_TTL_MS);

// ==========================================
// 1. ENDPOINT REGISTER
// ==========================================
// ADD qr_data COLUMN IF NOT EXISTS
db.query("ALTER TABLE users ADD COLUMN qr_data TEXT DEFAULT NULL", (err) => {
    if (err && err.code !== 'ER_DUP_FIELDNAME') {
        console.error("Gagal menambah kolom qr_data:", err);
    }
});

app.post('/qr-scan', (req, res) => {
    const { username, qr_data } = req.body;
    if (!username || !qr_data) {
        return res.status(400).json({ message: 'Username dan Data QR tidak boleh kosong' });
    }
    
    const query = 'UPDATE users SET qr_data = ? WHERE username = ?';
    db.query(query, [qr_data, username], (err, results) => {
        if (err) {
            return res.status(500).json({ error: err.message });
        }
        if (results.affectedRows === 0) {
            return res.status(404).json({ message: 'User tidak ditemukan' });
        }
        res.status(200).json({ message: 'Data QR berhasil disimpan' });
    });
});

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
// 3. ENDPOINT HARGA REALTIME
// ==========================================
app.get('/crypto/prices', (_req, res) => {
    if (!priceCache.updatedAt) {
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

// ==========================================
// 4. ENDPOINT KLINE (SPARKLINE/CHART DATA) ← NEW
// ==========================================
/**
 * GET /crypto/klines?symbol=BTCUSDT&interval=1h&limit=24
 *
 * Query params:
 *   symbol   : Binance pair (default: BTCUSDT)
 *   interval : 1m, 5m, 15m, 1h, 4h, 1d (default: 1h)
 *   limit    : jumlah candle, max 100 (default: 24)
 */
app.get('/crypto/klines', async (req, res) => {
    const symbol = (req.query.symbol || 'BTCUSDT').toUpperCase();
    const interval = req.query.interval || '1h';
    const limit = Math.min(parseInt(req.query.limit) || 24, 100);

    // Validasi interval
    const validIntervals = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d', '3d', '1w'];
    if (!validIntervals.includes(interval)) {
        return res.status(400).json({ message: `Interval tidak valid. Gunakan: ${validIntervals.join(', ')}` });
    }

    try {
        const klines = await refreshKlineCache(symbol, interval, limit);

        res.json({
            source: 'binance',
            symbol,
            interval,
            limit,
            count: klines.length,
            data: klines,
        });
    } catch (err) {
        res.status(500).json({ message: 'Gagal mengambil data kline.', error: err.message });
    }
});

// ==========================================
// 5. ENDPOINT KLINE BATCH (multiple symbols) ← NEW
// ==========================================
/**
 * GET /crypto/klines/batch?symbols=BTCUSDT,ETHUSDT&interval=1h&limit=24
 *
 * Return sparkline data untuk beberapa symbol sekaligus,
 * berguna agar Flutter hanya butuh 1 request.
 */
app.get('/crypto/klines/batch', async (req, res) => {
    const rawSymbols = req.query.symbols || 'BTCUSDT,ETHUSDT,BNBUSDT,SOLUSDT';
    const symbols = rawSymbols
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .filter(Boolean)
        .slice(0, 10); // max 10 symbols per request

    const interval = req.query.interval || '1h';
    const limit = Math.min(parseInt(req.query.limit) || 24, 100);

    try {
        const results = await Promise.all(
            symbols.map(async (symbol) => {
                const klines = await refreshKlineCache(symbol, interval, limit);
                return {
                    symbol,
                    // Return hanya close prices untuk efisiensi (sparkline)
                    closes: klines.map((k) => k.close),
                    updatedAt: klineCacheUpdatedAt[`${symbol}_${interval}_${limit}`]
                        ? new Date(klineCacheUpdatedAt[`${symbol}_${interval}_${limit}`]).toISOString()
                        : null,
                };
            })
        );

        res.json({
            source: 'binance',
            interval,
            limit,
            data: results,
        });
    } catch (err) {
        res.status(500).json({ message: 'Gagal mengambil data kline batch.', error: err.message });
    }
});

// ==========================================
// 6. SSE STREAM
// ==========================================
const sseClients = new Set();

app.get('/crypto/prices/stream', (req, res) => {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders();

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

    const heartbeat = setInterval(() => res.write(': ping\n\n'), 30000);

    req.on('close', () => {
        sseClients.delete(sendData);
        clearInterval(heartbeat);
    });
});

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

const PORT = Number(process.env.PORT) || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server Backend berjalan di http://0.0.0.0:${PORT}`);
    console.log(`Endpoints:`);
    console.log(`  GET /crypto/prices          - Harga realtime`);
    console.log(`  GET /crypto/prices/stream   - SSE stream`);
    console.log(`  GET /crypto/klines          - Kline/chart data (1 symbol)`);
    console.log(`  GET /crypto/klines/batch    - Kline/chart data (multi symbol)`);
});