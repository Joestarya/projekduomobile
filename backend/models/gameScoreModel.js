const db = require('../db');

const getScoreByUserId = async (userId) => {
    const [rows] = await db.promise().query(
        'SELECT total_score FROM game_scores WHERE user_id = ?',
        [userId]
    );
    return rows[0] || null;
};

const upsertScore = async (userId, totalScore) => {
    const [result] = await db.promise().query(
        `INSERT INTO game_scores (user_id, total_score)
         VALUES (?, ?)
         ON DUPLICATE KEY UPDATE
           total_score  = VALUES(total_score)`,
        [userId, totalScore]
    );
    return result.affectedRows;
};

module.exports = {
    getScoreByUserId,
    upsertScore,
};
