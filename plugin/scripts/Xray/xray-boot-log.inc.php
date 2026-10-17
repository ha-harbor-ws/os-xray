<?php
/**
 * Дозапись в Boot / Autoroute Log GUI (/var/log, ротация newsyslog + soft ~50 KB).
 */

if (!defined('XRAY_BOOT_LOG')) {
    define('XRAY_BOOT_LOG', '/var/log/xray-boot.log');
}
if (!defined('XRAY_AUTOROUTE_LOG')) {
    define('XRAY_AUTOROUTE_LOG', '/var/log/xray-autoroute.log');
}
if (!defined('XRAY_BOOT_LOG_MAX')) {
    define('XRAY_BOOT_LOG_MAX', 50000);
}

function xray_log_file_rotate(string $path): void
{
    if (!is_file($path)) {
        return;
    }
    $size = @filesize($path);
    if ($size !== false && $size > XRAY_BOOT_LOG_MAX) {
        @rename($path, $path . '.0');
    }
}

function xray_boot_log_rotate(): void
{
    xray_log_file_rotate(XRAY_BOOT_LOG);
}

function xray_log_file_append(string $path, string $text): void
{
    xray_log_file_rotate($path);
    $text = rtrim($text, "\n") . "\n";
    @file_put_contents($path, $text, FILE_APPEND | LOCK_EX);
}

function xray_boot_log(string $text): void
{
    xray_log_file_append(XRAY_BOOT_LOG, $text);
}

function xray_log_file_block(string $path, string $title, string $body): void
{
    $body = trim($body);
    if ($body === '') {
        return;
    }
    xray_log_file_append(
        $path,
        "\n=== {$title}: " . date('Y-m-d H:i:s') . " ===\n"
        . $body . "\n=== end ===\n"
    );
}

function xray_boot_log_block(string $title, string $body): void
{
    xray_log_file_block(XRAY_BOOT_LOG, $title, $body);
}

function xray_autoroute_log_block(string $title, string $body): void
{
    xray_log_file_block(XRAY_AUTOROUTE_LOG, $title, $body);
}
