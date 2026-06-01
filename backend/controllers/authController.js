const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { SECRET_KEY } = require('../config');
const {
    getUserByUsername,
    createUser,
} = require('../models/userModel');

const register = async (req, res) => {
    const { full_name, username, password } = req.body;
    if (!full_name || !username || !password) {
        return res.status(400).json({ message: 'Semua field (Nama, Email, Password) harus diisi!' });
    }

    try {
        const existingUser = await getUserByUsername(username);
        if (existingUser) {
            return res.status(400).json({ message: 'Email/Username sudah digunakan!' });
        }

        const hashedPassword = await bcrypt.hash(password, 10);
        await createUser(full_name, username, hashedPassword);
        return res.status(201).json({ message: 'Registrasi berhasil!' });
    } catch (err) {
        return res.status(500).json({ error: err.message || 'Gagal memproses password' });
    }
};

const login = async (req, res) => {
    const { username, password } = req.body;

    try {
        const user = await getUserByUsername(username);
        if (!user) return res.status(401).json({ message: 'Username tidak ditemukan!' });

        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) return res.status(401).json({ message: 'Password salah!' });

        const token = jwt.sign(
            { id: user.id, username: user.username },
            SECRET_KEY,
            { expiresIn: '1h' }
        );

        return res.json({
            message: 'Login berhasil!',
            token,
            user: { id: user.id, username: user.username, full_name: user.full_name },
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

module.exports = {
    register,
    login,
};
