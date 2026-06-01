const { genAI, GEMINI_API_KEY } = require('../config');

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
                model: 'gemini-1.5-flash',
                systemInstruction: "Kamu adalah asisten virtual ramah di aplikasi trading bernama Jaga Lilin. Selalu berikan jawaban yang singkat, sopan, dan dalam bahasa Indonesia. Jangan memberikan saran keuangan yang berisiko tinggi tanpa peringatan.",
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
