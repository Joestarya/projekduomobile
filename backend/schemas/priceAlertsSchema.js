const db = require('../db');

const ensurePriceAlertsTable = () =>
    new Promise((resolve, reject) => {
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
            (err) => {
                if (err) return reject(err);
                return resolve();
            }
        );
    });

module.exports = { ensurePriceAlertsTable };
