const express = require('express');
const router = express.Router();
const {
  getAlerts,
  createAlertHandler,
  deleteAlertHandler,
  checkAlerts,
  markAlertTriggeredHandler,
} = require('../controllers/alertsController');

router.get('/alerts', getAlerts);
router.post('/alerts', createAlertHandler);
router.delete('/alerts/:id', deleteAlertHandler);
router.get('/alerts/check', checkAlerts);
router.patch('/alerts/:id/triggered', markAlertTriggeredHandler);

module.exports = router;