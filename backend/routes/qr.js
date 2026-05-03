const express = require('express');
const router = express.Router();
const db = require('../db');
const { encryptQRData, decryptQRData } = require('../utils/crypto');

db.query("ALTER TABLE users ADD COLUMN qr_data TEXT DEFAULT NULL", (err) => {
    if (err && err.code !== 'ER_DUP_FIELDNAME') {
        console.error("Gagal menambah kolom qr_data:", err);
    }
});

router.post('/qr-scan', (req, res) => {
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

router.get('/qr-data', (req, res) => {
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

module.exports = router;