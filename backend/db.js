const mysql = require('mysql2');
require('dotenv').config({ override: true });

const connection = mysql.createConnection({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'tpm_projek'
});

connection.connect((err) => {
  if (err) {
    console.error('Error connecting to database: ' + err.stack);
    return;
  }
  console.log('Terhubung ke database SQL sebagai id ' + connection.threadId);
});

// INI YANG PALING PENTING DAN BIKIN ERROR TADI:
module.exports = connection;