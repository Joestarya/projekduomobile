const db = require('../db');

const addTotalScoreColumn = () => {
  db.query(
    'ALTER TABLE users ADD COLUMN totalscore INT DEFAULT 0',
    (err) => {
      if (err && err.code !== 'ER_DUP_FIELDNAME') {
        console.error('Error adding users.totalscore column:', err.message);
        return;
      }
      console.log('✓ users.totalscore column ready');
    }
  );
};

addTotalScoreColumn();
