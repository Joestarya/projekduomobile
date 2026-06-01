const mysql = require('mysql2');
require('dotenv').config({ override: true });

const connection = mysql.createConnection({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

connection.connect((err) => {
  if (err) {
    console.error('Error connecting to database: ' + err.stack);
    return;
  }
  console.log('Terhubung ke database SQL sebagai id ' + connection.threadId);
});

module.exports = connection;