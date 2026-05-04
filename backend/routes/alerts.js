const express = require('express');
const router = express.Router();
const db = require('../db');
const { priceCache } = require('../services/binance');

const ensurePriceAlertsTable = new Promise((resolve) => {
  db.query(
    `
    CREATE TABLE IF NOT EXISTS price_alerts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      coin_symbol VARCHAR(10) NOT NULL,
      target_price DECIMAL(20, 8) NOT NULL,
      direction ENUM('up', 'down') NOT NULL,
      status ENUM('active', 'triggered') DEFAULT 'active',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      INDEX (user_id),
      INDEX (status)
    )
    `,
    () => resolve()
  );
});

router.get('/alerts', async (req, res) => {
  await ensurePriceAlertsTable;
  const userId = parseInt(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });
 
  db.query(
    'SELECT * FROM price_alerts WHERE user_id = ? ORDER BY id DESC',
    [userId],
    (err, results) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ alerts: results });
    }
  );
});
 
router.post('/alerts', async (req, res) => {
  await ensurePriceAlertsTable;
  const { user_id, coin_symbol, target_price, direction } = req.body;
  if (!user_id || !coin_symbol || !target_price || !direction)
    return res.status(400).json({ message: 'Semua field wajib diisi' });
  if (!['up', 'down'].includes(direction))
    return res.status(400).json({ message: "direction harus 'up' atau 'down'" });
 
  db.query(
    'INSERT INTO price_alerts (user_id, coin_symbol, target_price, direction, status) VALUES (?, ?, ?, ?, "active")',
    [user_id, coin_symbol.toUpperCase(), parseFloat(target_price), direction],
    (err, result) => {
      if (err) return res.status(500).json({ error: err.message });
      res.status(201).json({ message: 'Alert berhasil dibuat', id: result.insertId });
    }
  );
});
 
router.delete('/alerts/:id', async (req, res) => {
  await ensurePriceAlertsTable;
  const alertId = parseInt(req.params.id);
  const userId  = parseInt(req.query.user_id);
  if (!alertId || !userId) return res.status(400).json({ message: 'id dan user_id diperlukan' });
 
  db.query(
    'DELETE FROM price_alerts WHERE id = ? AND user_id = ?',
    [alertId, userId],
    (err, result) => {
      if (err) return res.status(500).json({ error: err.message });
      if (result.affectedRows === 0) return res.status(404).json({ message: 'Alert tidak ditemukan' });
      res.json({ message: 'Alert dihapus' });
    }
  );
});
 
router.get('/alerts/check', async (req, res) => {
  await ensurePriceAlertsTable;
  const userId = parseInt(req.query.user_id);
  if (!userId) return res.status(400).json({ message: 'user_id diperlukan' });
  if (!priceCache.updatedAt) return res.status(503).json({ message: 'Cache harga belum siap' });
 
  db.query(
    "SELECT * FROM price_alerts WHERE user_id = ? AND status = 'active'",
    [userId],
    (err, alerts) => {
      if (err) return res.status(500).json({ error: err.message });
 
      const triggered = [];
      for (const alert of alerts) {
        const priceData = priceCache.data.find((p) => p.symbol === alert.coin_symbol);
        if (!priceData) continue;
 
        const currentPrice = priceData.price;
        const targetPrice  = parseFloat(alert.target_price);
        const isTriggered  =
          (alert.direction === 'up'   && currentPrice >= targetPrice) ||
          (alert.direction === 'down' && currentPrice <= targetPrice);
 
        if (isTriggered) {
          triggered.push({
            id:            alert.id,
            coin_symbol:   alert.coin_symbol,
            target_price:  targetPrice,
            direction:     alert.direction,
            current_price: currentPrice,
          });
        }
      }
      res.json({ triggered });
    }
  );
});
 
router.patch('/alerts/:id/triggered', async (req, res) => {
  await ensurePriceAlertsTable;
  const alertId = parseInt(req.params.id);
  const userId  = parseInt(req.body.user_id);
  if (!alertId || !userId) return res.status(400).json({ message: 'id dan user_id diperlukan' });
 
  db.query(
    "UPDATE price_alerts SET status = 'triggered' WHERE id = ? AND user_id = ?",
    [alertId, userId],
    (err) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ message: 'Status diperbarui' });
    }
  );
});

module.exports = router;