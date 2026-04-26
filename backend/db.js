const mysql = require('mysql2');

const connection = mysql.createConnection({
  host: 'localhost',
  user: 'root',      
  password: '12345',      
  database: 'tpm_projek'
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