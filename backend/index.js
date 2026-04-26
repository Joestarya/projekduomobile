const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const db = require('./db'); // Memanggil koneksi database dari db.js

const app = express();
app.use(cors()); // Agar bisa diakses dari aplikasi mobile
app.use(express.json()); // Agar bisa menerima input format JSON

// Secret key untuk JWT (Nantinya baiknya ditaruh di file .env)
const SECRET_KEY = 'kunci_rahasia_projek_tpm';

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

// Jalankan server di port 3000
const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server Backend TPM berjalan di http://0.0.0.0:${PORT}`);
});