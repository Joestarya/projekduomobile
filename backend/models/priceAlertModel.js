const db = require('../db');

const getAlertsByUserId = async (userId) => {
    const [rows] = await db.promise().query(
        'SELECT * FROM price_alerts WHERE user_id = ? ORDER BY id DESC',
        [userId]
    );
    return rows;
};

const createAlert = async (userId, coinSymbol, targetPrice, direction) => {
    const [result] = await db.promise().query(
        'INSERT INTO price_alerts (user_id, coin_symbol, target_price, direction, status) VALUES (?, ?, ?, ?, "active")',
        [userId, coinSymbol, targetPrice, direction]
    );
    return result.insertId;
};

const deleteAlertById = async (alertId, userId) => {
    const [result] = await db.promise().query(
        'DELETE FROM price_alerts WHERE id = ? AND user_id = ?',
        [alertId, userId]
    );
    return result.affectedRows;
};

const getActiveAlertsByUserId = async (userId) => {
    const [rows] = await db.promise().query(
        "SELECT * FROM price_alerts WHERE user_id = ? AND status = 'active'",
        [userId]
    );
    return rows;
};

const markAlertTriggered = async (alertId, userId) => {
    const [result] = await db.promise().query(
        "UPDATE price_alerts SET status = 'triggered' WHERE id = ? AND user_id = ?",
        [alertId, userId]
    );
    return result.affectedRows;
};

module.exports = {
    getAlertsByUserId,
    createAlert,
    deleteAlertById,
    getActiveAlertsByUserId,
    markAlertTriggered,
};
