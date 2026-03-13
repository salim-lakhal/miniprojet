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
