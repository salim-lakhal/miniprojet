const express = require('express');
const mysql = require('mysql2');
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");
const app = express();

app.set('view engine', 'ejs');
app.use(express.urlencoded({ extended: true }));

let db;

async function getSecret() {
  const client = new SecretsManagerClient({ region: "us-east-1" });
  const response = await client.send(new GetSecretValueCommand({ SecretId: "Mydbsecret" }));
  return JSON.parse(response.SecretString);
}

async function initDB() {
  const secret = await getSecret();
  console.log('Connecting to DB at:', secret.host);
  db = mysql.createConnection({
    host: secret.host,
    user: secret.user,
    password: secret.password,
    database: secret.database,
    port: secret.port || 3306
  });
  db.connect((err) => {
    if (err) { console.error('DB error:', err); process.exit(1); }
    console.log('Connected to RDS MySQL');
    db.query(`CREATE TABLE IF NOT EXISTS students (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255),
      address VARCHAR(255),
      city VARCHAR(255),
      state VARCHAR(255),
      email VARCHAR(255),
      phone VARCHAR(20)
    )`, (err) => {
      if (err) console.error('Create table error:', err);
      else console.log('Table ready');
    });
  });
}

app.get('/', (req, res) => {
  db.query('SELECT * FROM students', (err, results) => {
    if (err) { res.status(500).send('DB Error: ' + err.message); return; }
    res.render('index', { students: results });
  });
});

app.get('/add', (req, res) => { res.render('add'); });

app.post('/add', (req, res) => {
  const { name, address, city, state, email, phone } = req.body;
  db.query('INSERT INTO students (name, address, city, state, email, phone) VALUES (?, ?, ?, ?, ?, ?)',
    [name, address, city, state, email, phone], (err) => {
    if (err) { res.status(500).send('Error'); return; }
    res.redirect('/');
  });
});

app.get('/edit/:id', (req, res) => {
  db.query('SELECT * FROM students WHERE id = ?', [req.params.id], (err, results) => {
    if (err || results.length === 0) { res.redirect('/'); return; }
    res.render('edit', { student: results[0] });
  });
});

app.post('/edit/:id', (req, res) => {
  const { name, address, city, state, email, phone } = req.body;
  db.query('UPDATE students SET name=?, address=?, city=?, state=?, email=?, phone=? WHERE id=?',
    [name, address, city, state, email, phone, req.params.id], (err) => {
    if (err) { res.status(500).send('Error'); return; }
    res.redirect('/');
  });
});

app.get('/delete/:id', (req, res) => {
  db.query('DELETE FROM students WHERE id = ?', [req.params.id], (err) => {
    if (err) { res.status(500).send('Error'); return; }
    res.redirect('/');
  });
});

initDB().then(() => {
  app.listen(80, () => { console.log('Server running on port 80'); });
}).catch(err => { console.error('Init failed:', err); process.exit(1); });
