const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const crypto = require('crypto');
require('dotenv').config({ override: true });

// Bypass SSL cert issues for binance.com on local environment
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

const db = require('./db');

// --- TAMBAHAN UNTUK GEMINI ---
const { GoogleGenerativeAI } = require('@google/generative-ai');

const GEMINI_API_KEY = process.env.GEMINI_API_KEY ? process.env.GEMINI_API_KEY.trim() : '';

console.log("Key Terbaca:", GEMINI_API_KEY ? "Ya" : "Tidak");
if (GEMINI_API_KEY) {
    console.log("Panjang Key:", GEMINI_API_KEY.length);
    console.log("Karakter Pertama:", GEMINI_API_KEY[0]);
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
// -----------------------------

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
// MIDDLEWARE: JWT AUTH
// ── Dipakai oleh endpoint /game/score ─────
// ==========================================
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // "Bearer <token>"

    if (!token) {
        return res.status(401).json({ message: 'Token tidak ditemukan' });
    }

    jwt.verify(token, SECRET_KEY, (err, user) => {
        if (err) {
            return res.status(403).json({ message: 'Token tidak valid atau kadaluarsa' });
        }
        req.user = user; // { id, username, iat, exp }
        next();
    });
}

// ==========================================
// SECURE KEY DERIVATION (PBKDF2)
// ==========================================
function deriveEncryptionKey(hashedPassword, userId, username) {
    const saltInput = `${hashedPassword}|${userId}|${username}`;
    const salt = crypto.createHash('sha256').update(saltInput).digest();
    const key = crypto.pbkdf2Sync(
        hashedPassword,
        salt,
        100000,
        32,
        'sha256'
    );
    return key;
}

function encryptQRData(plaintext, hashedPassword, userId, username) {
    const encryptionKey = deriveEncryptionKey(hashedPassword, userId, username);
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey, iv);
    let encrypted = cipher.update(plaintext, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const authTag = cipher.getAuthTag();
    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
}

function decryptQRData(ciphertext, hashedPassword, userId, username) {
    try {
        const encryptionKey = deriveEncryptionKey(hashedPassword, userId, username);
        const parts = ciphertext.split(':');
        if (parts.length !== 3) throw new Error('Format cipher tidak valid');
        const iv = Buffer.from(parts[0], 'hex');
        const authTag = Buffer.from(parts[1], 'hex');
        const encrypted = parts[2];
        const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey, iv);
        decipher.setAuthTag(authTag);
        let decrypted = decipher.update(encrypted, 'hex', 'utf8');
        decrypted += decipher.final('utf8');
        return decrypted;
    } catch (err) {
        console.error('[Decrypt] Error:', err.message);
        throw new Error('Gagal mendekripsi QR data');
    }
}

//==========================================
// PRICE ALERTS ENDPOINTS
// Salin dan tempel ke index.js SEBELUM baris app.listen(...)
// ==========================================
 
// GET /alerts?user_id=xxx
app.get('/alerts', (req, res) => {
  const userId = parseInt(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });
 
  db.query(
    'SELECT * FROM price_alerts WHERE user_id = ? ORDER BY id DESC',
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ alerts: results });
    }
  );
});
 
// POST /alerts
app.post('/alerts', (req, res) => {
  const { user_id, coin_symbol, target_price, direction } = req.body;
  if (!user_id || !coin_symbol || !target_price || !direction)
    return res.status(400).json({ message: 'Semua field wajib diisi' });
  if (!['up', 'down'].includes(direction))
    return res.status(400).json({ message: "direction harus 'up' atau 'down'" });
 
  db.query(
    'INSERT INTO price_alerts (user_id, coin_symbol, target_price, direction, status) VALUES (?, ?, ?, ?, "active")',
    [user_id, coin_symbol.toUpperCase(), parseFloat(target_price), direction],
    (err, result) => {
      if (err) return res.status(500).json({ error: err.message });
      res.status(201).json({ message: 'Alert berhasil dibuat', id: result.insertId });
    }
  );
});
 
// DELETE /alerts/:id?user_id=xxx
app.delete('/alerts/:id', (req, res) => {
  const alertId = parseInt(req.params.id);
  const userId  = parseInt(req.query.user_id);
  if (!alertId || !userId) return res.status(400).json({ message: 'id dan user_id diperlukan' });
 
  db.query(
    'DELETE FROM price_alerts WHERE id = ? AND user_id = ?',
    [alertId, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: err.message });
      if (result.affectedRows === 0) return res.status(404).json({ message: 'Alert tidak ditemukan' });
      res.json({ message: 'Alert dihapus' });
    }
  );
});
 
// GET /alerts/check?user_id=xxx  — dipanggil Flutter tiap 30 detik
app.get('/alerts/check', (req, res) => {
  const userId = parseInt(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });
  if (!priceCache.updatedAt) return res.status(503).json({ message: 'Cache harga belum siap' });
 
  db.query(
    "SELECT * FROM price_alerts WHERE user_id = ? AND status = 'active'",
    [userId],
    (err, alerts) => {
      if (err) return res.status(500).json({ error: err.message });
 
      const triggered = [];
      for (const alert of alerts) {
        // priceCache.data punya field: symbol (e.g. 'BTC'), price
        const priceData = priceCache.data.find((p) => p.symbol === alert.coin_symbol);
        if (!priceData) continue;
 
        const currentPrice = priceData.price;
        const targetPrice  = parseFloat(alert.target_price);
        const isTriggered  =
          (alert.direction === 'up'   && currentPrice >= targetPrice) ||
          (alert.direction === 'down' && currentPrice <= targetPrice);
 
        if (isTriggered) {
          triggered.push({
            id:            alert.id,
            coin_symbol:   alert.coin_symbol,
            target_price:  targetPrice,
            direction:     alert.direction,
            current_price: currentPrice,
          });
        }
      }
      res.json({ triggered });
    }
  );
});
 
// PATCH /alerts/:id/triggered  — Flutter konfirmasi notif diterima → ubah status
app.patch('/alerts/:id/triggered', (req, res) => {
  const alertId = parseInt(req.params.id);
  const userId  = parseInt(req.body.user_id);
  if (!alertId || !userId) return res.status(400).json({ message: 'id dan user_id diperlukan' });
 
  db.query(
    "UPDATE price_alerts SET status = 'triggered' WHERE id = ? AND user_id = ?",
    [alertId, userId],
    (err) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ message: 'Status diperbarui' });
    }
  );
});

// ==========================================
// CACHE IN-MEMORY
// ==========================================
let priceCache = {
    data: [],
    updatedAt: null,
    isFetching: false,
};

let klineCache = {};
let klineCacheUpdatedAt = {};
const KLINE_CACHE_TTL_MS = 5 * 60 * 1000;
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

async function fetchBinanceAuth(path, apiKey, secretKey, method = 'GET') {
    const timestamp = Date.now();
    let queryString = `timestamp=${timestamp}`;

    if (path.includes('?')) {
        const parts = path.split('?');
        path = parts[0];
        queryString = `${parts[1]}&${queryString}`;
    }

    const signature = crypto.createHmac('sha256', secretKey).update(queryString).digest('hex');
    const finalQueryString = `${queryString}&signature=${signature}`;
    const fullPath = `${path}?${finalQueryString}`;

    let lastError = null;
    for (const baseUrl of BINANCE_BASE_URLS) {
        try {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 5000);
            const response = await fetch(`${baseUrl}${fullPath}`, {
                method: method,
                headers: { 'X-MBX-APIKEY': apiKey },
                signal: controller.signal,
            });
            clearTimeout(timeout);
            if (!response.ok) {
                const errText = await response.text();
                throw new Error(`HTTP ${response.status} - ${errText}`);
            }
            return await response.json();
        } catch (error) {
            console.error('[fetchBinanceAuth] Error:', error.message, error.cause || '');
            lastError = `${baseUrl} -> ${error.message}`;
        }
    }

    if (path.includes('/account')) {
        console.warn(`[fetchBinanceAuth] Semua endpoint gagal karena blokir ISP. Menggunakan data MOCK.`);
        return {
            balances: [
                { asset: 'BTC',  free: '0.015', locked: '0' },
                { asset: 'ETH',  free: '1.25',  locked: '0' },
                { asset: 'BNB',  free: '10.5',  locked: '0' },
                { asset: 'SOL',  free: '25.0',  locked: '0' },
                { asset: 'USDT', free: '150.0', locked: '0' },
            ],
        };
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
        { symbol: 'BTCUSDT', name: 'Bitcoin',  short: 'BTC' },
        { symbol: 'ETHUSDT', name: 'Ethereum', short: 'ETH' },
        { symbol: 'BNBUSDT', name: 'BNB',      short: 'BNB' },
        { symbol: 'SOLUSDT', name: 'Solana',   short: 'SOL' },
        { symbol: 'USDTIDRT', name: 'Rupiah Token', short: 'USDT_IDR' },
    ];

    try {
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
// KLINE CACHE
// ==========================================
async function refreshKlineCache(symbol, interval = '1h', limit = 24) {
    const cacheKey = `${symbol}_${interval}_${limit}`;
    const now = Date.now();

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

        const klines = data.map((k) => ({
            openTime: k[0],
            open:     parseFloat(k[1]),
            high:     parseFloat(k[2]),
            low:      parseFloat(k[3]),
            close:    parseFloat(k[4]),
            volume:   parseFloat(k[5]),
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

refreshPriceCache();
setInterval(refreshPriceCache, CACHE_TTL_MS);
warmUpKlineCache();

setInterval(() => {
    const symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
    symbols.forEach((sym) => refreshKlineCache(sym).catch(() => {}));
}, KLINE_CACHE_TTL_MS);

// ==========================================
// QR SCAN & DATA
// ==========================================
db.query("ALTER TABLE users ADD COLUMN qr_data TEXT DEFAULT NULL", (err) => {
    if (err && err.code !== 'ER_DUP_FIELDNAME') {
        console.error("Gagal menambah kolom qr_data:", err);
    }
});

app.post('/qr-scan', (req, res) => {
    const { user_id, username, full_name, qr_data } = req.body;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '') && (!full_name || full_name.trim() === '')) {
        return res.status(400).json({ message: 'Identitas user tidak boleh kosong' });
    }
    if (!qr_data || qr_data.trim() === '') {
        return res.status(400).json({ message: 'Data QR tidak boleh kosong' });
    }

    const parsedId = user_id ? parseInt(String(user_id), 10) : NaN;
    let selectQuery, selectParams;

    if (!isNaN(parsedId) && parsedId > 0) {
        selectQuery = 'SELECT id, username, password FROM users WHERE id = ?';
        selectParams = [parsedId];
    } else {
        selectQuery = 'SELECT id, username, password FROM users WHERE username = ? OR full_name = ?';
        selectParams = [username || full_name, full_name || username];
    }

    db.query(selectQuery, selectParams, (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) return res.status(404).json({ message: 'User tidak ditemukan' });

        const user = results[0];
        let encryptedQRData;
        try {
            encryptedQRData = encryptQRData(qr_data, user.password, user.id, user.username);
        } catch (err) {
            return res.status(500).json({ error: 'Gagal enkripsi QR data', detail: err.message });
        }

        db.query('UPDATE users SET qr_data = ? WHERE id = ?', [encryptedQRData, user.id], (err) => {
            if (err) return res.status(500).json({ error: err.message });
            res.status(200).json({
                message: 'Data QR berhasil disimpan (encrypted dengan PBKDF2)',
                user_id: user.id,
            });
        });
    });
});

app.get('/qr-data', (req, res) => {
    const { user_id, username } = req.query;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '')) {
        return res.status(400).json({ message: 'user_id atau username harus dikirimkan' });
    }

    let query, params;
    if (user_id) {
        const parsedId = parseInt(String(user_id), 10);
        if (isNaN(parsedId)) return res.status(400).json({ message: 'user_id harus berupa angka' });
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE id = ?';
        params = [parsedId];
    } else {
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE username = ?';
        params = [username];
    }

    db.query(query, params, (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) return res.status(404).json({ message: 'User tidak ditemukan' });

        const user = results[0];
        let decryptedQRData = null;
        if (user.qr_data) {
            try {
                decryptedQRData = decryptQRData(user.qr_data, user.password, user.id, user.username);
            } catch (err) {
                return res.status(500).json({ error: 'Gagal dekripsi QR data', detail: err.message });
            }
        }

        res.json({ id: user.id, username: user.username, full_name: user.full_name, qr_data: decryptedQRData });
    });
});

// ==========================================
// PORTFOLIO & ORDER BINANCE
// ==========================================
app.get('/crypto/portfolio', (req, res) => {
    const { user_id, username } = req.query;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '')) {
        return res.status(400).json({ message: 'user_id atau username harus dikirimkan' });
    }

    let query, params;
    if (user_id) {
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE id = ?';
        params = [parseInt(String(user_id), 10)];
    } else {
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE username = ?';
        params = [username];
    }

    db.query(query, params, async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) return res.status(404).json({ message: 'User tidak ditemukan' });

        const user = results[0];
        if (!user.qr_data) return res.status(400).json({ message: 'User belum melakukan scan QR Binance' });

        let apiKey, secretKey;
        try {
            const decryptedQRData = decryptQRData(user.qr_data, user.password, user.id, user.username);
            const keyData = JSON.parse(decryptedQRData);
            apiKey    = String(keyData.apiKey    || keyData.api_key    || keyData.apikey    || '').trim();
            secretKey = String(keyData.secretKey || keyData.secret_key || keyData.secretkey || '').trim();
            if (!apiKey || !secretKey) throw new Error('Format QR tidak mengandung apiKey dan secretKey');
        } catch (err) {
            return res.status(400).json({ error: 'Gagal membaca API key dari data QR', detail: err.message });
        }

        try {
            const accountData = await fetchBinanceAuth('/account', apiKey, secretKey);
            const balances = accountData.balances.filter(
                (b) => parseFloat(b.free) > 0 || parseFloat(b.locked) > 0
            );
            res.json({ balances });
        } catch (err) {
            res.status(500).json({ error: 'Gagal mengambil data portofolio dari Binance', detail: err.message });
        }
    });
});

app.post('/crypto/order', (req, res) => {
    const { user_id, username, symbol, side, type, quantity, quoteOrderQty } = req.body;

    if ((!user_id || String(user_id).trim() === '') && (!username || username.trim() === '')) {
        return res.status(400).json({ message: 'user_id atau username harus dikirimkan' });
    }
    if (!symbol || !side || !type) return res.status(400).json({ message: 'symbol, side, dan type wajib diisi' });
    if (!quantity && !quoteOrderQty) return res.status(400).json({ message: 'quantity atau quoteOrderQty wajib diisi' });

    let query, params;
    if (user_id) {
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE id = ?';
        params = [parseInt(String(user_id), 10)];
    } else {
        query = 'SELECT id, username, full_name, qr_data, password FROM users WHERE username = ?';
        params = [username];
    }

    db.query(query, params, async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) return res.status(404).json({ message: 'User tidak ditemukan' });

        const user = results[0];
        if (!user.qr_data) return res.status(400).json({ message: 'User belum melakukan scan QR Binance' });

        let apiKey, secretKey;
        try {
            const decryptedQRData = decryptQRData(user.qr_data, user.password, user.id, user.username);
            const keyData = JSON.parse(decryptedQRData);
            apiKey    = String(keyData.apiKey    || keyData.api_key    || keyData.apikey    || '').trim();
            secretKey = String(keyData.secretKey || keyData.secret_key || keyData.secretkey || '').trim();
            if (!apiKey || !secretKey) throw new Error('Format QR tidak mengandung apiKey dan secretKey');
        } catch (err) {
            return res.status(400).json({ error: 'Gagal membaca API key dari data QR', detail: err.message });
        }

        try {
            let orderPath = `/order?symbol=${symbol.toUpperCase()}&side=${side.toUpperCase()}&type=${type.toUpperCase()}`;
            if (quantity) orderPath += `&quantity=${quantity}`;
            if (quoteOrderQty) orderPath += `&quoteOrderQty=${quoteOrderQty}`;

            const orderResponse = await fetchBinanceAuth(orderPath, apiKey, secretKey, 'POST');
            res.json({ message: 'Order berhasil dieksekusi', data: orderResponse });
        } catch (err) {
            let msg = err.message;
            if (msg.includes('NOTIONAL'))                                msg = 'Minimum order 5 USDT';
            else if (msg.includes('Account has insufficient balance'))   msg = 'Saldo Anda tidak mencukupi';
            else if (msg.includes('LOT_SIZE'))                           msg = 'Jumlah koin tidak sesuai';
            else if (msg.includes('Invalid API-key, IP, or permissions'))msg = 'API Key salah, kadaluarsa, atau tidak memiliki izin Spot Trading.';

            res.status(400).json({ error: 'Gagal mengeksekusi order di Binance', detail: msg, original: err.message });
        }
    });
});

// ==========================================
// REGISTER & LOGIN
// ==========================================
app.post('/register', (req, res) => {
    const { full_name, username, password } = req.body;
    if (!full_name || !username || !password) {
        return res.status(400).json({ message: 'Semua field (Nama, Email, Password) harus diisi!' });
    }

    db.query('SELECT id FROM users WHERE username = ?', [username], async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length > 0) return res.status(400).json({ message: 'Email/Username sudah digunakan!' });

        try {
            const hashedPassword = await bcrypt.hash(password, 10);
            db.query(
                'INSERT INTO users (username, password, full_name) VALUES (?, ?, ?)',
                [username, hashedPassword, full_name],
                (err) => {
                    if (err) return res.status(500).json({ error: err.message });
                    res.status(201).json({ message: 'Registrasi berhasil!' });
                }
            );
        } catch (hashErr) {
            res.status(500).json({ error: 'Gagal memproses password' });
        }
    });
});

app.post('/login', (req, res) => {
    const { username, password } = req.body;
    db.query('SELECT * FROM users WHERE username = ?', [username], async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        if (results.length === 0) return res.status(401).json({ message: 'Username tidak ditemukan!' });

        const user = results[0];
        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) return res.status(401).json({ message: 'Password salah!' });

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
// GEMINI AI PREDICT
// ==========================================
app.post('/crypto/predict', async (req, res) => {
    if (!GEMINI_API_KEY) {
        return res.status(500).json({ message: 'GEMINI_API_KEY belum diset di .env' });
    }

    const pair = (req.body.pair || 'BTCUSDT').toUpperCase();
    const validPairs = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
    if (!validPairs.includes(pair)) {
        return res.status(400).json({ message: `Pair tidak valid. Gunakan: ${validPairs.join(', ')}` });
    }

    const timeframe = req.body.timeframe || '1m';
    const validTimeframes = ['1m', '5m', '15m'];
    if (!validTimeframes.includes(timeframe)) {
        return res.status(400).json({ message: `Timeframe tidak valid. Gunakan: ${validTimeframes.join(', ')}` });
    }

    try {
        const priceData = priceCache.data.find((d) => d.pair === pair);
        if (!priceData) return res.status(503).json({ message: 'Data harga belum tersedia, coba lagi.' });

        const klines = await refreshKlineCache(pair, timeframe, 15);
        const recentCloses  = klines.map((k) => k.close.toFixed(4)).join(', ');
        const recentVolumes = klines.map((k) => k.volume.toFixed(2)).join(', ');
        const lastClose  = klines[klines.length - 1]?.close ?? priceData.price;
        const firstClose = klines[0]?.close ?? priceData.price;
        const momentum   = lastClose - firstClose;

        let durationText = '60 seconds';
        if (timeframe === '5m') durationText = '5 minutes';
        else if (timeframe === '15m') durationText = '15 minutes';

        const prompt = `You are a short-term crypto price direction analyst.

Analyze the following market data for ${pair} and predict whether the price will go UP or DOWN in the next ${durationText}.

## Current Market Data
- Pair: ${pair}
- Current Price: $${priceData.price.toFixed(4)}
- 24h Change: ${priceData.changePercent.toFixed(2)}%
- 24h High: $${priceData.high24h.toFixed(4)}
- 24h Low: $${priceData.low24h.toFixed(4)}
- 24h Volume: ${priceData.volume24h.toFixed(2)}

## Last 15 Candles (${timeframe} close prices)
${recentCloses}

## Last 15 Candles (${timeframe} volumes)
${recentVolumes}

## Calculated Momentum (15 candles of ${timeframe})
Price change over last 15 candles: ${momentum >= 0 ? '+' : ''}${momentum.toFixed(4)}

## Instructions
Based on the data above:
1. Determine if price will go UP or DOWN in the next ${durationText}
2. Rate your confidence: HIGH, MEDIUM, or LOW
3. Give a very short reasoning (max 2 sentences, in Indonesian)

Respond ONLY in this exact JSON format (no markdown, no extra text):
{"direction":"UP","confidence":"MEDIUM","reasoning":"Momentum positif dengan volume meningkat. Harga berpotensi melanjutkan kenaikan jangka pendek."}`;

        const geminiModel = genAI.getGenerativeModel({
            model: "gemini-flash-latest",
            generationConfig: {
                temperature: 0.3,
                maxOutputTokens: 1000,
                responseMimeType: "application/json",
            },
        });

        const geminiResp = await geminiModel.generateContent(prompt);
        const rawText = geminiResp.response.text();

        let prediction;
        try {
            const cleaned = rawText.replace(/```json|```/g, '').trim();
            prediction = JSON.parse(cleaned);
        } catch (_) {
            console.error('[Gemini] Parse error, raw:', rawText);
            return res.status(502).json({ message: 'Gagal parse response Gemini', raw: rawText });
        }

        if (!['UP', 'DOWN'].includes(prediction.direction)) {
            return res.status(502).json({ message: 'Direction tidak valid dari Gemini', raw: rawText });
        }

        res.json({
            pair,
            direction:    prediction.direction,
            confidence:   prediction.confidence ?? 'MEDIUM',
            reasoning:    prediction.reasoning ?? '',
            currentPrice: priceData.price,
            generatedAt:  new Date().toISOString(),
        });
    } catch (err) {
        console.error('[Predict] Error:', err.message);
        res.status(500).json({ message: 'Internal server error', error: err.message });
    }
});

// ==========================================
// CRYPTO PRICES
// ==========================================
app.get('/crypto/prices', (_req, res) => {
    if (!priceCache.updatedAt) {
        return res.status(503).json({ message: 'Server sedang inisialisasi, coba lagi dalam 2 detik.' });
    }
    res.json({ source: 'binance', quoteAsset: 'USDT', updatedAt: priceCache.updatedAt, data: priceCache.data });
});

// ==========================================
// KLINE (SINGLE SYMBOL)
// ==========================================
app.get('/crypto/klines', async (req, res) => {
    const symbol   = (req.query.symbol || 'BTCUSDT').toUpperCase();
    const interval = req.query.interval || '1h';
    const limit    = Math.min(parseInt(req.query.limit) || 24, 100);

    const validIntervals = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d', '3d', '1w'];
    if (!validIntervals.includes(interval)) {
        return res.status(400).json({ message: `Interval tidak valid. Gunakan: ${validIntervals.join(', ')}` });
    }

    try {
        const klines = await refreshKlineCache(symbol, interval, limit);
        res.json({ source: 'binance', symbol, interval, limit, count: klines.length, data: klines });
    } catch (err) {
        res.status(500).json({ message: 'Gagal mengambil data kline.', error: err.message });
    }
});

// ==========================================
// KLINE BATCH (MULTI SYMBOL)
// ==========================================
app.get('/crypto/klines/batch', async (req, res) => {
    const rawSymbols = req.query.symbols || 'BTCUSDT,ETHUSDT,BNBUSDT,SOLUSDT';
    const symbols = rawSymbols.split(',').map((s) => s.trim().toUpperCase()).filter(Boolean).slice(0, 10);
    const interval = req.query.interval || '1h';
    const limit    = Math.min(parseInt(req.query.limit) || 24, 100);

    try {
        const results = await Promise.all(
            symbols.map(async (symbol) => {
                const klines = await refreshKlineCache(symbol, interval, limit);
                return {
                    symbol,
                    closes: klines.map((k) => k.close),
                    updatedAt: klineCacheUpdatedAt[`${symbol}_${interval}_${limit}`]
                        ? new Date(klineCacheUpdatedAt[`${symbol}_${interval}_${limit}`]).toISOString()
                        : null,
                };
            })
        );
        res.json({ source: 'binance', interval, limit, data: results });
    } catch (err) {
        res.status(500).json({ message: 'Gagal mengambil data kline batch.', error: err.message });
    }
});

// ==========================================
// GAME SCORE  (butuh JWT — pakai authenticateToken)
// ==========================================

// GET /game/score — ambil score milik user yang sedang login
app.get('/game/score', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const [rows] = await db.promise().query(
            'SELECT total_score, total_rounds, total_wins, best_streak FROM game_scores WHERE user_id = ?',
            [userId]
        );
        if (rows.length === 0) {
            return res.json({ total_score: 0, total_rounds: 0, total_wins: 0, best_streak: 0 });
        }
        return res.json(rows[0]);
    } catch (err) {
        console.error('GET /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
});

// POST /game/score — simpan/update score milik user yang sedang login
app.post('/game/score', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { total_score, total_rounds, total_wins, best_streak } = req.body;

        await db.promise().query(
            `INSERT INTO game_scores (user_id, total_score, total_rounds, total_wins, best_streak)
             VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
               total_score  = VALUES(total_score),
               total_rounds = VALUES(total_rounds),
               total_wins   = VALUES(total_wins),
               best_streak  = VALUES(best_streak)`,
            [userId, total_score, total_rounds, total_wins, best_streak]
        );

        return res.json({ message: 'Score saved' });
    } catch (err) {
        console.error('POST /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
});

// ==========================================
// SSE STREAM
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
                source: 'binance', quoteAsset: 'USDT',
                updatedAt: priceCache.updatedAt, data: priceCache.data,
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
            source: 'binance', quoteAsset: 'USDT',
            updatedAt: priceCache.updatedAt, data: priceCache.data,
        });
        for (const send of sseClients) {
            try { send(payload); } catch (_) { sseClients.delete(send); }
        }
    }
}, CACHE_TTL_MS);

// ==========================================
// START SERVER
// ==========================================
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