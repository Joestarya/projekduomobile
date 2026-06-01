const express = require('express');
const router = express.Router();
const {
    getPortfolio,
    createOrder,
    predictPrice,
    getPrices,
    getKlines,
    getKlinesBatch,
    getPricesStream,
} = require('../controllers/cryptoController');

router.get('/crypto/portfolio', getPortfolio);
router.post('/crypto/order', createOrder);
router.post('/crypto/predict', predictPrice);
router.get('/crypto/prices', getPrices);
router.get('/crypto/klines', getKlines);
router.get('/crypto/klines/batch', getKlinesBatch);
router.get('/crypto/prices/stream', getPricesStream);

module.exports = router;