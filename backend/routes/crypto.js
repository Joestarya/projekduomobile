const express = require('express');
const router = express.Router();
const db = require('../db');
const { GEMINI_API_KEY, genAI } = require('../config');
const { decryptQRData } = require('../utils/crypto');
const { 
    priceCache, 
    klineCacheUpdatedAt, 
    CACHE_TTL_MS, 
    fetchBinanceAuth, 
    refreshKlineCache 
} = require('../services/binance');

router.get('/crypto/portfolio', (req, res) => {
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

router.post('/crypto/order', (req, res) => {
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

router.post('/crypto/predict', async (req, res) => {
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

router.get('/crypto/prices', (_req, res) => {
    if (!priceCache.updatedAt) {
        return res.status(503).json({ message: 'Server sedang inisialisasi, coba lagi dalam 2 detik.' });
    }
    res.json({ source: 'binance', quoteAsset: 'USDT', updatedAt: priceCache.updatedAt, data: priceCache.data });
});

router.get('/crypto/klines', async (req, res) => {
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

router.get('/crypto/klines/batch', async (req, res) => {
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

const sseClients = new Set();

router.get('/crypto/prices/stream', (req, res) => {
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

module.exports = router;