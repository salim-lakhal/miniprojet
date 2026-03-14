#!/bin/bash
# EC2 User Data — Phase 2 POC
# Installs Node.js, MySQL, and deploys the CRUD app on a single instance.

apt-get update -y
apt-get install -y nodejs npm mysql-server

systemctl start mysql
systemctl enable mysql

mysql -u root << 'SQL'
CREATE DATABASE IF NOT EXISTS STUDENTS;
USE STUDENTS;
CREATE TABLE IF NOT EXISTS students (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255),
  address VARCHAR(255),
  city VARCHAR(255),
  state VARCHAR(255),
  email VARCHAR(255),
  phone VARCHAR(20)
);
INSERT INTO students (name, address, city, state, email, phone) VALUES
('John Doe', 'Example Address', 'Example City', 'example State', 'example@example.com', '9009009009');
CREATE USER IF NOT EXISTS 'nodeapp'@'localhost' IDENTIFIED BY 'student12';
GRANT ALL PRIVILEGES ON STUDENTS.* TO 'nodeapp'@'localhost';
FLUSH PRIVILEGES;
SQL

mkdir -p /home/ubuntu/app
cd /home/ubuntu/app

cat > package.json << 'PKGJSON'
{
  "name": "student-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.0",
    "ejs": "^3.1.9"
  }
}
PKGJSON

npm install

cat > app.js << 'APPJS'
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
APPJS

mkdir -p views

cat > views/index.ejs << 'VIEWINDEX'
<!DOCTYPE html>
<html>
<head><title>XYZ University</title>
<style>body{font-family:Arial;margin:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#4CAF50;color:white}a{margin:5px;padding:5px 10px;background:#2196F3;color:white;text-decoration:none;border-radius:3px}h1{color:#333}</style>
</head>
<body>
<h1>XYZ University - Student Records</h1>
<a href="/">Home</a> <a href="/add">Add a new student</a>
<h2>All students</h2>
<table><tr><th>Name</th><th>Address</th><th>City</th><th>State</th><th>Email</th><th>Phone</th><th>Actions</th></tr>
<% students.forEach(s => { %>
<tr><td><%= s.name %></td><td><%= s.address %></td><td><%= s.city %></td><td><%= s.state %></td><td><%= s.email %></td><td><%= s.phone %></td><td><a href="/edit/<%= s.id %>">edit</a> <a href="/delete/<%= s.id %>">delete</a></td></tr>
<% }); %>
</table>
</body></html>
VIEWINDEX

cat > views/add.ejs << 'VIEWADD'
<!DOCTYPE html>
<html><head><title>Add Student</title>
<style>body{font-family:Arial;margin:20px}input{margin:5px;padding:5px;width:300px}button{padding:10px 20px;background:#4CAF50;color:white;border:none;cursor:pointer}</style>
</head><body>
<h1>Add a new student</h1>
<form method="POST" action="/add">
<div>Name: <input name="name" required></div>
<div>Address: <input name="address" required></div>
<div>City: <input name="city" required></div>
<div>State: <input name="state" required></div>
<div>Email: <input name="email" type="email" required></div>
<div>Phone: <input name="phone" required></div>
<button type="submit">Add Student</button>
</form>
<a href="/">Back</a>
</body></html>
VIEWADD

cat > views/edit.ejs << 'VIEWEDIT'
<!DOCTYPE html>
<html><head><title>Edit Student</title>
<style>body{font-family:Arial;margin:20px}input{margin:5px;padding:5px;width:300px}button{padding:10px 20px;background:#FF9800;color:white;border:none;cursor:pointer}</style>
</head><body>
<h1>Edit Student</h1>
<form method="POST" action="/edit/<%= student.id %>">
<div>Name: <input name="name" value="<%= student.name %>" required></div>
<div>Address: <input name="address" value="<%= student.address %>" required></div>
<div>City: <input name="city" value="<%= student.city %>" required></div>
<div>State: <input name="state" value="<%= student.state %>" required></div>
<div>Email: <input name="email" value="<%= student.email %>" type="email" required></div>
<div>Phone: <input name="phone" value="<%= student.phone %>" required></div>
<button type="submit">Update</button>
</form>
<a href="/">Back</a>
</body></html>
VIEWEDIT

cd /home/ubuntu/app
node app.js &
