<?php
session_start();
mysqli_report(MYSQLI_REPORT_OFF);

define('LOCALHOST', 'localhost');
define('DB_USERNAME', 'taskmgr_user');
define('DB_PASSWORD', 'CHANGE_ME_DB_PASSWORD');
define('DB_NAME', 'task_manager');

$proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host  = $_SERVER['HTTP_HOST'];
$dir   = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/\\');
define('SITEURL', "$proto://$host$dir/");

// Require login for all pages except login.php and signup.php
if (!isset($_SESSION['user']) && basename($_SERVER['PHP_SELF']) != 'login.php' && basename($_SERVER['PHP_SELF']) != 'signup.php') {
    header("Location: ".SITEURL."login.php");
    exit;
}

if (isset($_SESSION['user']) && !isset($_SESSION['user_id'])) {
    $conn_init = mysqli_connect(LOCALHOST, DB_USERNAME, DB_PASSWORD);
    if ($conn_init) {
        mysqli_select_db($conn_init, DB_NAME);
        $user_esc = mysqli_real_escape_string($conn_init, $_SESSION['user']);
        $res_init = mysqli_query($conn_init, "SELECT user_id FROM tbl_users WHERE username = '$user_esc'");
        if ($res_init && $row_init = mysqli_fetch_assoc($res_init)) {
            $_SESSION['user_id'] = $row_init['user_id'];
        }
        mysqli_close($conn_init);
    }
}
