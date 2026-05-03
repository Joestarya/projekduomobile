require('dotenv').config({ override: true });
const { GoogleGenerativeAI } = require('@google/generative-ai');

// Bypass SSL cert issues for binance.com on local environment
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

// --- GEMINI CONFIG ---
const GEMINI_API_KEY = process.env.GEMINI_API_KEY ? process.env.GEMINI_API_KEY.trim() : '';

console.log("Key Terbaca:", GEMINI_API_KEY ? "Ya" : "Tidak");
if (GEMINI_API_KEY) {
    console.log("Panjang Key:", GEMINI_API_KEY.length);
    console.log("Karakter Pertama:", GEMINI_API_KEY[0]);
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

// --- BINANCE CONFIG ---
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

// --- JWT CONFIG ---
const SECRET_KEY = process.env.JWT_SECRET;
if (!SECRET_KEY) {
    throw new Error('JWT_SECRET belum diset. Tambahkan di file .env backend.');
}

module.exports = {
    GEMINI_API_KEY,
    genAI,
    BINANCE_BASE_URLS,
    SECRET_KEY
};