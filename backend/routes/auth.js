const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../db');
const { SECRET_KEY } = require('../config');

router.post('/register', (req, res) => {
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

router.post('/login', (req, res) => {
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

module.exports = router;