const {
    getUserTotalScoreById,
    updateUserTotalScore,
} = require('../models/userModel');

const getScore = async (req, res) => {
    try {
        const userId = req.user.id;
        const score = await getUserTotalScoreById(userId);
        const totalScore = score && Number.isFinite(score.totalscore)
            ? score.totalscore
            : 0;
        return res.json({ total_score: totalScore });
    } catch (err) {
        console.error('GET /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
};

const saveScore = async (req, res) => {
    try {
        const userId = req.user.id;
        const { total_score } = req.body;
        const parsedScore = Number(total_score);

        if (!Number.isFinite(parsedScore)) {
            return res.status(400).json({ message: 'Invalid total_score' });
        }

        await updateUserTotalScore(userId, parsedScore);
        return res.json({ message: 'Score saved' });
    } catch (err) {
        console.error('POST /game/score error:', err);
        return res.status(500).json({ message: 'Server error' });
    }
};

module.exports = {
    getScore,
    saveScore,
};
