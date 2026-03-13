const express = require('express');
const mysql = require('mysql2');
const app = express();

app.set('view engine', 'ejs');
app.use(express.urlencoded({ extended: true }));

const db = mysql.createConnection({
  host: 'localhost',
  user: 'nodeapp',
  password: 'student12',
  database: 'STUDENTS'
});

db.connect((err) => {
  if (err) { console.error('DB error:', err); return; }
  console.log('Connected to MySQL');
});

app.get('/', (req, res) => {
  db.query('SELECT * FROM students', (err, results) => {
    if (err) { res.status(500).send('DB Error'); return; }
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

app.listen(80, () => { console.log('Server running on port 80'); });
