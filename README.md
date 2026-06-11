# DBS401 SQL Injection Playground

Intentionally-vulnerable Task Manager for the FPT University DBS401 project.
Contains **3 SQL injection challenges** at Easy, Medium, and Hard difficulty.

## Quick Start (Fresh Linux VM)

```bash
git clone https://github.com/quan12-4/DBS401.git
cd DBS401
sudo setup.sh
```

or

```bash
sudo apt install curl -y
curl -fsSL https://raw.githubusercontent.com/quan12-4/DBS401/main/setup.sh | sudo bash
```

The script installs Apache, MariaDB, PHP, clones this repo, imports the
database, and prints the target's ip address to access the web page.

## Manual Installation

1. Place the files in your web root (e.g. `/var/www/html/task-manager`).
2. Import `task_manager.sql` into MySQL/MariaDB.
3. Update `config/constants.php` with your database credentials.
4. Browse to `http://localhost/task-manager/`.

## Flag Overview

There are 3 flags in the project with flag format `Nhom4-FLAGX{your-answer}`.

## Technologies

- PHP 8.x (procedural)
- MySQL / MariaDB
- Apache 2
