const express = require('express');
const router = express.Router();
const { scanQr, getQrData } = require('../controllers/qrController');

router.post('/qr-scan', scanQr);
router.get('/qr-data', getQrData);

module.exports = router;