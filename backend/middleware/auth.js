const jwt = require('jsonwebtoken');
const { SECRET_KEY } = require('../config');

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // "Bearer <token>"

    if (!token) {
        return res.status(401).json({ message: 'Token tidak ditemukan' });
    }

    jwt.verify(token, SECRET_KEY, (err, user) => {
        if (err) {
            return res.status(403).json({ message: 'Token tidak valid atau kadaluarsa' });
        }
        req.user = user; // { id, username, iat, exp }
        next();
    });
}

module.exports = authenticateToken;