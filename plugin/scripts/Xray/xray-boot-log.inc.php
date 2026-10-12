<?php
/**
 * Дозапись в Boot Log GUI: /tmp/xray_syshook.log (ротация ~50 KB, как syshook).
 */

if (!defined('XRAY_BOOT_LOG')) {
    define('XRAY_BOOT_LOG', '/tmp/xray_syshook.log');
}
if (!defined('XRAY_BOOT_LOG_MAX')) {
    define('XRAY_BOOT_LOG_MAX', 50000);
}

function xray_boot_log_rotate(): void
{
    if (!is_file(XRAY_BOOT_LOG)) {
        return;
    }
    $size = @filesize(XRAY_BOOT_LOG);
    if ($size !== false && $size > XRAY_BOOT_LOG_MAX) {
        @rename(XRAY_BOOT_LOG, XRAY_BOOT_LOG . '.0');
    }
}

function xray_boot_log(string $text): void
{
    xray_boot_log_rotate();
    $text = rtrim($text, "\n") . "\n";
    @file_put_contents(XRAY_BOOT_LOG, $text, FILE_APPEND | LOCK_EX);
}

function xray_boot_log_block(string $title, string $body): void
{
    $body = trim($body);
    if ($body === '') {
        return;
    }
    xray_boot_log(
        "\n=== {$title}: " . date('Y-m-d H:i:s') . " ===\n"
        . $body . "\n=== end ===\n"
    );
}
