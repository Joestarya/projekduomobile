const { priceCache } = require('../services/binance');
const {
    getAlertsByUserId,
    createAlert,
    deleteAlertById,
    getActiveAlertsByUserId,
    markAlertTriggered,
} = require('../models/priceAlertModel');
const { ensurePriceAlertsTable } = require('../schemas/priceAlertsSchema');

const getAlerts = async (req, res) => {
    const userId = parseInt(req.query.user_id, 10);
    if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });

    try {
        await ensurePriceAlertsTable();
        const alerts = await getAlertsByUserId(userId);
        return res.json({ alerts });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

const createAlertHandler = async (req, res) => {
    const { user_id, coin_symbol, target_price, direction } = req.body;
    if (!user_id || !coin_symbol || !target_price || !direction) {
        return res.status(400).json({ message: 'Semua field wajib diisi' });
    }
    if (!['up', 'down'].includes(direction)) {
        return res.status(400).json({ message: "direction harus 'up' atau 'down'" });
    }

    try {
        await ensurePriceAlertsTable();
        const insertId = await createAlert(
            user_id,
            coin_symbol.toUpperCase(),
            parseFloat(target_price),
            direction
        );
        return res.status(201).json({ message: 'Alert berhasil dibuat', id: insertId });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

const deleteAlertHandler = async (req, res) => {
    const alertId = parseInt(req.params.id, 10);
    const userId = parseInt(req.query.user_id, 10);
    if (!alertId || !userId) {
        return res.status(400).json({ message: 'id dan user_id diperlukan' });
    }

    try {
        await ensurePriceAlertsTable();
        const affectedRows = await deleteAlertById(alertId, userId);
        if (affectedRows === 0) {
            return res.status(404).json({ message: 'Alert tidak ditemukan' });
        }
        return res.json({ message: 'Alert dihapus' });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

const checkAlerts = async (req, res) => {
    const userId = parseInt(req.query.user_id, 10);
    if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });
    if (!priceCache.updatedAt) {
        return res.status(503).json({ message: 'Cache harga belum siap' });
    }

    try {
        await ensurePriceAlertsTable();
        const alerts = await getActiveAlertsByUserId(userId);

        const triggered = [];
        for (const alert of alerts) {
            const priceData = priceCache.data.find((p) => p.symbol === alert.coin_symbol);
            if (!priceData) continue;

            const currentPrice = priceData.price;
            const targetPrice = parseFloat(alert.target_price);
            const isTriggered =
                (alert.direction === 'up' && currentPrice >= targetPrice) ||
                (alert.direction === 'down' && currentPrice <= targetPrice);

            if (isTriggered) {
                triggered.push({
                    id: alert.id,
                    coin_symbol: alert.coin_symbol,
                    target_price: targetPrice,
                    direction: alert.direction,
                    current_price: currentPrice,
                });
            }
        }

        return res.json({ triggered });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

const markAlertTriggeredHandler = async (req, res) => {
    const alertId = parseInt(req.params.id, 10);
    const userId = parseInt(req.body.user_id, 10);
    if (!alertId || !userId) {
        return res.status(400).json({ message: 'id dan user_id diperlukan' });
    }

    try {
        await ensurePriceAlertsTable();
        await markAlertTriggered(alertId, userId);
        return res.json({ message: 'Status diperbarui' });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
};

module.exports = {
    getAlerts,
    createAlertHandler,
    deleteAlertHandler,
    checkAlerts,
    markAlertTriggeredHandler,
};
