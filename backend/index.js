const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
require('dotenv').config({ override: true });
const db = require('./db'); // Memanggil koneksi database dari db.js

const app = express();
app.use(cors()); // Agar bisa diakses dari aplikasi mobile
app.use(express.json()); // Agar bisa menerima input format JSON

const TOKOCRYPTO_BASE_URL = process.env.TOKOCRYPTO_BASE_URL || 'https://www.tokocrypto.com/open/v1';
const TOKOCRYPTO_PRICE_MODE = (process.env.TOKOCRYPTO_PRICE_MODE || 'mid').toLowerCase();

function pickPriceByMode(bestBid, bestAsk) {
    if (TOKOCRYPTO_PRICE_MODE === 'bid' && Number.isFinite(bestBid)) {
        return bestBid;
    }

    if (TOKOCRYPTO_PRICE_MODE === 'ask' && Number.isFinite(bestAsk)) {
        return bestAsk;
    }

    if (Number.isFinite(bestBid) && Number.isFinite(bestAsk)) {
        return (bestBid + bestAsk) / 2;
    }

    if (Number.isFinite(bestBid)) {
        return bestBid;
    }

    if (Number.isFinite(bestAsk)) {
        return bestAsk;
    }

    return null;
}

// Secret key untuk JWT diambil dari environment variable
const SECRET_KEY = process.env.JWT_SECRET;

if (!SECRET_KEY) {
    throw new Error('JWT_SECRET belum diset. Tambahkan di file .env backend.');
}

// ==========================================
// 1. ENDPOINT REGISTER (Mendaftar Akun Baru)
// ==========================================
app.post('/register', async (req, res) => {
    const { username, password, full_name } = req.body;

    if (!username || !password) {
        return res.status(400).json({ message: 'Username dan Password wajib diisi!' });
    }

    try {
        // Proses Enkripsi Password (Kriteria Dosen: Enkripsi)
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        // Simpan ke database SQL
        const query = 'INSERT INTO users (username, password, full_name) VALUES (?, ?, ?)';
        db.query(query, [username, hashedPassword, full_name], (err, results) => {
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
// 2. ENDPOINT LOGIN (Masuk Akun)
// ==========================================
app.post('/login', (req, res) => {
    const { username, password } = req.body;

    // Cari user di database
    const query = 'SELECT * FROM users WHERE username = ?';
    db.query(query, [username], async (err, results) => {
        if (err) return res.status(500).json({ error: err.message });

        if (results.length === 0) {
            return res.status(401).json({ message: 'Username tidak ditemukan!' });
        }

        const user = results[0];

        // Cek kecocokan password yang diinput dengan password terenkripsi di database
        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) {
            return res.status(401).json({ message: 'Password salah!' });
        }

        // Jika cocok, buatkan Session / Token JWT (Kriteria Dosen: Session)
        const token = jwt.sign(
            { id: user.id, username: user.username },
            SECRET_KEY,
            { expiresIn: '1h' } // Token hangus dalam 1 jam
        );

        res.json({
            message: 'Login berhasil!',
            token: token,
            user: { id: user.id, username: user.username, full_name: user.full_name }
        });
    });
});


async function getPriceFromTokocrypto(marketSymbol) {
    const response = await fetch(`${TOKOCRYPTO_BASE_URL}/market/depth?symbol=${marketSymbol}`);

    if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
    }

    const payload = await response.json();
    if (payload.code !== 0 || !payload.data) {
        throw new Error(payload.msg || 'Respons Tokocrypto tidak valid');
    }

    const bestBid = Number(payload.data?.bids?.[0]?.[0]);
    const bestAsk = Number(payload.data?.asks?.[0]?.[0]);
    const selectedPrice = pickPriceByMode(bestBid, bestAsk);

    if (Number.isFinite(selectedPrice)) {
        return {
            price: selectedPrice,
            bid: Number.isFinite(bestBid) ? bestBid : null,
            ask: Number.isFinite(bestAsk) ? bestAsk : null,
        };
    }

    throw new Error(`Order book kosong untuk ${marketSymbol}`);
}

app.get('/crypto/prices', async (_req, res) => {
    try {
        const [btcPriceUsdData, ethPriceUsdData] = await Promise.all([
            getPriceFromTokocrypto('BTC_USDT'),
            getPriceFromTokocrypto('ETH_USDT'),
        ]);

        res.json({
            source: 'tokocrypto',
            quoteAsset: 'USDT',
            priceMode: TOKOCRYPTO_PRICE_MODE,
            updatedAt: new Date().toISOString(),
            data: [
                {
                    name: 'Bitcoin',
                    symbol: 'BTC',
                    pair: 'BTCUSDT',
                    price: btcPriceUsdData.price,
                    bid: btcPriceUsdData.bid,
                    ask: btcPriceUsdData.ask,
                },
                {
                    name: 'Ethereum',
                    symbol: 'ETH',
                    pair: 'ETHUSDT',
                    price: ethPriceUsdData.price,
                    bid: ethPriceUsdData.bid,
                    ask: ethPriceUsdData.ask,
                },
            ],
        });
    } catch (error) {
        res.status(502).json({
            message: 'Gagal mengambil data harga dari Tokocrypto.',
            error: error.message,
        });
    }
});

// Jalankan server di port 3000
const PORT = Number(process.env.PORT) || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server Backend TPM berjalan di http://0.0.0.0:${PORT}`);
});