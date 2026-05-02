const { GoogleGenerativeAI } = require("@google/generative-ai");
require('dotenv').config();

async function checkAvailableModels() {
  const apiKey = process.env.GEMINI_API_KEY;
  const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`;

  try {
    console.log("Mengecek daftar model untuk API Key kamu...");
    console.log("URL YANG DIPANGGIL:", apiKey ? url : "Tidak ada API Key yang terbaca. Pastikan .env sudah benar.");
    const response = await fetch(url);
    const data = await response.json();

    if (data.error) {
      console.error("Error dari Google:", data.error.message);
      return;
    }

    console.log("--- DAFTAR MODEL YANG TERSEDIA ---");
    data.models.forEach(model => {
      if (model.supportedGenerationMethods.includes("generateContent")) {
        console.log("- " + model.name.replace("models/", ""));
      }
    });
    console.log("----------------------------------");
    console.log("Gunakan salah satu nama di atas pada getGenerativeModel({ model: 'NAMA_MODEL' })");

  } catch (error) {
    console.error("Gagal mengambil data:", error.message);
  }
}

checkAvailableModels();