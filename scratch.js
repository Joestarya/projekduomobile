const { BINANCE_BASE_URLS } = require('./backend/config.js');
console.log(BINANCE_BASE_URLS);
fetch('https://api.binance.com/api/v3/ticker/24hr?symbols=["EURUSDT","USDTBIDR","USDTIDRT"]')
  .then(r => r.text())
  .then(console.log)
  .catch(console.error);
