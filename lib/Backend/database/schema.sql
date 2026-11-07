-- ============================================================
-- Restaurant Management System — MySQL Schema
-- ============================================================
CREATE DATABASE IF NOT EXISTS rms_db CHARACTER SET utf8mb4;
USE rms_db;

-- ---------- Roles & Permissions ----------
CREATE TABLE roles (
  role_id INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE permissions (
  permission_id INT AUTO_INCREMENT PRIMARY KEY,
  permission_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE role_permissions (
  role_id INT NOT NULL,
  permission_id INT NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE,
  FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE
);

-- ---------- Employees ----------
CREATE TABLE employees (
  employee_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  username VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  role_id INT NOT NULL,
  status ENUM('active','inactive') DEFAULT 'active',
  failed_login_attempts INT DEFAULT 0,
  locked_until DATETIME NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

-- ---------- Menu ----------
CREATE TABLE menu_categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE menu_items (
  menu_id INT AUTO_INCREMENT PRIMARY KEY,
  category_id INT NOT NULL,
  food_name VARCHAR(150) NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  image VARCHAR(255),
  availability ENUM('available','unavailable') DEFAULT 'available',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES menu_categories(category_id)
);

-- ---------- Inventory ----------
CREATE TABLE inventory (
  inventory_id INT AUTO_INCREMENT PRIMARY KEY,
  ingredient_name VARCHAR(150) NOT NULL,
  quantity DECIMAL(10,2) NOT NULL DEFAULT 0,
  unit VARCHAR(20) NOT NULL,
  minimum_stock DECIMAL(10,2) NOT NULL DEFAULT 0,
  status ENUM('ok','low','out') DEFAULT 'ok',
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE inventory_transactions (
  transaction_id INT AUTO_INCREMENT PRIMARY KEY,
  inventory_id INT NOT NULL,
  transaction_type ENUM('delivery','usage','adjustment') NOT NULL,
  quantity DECIMAL(10,2) NOT NULL,
  transaction_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  employee_id INT NOT NULL,
  FOREIGN KEY (inventory_id) REFERENCES inventory(inventory_id),
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

-- ---------- Tables & Reservations ----------
CREATE TABLE tables (
  table_id INT AUTO_INCREMENT PRIMARY KEY,
  table_number VARCHAR(10) NOT NULL UNIQUE,
  capacity INT NOT NULL,
  status ENUM('available','occupied','reserved') DEFAULT 'available'
);

CREATE TABLE reservations (
  reservation_id INT AUTO_INCREMENT PRIMARY KEY,
  table_id INT NOT NULL,
  customer_name VARCHAR(100) NOT NULL,
  contact_number VARCHAR(30),
  reservation_date DATE NOT NULL,
  reservation_time TIME NOT NULL,
  guest_count INT NOT NULL,
  status ENUM('pending','confirmed','seated','completed','cancelled','no_show') DEFAULT 'pending',
  created_by INT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (table_id) REFERENCES tables(table_id),
  FOREIGN KEY (created_by) REFERENCES employees(employee_id),
  UNIQUE KEY uniq_table_slot (table_id, reservation_date, reservation_time)
);

-- ---------- Orders ----------
CREATE TABLE orders (
  order_id INT AUTO_INCREMENT PRIMARY KEY,
  table_id INT NULL,
  employee_id INT NOT NULL,
  order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  order_status ENUM('pending','confirmed','preparing','ready','completed','cancelled') DEFAULT 'pending',
  subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
  discount DECIMAL(10,2) NOT NULL DEFAULT 0,
  tax DECIMAL(10,2) NOT NULL DEFAULT 0,
  total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
  payment_status ENUM('pending','paid','failed','refunded','cancelled') DEFAULT 'pending',
  FOREIGN KEY (table_id) REFERENCES tables(table_id),
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

CREATE TABLE order_items (
  order_item_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  menu_id INT NOT NULL,
  quantity INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  subtotal DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
  FOREIGN KEY (menu_id) REFERENCES menu_items(menu_id)
);

-- ---------- Payments ----------
CREATE TABLE payments (
  payment_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  payment_method ENUM('cash','card','ewallet','online') NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  payment_status ENUM('pending','paid','failed','refunded','cancelled') DEFAULT 'pending',
  transaction_reference VARCHAR(150),
  payment_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  processed_by INT NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  FOREIGN KEY (processed_by) REFERENCES employees(employee_id)
);

-- ---------- Notifications ----------
CREATE TABLE notifications (
  notification_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NULL,
  role_id INT NULL,
  title VARCHAR(150) NOT NULL,
  message TEXT NOT NULL,
  notification_type VARCHAR(50) NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
  FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

-- ---------- Activity Logs ----------
CREATE TABLE activity_logs (
  log_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL,
  action VARCHAR(150) NOT NULL,
  module VARCHAR(100) NOT NULL,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

-- ---------- Seed data ----------
INSERT INTO roles (role_name) VALUES ('administrator'), ('manager'), ('cashier'), ('kitchen');

INSERT INTO permissions (permission_name) VALUES
('manage_employees'), ('manage_menu'), ('manage_inventory'), ('manage_reservations'),
('manage_orders'), ('process_payments'), ('view_reports'), ('manage_settings'),
('view_kitchen_orders'), ('update_order_status');

-- role_permissions wiring (illustrative — extend as needed)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM roles r, permissions p WHERE r.role_name = 'administrator';

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM roles r, permissions p
WHERE r.role_name = 'manager' AND p.permission_name IN
('manage_menu','manage_inventory','manage_reservations','manage_orders','view_reports');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM roles r, permissions p
WHERE r.role_name = 'cashier' AND p.permission_name IN
('manage_reservations','manage_orders','process_payments');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM roles r, permissions p
WHERE r.role_name = 'kitchen' AND p.permission_name IN
('view_kitchen_orders','update_order_status');

ALTER TABLE employees ADD COLUMN profile_image VARCHAR(255) NULL AFTER email;

CREATE TABLE IF NOT EXISTS attendance (
  attendance_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL,
  clock_in DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  clock_out DATETIME NULL,
  break_started_at DATETIME NULL,
  FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
  INDEX idx_attendance_open (employee_id, clock_out)
);
-- The default administrator account is created by running `npm run seed`
-- (see database/seed.js) so the password is hashed correctly with bcrypt
-- instead of a hardcoded hash sitting in version control.