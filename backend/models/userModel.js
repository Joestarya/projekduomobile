const db = require('../db');

const getUserByUsername = async (username) => {
    const [rows] = await db.promise().query(
        'SELECT * FROM users WHERE username = ?',
        [username]
    );
    return rows[0] || null;
};

const getUserByIdWithQr = async (id) => {
    const [rows] = await db.promise().query(
        'SELECT id, username, full_name, qr_data, password FROM users WHERE id = ?',
        [id]
    );
    return rows[0] || null;
};

const getUserByUsernameWithQr = async (username) => {
    const [rows] = await db.promise().query(
        'SELECT id, username, full_name, qr_data, password FROM users WHERE username = ?',
        [username]
    );
    return rows[0] || null;
};

const getUserByUsernameOrFullName = async (username, fullName) => {
    const [rows] = await db.promise().query(
        'SELECT id, username, password FROM users WHERE username = ? OR full_name = ?',
        [username, fullName]
    );
    return rows[0] || null;
};

const createUser = async (fullName, username, hashedPassword) => {
    const [result] = await db.promise().query(
        'INSERT INTO users (username, password, full_name) VALUES (?, ?, ?)',
        [username, hashedPassword, fullName]
    );
    return result.insertId;
};

const updateUserQrData = async (userId, encryptedQrData) => {
    const [result] = await db.promise().query(
        'UPDATE users SET qr_data = ? WHERE id = ?',
        [encryptedQrData, userId]
    );
    return result.affectedRows;
};

const getUserTotalScoreById = async (userId) => {
    const [rows] = await db.promise().query(
        'SELECT totalscore FROM users WHERE id = ?',
        [userId]
    );
    return rows[0] || null;
};

const updateUserTotalScore = async (userId, totalScore) => {
    const [result] = await db.promise().query(
        'UPDATE users SET totalscore = ? WHERE id = ?',
        [totalScore, userId]
    );
    return result.affectedRows;
};

module.exports = {
    getUserByUsername,
    getUserByIdWithQr,
    getUserByUsernameWithQr,
    getUserByUsernameOrFullName,
    createUser,
    updateUserQrData,
    getUserTotalScoreById,
    updateUserTotalScore,
};
