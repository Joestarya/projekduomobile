const { genAI, GEMINI_API_KEY, GEMINI_MODEL } = require('../config');

// In-memory session map. For production, store session history in DB or Redis.
const chatSessionMap = new Map();

const chatWithBot = async (req, res) => {
    if (!GEMINI_API_KEY) {
        return res.status(500).json({ message: 'GEMINI_API_KEY belum diset di .env' });
    }

    const { text, sessionId = 'default' } = req.body;
    if (!text) {
        return res.status(400).json({ message: 'Pesan tidak boleh kosong' });
    }

    try {
        let chatSession = chatSessionMap.get(sessionId);

        if (!chatSession) {
            const model = genAI.getGenerativeModel({
                model: GEMINI_MODEL,
                systemInstruction: `Kamu adalah asisten virtual ramah di aplikasi trading kripto bernama Jaga Lilin.

                Jaga Lilin adalah platform trading kripto sederhana yang dirancang untuk pemula maupun trader kasual. Platform ini terhubung langsung dengan API Binance sehingga data harga yang ditampilkan selalu real-time.

                Aset kripto yang tersedia di Jaga Lilin:
                - Bitcoin (BTC)
                - Ethereum (ETH)
                - Solana (SOL)

                Fitur-fitur yang tersedia di aplikasi Jaga Lilin:
                1. Portfolio - Melihat kepemilikan aset kripto pengguna beserta nilai saat ini
                2. Buy & Sell - Melakukan transaksi jual dan beli aset kripto yang tersedia
                3. Multi Kurs - Melihat harga aset dalam berbagai mata uang (misalnya IDR, USD, EUR, dll)
                4. Koneksi API Binance - Menghubungkan akun Binance pengguna ke aplikasi Jaga Lilin
                5. Game - Fitur permainan ringan yang tersedia di dalam aplikasi

                Tugas utamamu:
                - Membantu pengguna memahami cara menggunakan fitur-fitur di atas
                - Menjelaskan istilah dasar trading kripto seperti candlestick, market order, limit order, dll
                - Membantu pengguna memahami portofolio dan riwayat transaksi mereka
                - Mengarahkan pengguna ke fitur yang tepat sesuai kebutuhan mereka

                Aturan penting:
                - Selalu gunakan bahasa Indonesia yang ramah dan mudah dipahami
                - Berikan jawaban yang singkat dan to the point
                - Hanya bahas BTC, ETH, dan SOL jika ditanya soal aset kripto spesifik
                - Jika membahas harga atau pergerakan pasar, selalu sertakan peringatan bahwa pasar kripto sangat volatil dan berisiko
                - JANGAN memberikan saran "beli sekarang" atau "jual sekarang" secara langsung
                - Jika pengguna bertanya tentang strategi investasi besar atau berisiko tinggi, ingatkan untuk DYOR (Do Your Own Research) dan hanya gunakan dana yang siap hilang
                - Jangan membahas topik di luar konteks aplikasi Jaga Lilin`,                
                                generationConfig: {
                    temperature: 0.7,
                    topP: 0.8,
                    topK: 40,
                    maxOutputTokens: 800,
                }
            });
            chatSession = model.startChat();
            chatSessionMap.set(sessionId, chatSession);
        }

        const result = await chatSession.sendMessage(text);
        const responseText = result.response.text();

        return res.json({ response: responseText });
    } catch (err) {
        console.error('[Chatbot Error]', err);
        return res.status(500).json({ message: 'Terjadi kesalahan pada chatbot', error: err.message });
    }
};

module.exports = {
    chatWithBot
};
