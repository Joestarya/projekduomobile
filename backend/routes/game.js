const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth');
const { getScore, saveScore } = require('../controllers/gameController');

router.get('/game/score', authenticateToken, getScore);
router.post('/game/score', authenticateToken, saveScore);

module.exports = router;