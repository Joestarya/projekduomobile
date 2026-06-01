const db = require('../db');

const ensureQrDataColumn = () =>
    new Promise((resolve, reject) => {
        db.query('ALTER TABLE users ADD COLUMN qr_data TEXT DEFAULT NULL', (err) => {
            if (err && err.code !== 'ER_DUP_FIELDNAME') {
                return reject(err);
            }
            return resolve();
        });
    });

module.exports = { ensureQrDataColumn };
