const express = require('express');
const router = express.Router();
const db = require('../db');
const authenticateToken = require('../middleware/auth');

router.get('/game/score', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const [rows] = await db.promise().query(
            'SELECT total_score, total_rounds, total_wins, best_streak FROM game_scores WHERE user_id = ?',
            [userId]
        );
        if (rows.length === 0) {
            return res.json({ total_score: 0, total_rounds: 0, total_wins: 0, best_streak: 0 });
        }
        return res.json(rows[0]);
    } catch (err) {
        console.error('GET /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
});

router.post('/game/score', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { total_score, total_rounds, total_wins, best_streak } = req.body;

        await db.promise().query(
            `INSERT INTO game_scores (user_id, total_score, total_rounds, total_wins, best_streak)
             VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
               total_score  = VALUES(total_score),
               total_rounds = VALUES(total_rounds),
               total_wins   = VALUES(total_wins),
               best_streak  = VALUES(best_streak)`,
            [userId, total_score, total_rounds, total_wins, best_streak]
        );

        return res.json({ message: 'Score saved' });
    } catch (err) {
        console.error('POST /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
});

module.exports = router;