const crypto = require('crypto');
const { BINANCE_BASE_URLS } = require('../config');

let priceCache = {
    data: [],
    updatedAt: null,
    isFetching: false,
};

let klineCache = {};
let klineCacheUpdatedAt = {};
const KLINE_CACHE_TTL_MS = 5 * 60 * 1000;
const CACHE_TTL_MS = 1500;

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

module.exports = {
    priceCache,
    klineCacheUpdatedAt,
    CACHE_TTL_MS,
    fetchBinanceAuth,
    refreshKlineCache,
    warmUpKlineCache
};