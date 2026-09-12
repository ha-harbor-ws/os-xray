#!/usr/local/bin/php
<?php
/**
 * Read/write os-dnstap-bgp files for the Xray DNStap tab.
 *
 *   xray-dnstap-conf.php get
 *   xray-dnstap-conf.php write
 */

const XRAY_DNSTAP_STAGED = '/tmp/xray_dnstap_write.json';
const XRAY_DNSTAP_MAX = 524288;
const XRAY_DNSTAP_FILES = [
    'conf'    => '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf',
    'domains' => '/usr/local/etc/dnstap-bgp/domains.txt',
    'rc'      => '/usr/local/etc/rc.conf.d/dnstap_bgp',
];

function xray_dnstap_running(): bool
{
    exec('/usr/sbin/service dnstap_bgp onestatus 2>&1', $out, $rc);
    $text = strtolower(implode("\n", $out));
    if (strpos($text, 'not running') !== false) {
        return false;
    }
    return $rc === 0;
}

function xray_dnstap_read_file(string $path): string
{
    if (!is_readable($path)) {
        return '';
    }
    $raw = (string)file_get_contents($path);
    if (strlen($raw) > XRAY_DNSTAP_MAX) {
        return substr($raw, 0, XRAY_DNSTAP_MAX);
    }
    return $raw;
}

function xray_dnstap_write_file(string $path, string $body): bool
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    if (file_put_contents($path, $body) === false) {
        return false;
    }
    @chmod($path, 0644);
    return true;
}

$op = strtolower(trim((string)($argv[1] ?? 'get')));

if ($op === 'write') {
    if (!is_readable(XRAY_DNSTAP_STAGED)) {
        echo "OK\n";
        exit(0);
    }
    $j = json_decode((string)file_get_contents(XRAY_DNSTAP_STAGED), true);
    @unlink(XRAY_DNSTAP_STAGED);
    if (!is_array($j)) {
        echo "ERROR: invalid staged JSON\n";
        exit(1);
    }
    foreach (XRAY_DNSTAP_FILES as $key => $path) {
        if (!array_key_exists($key, $j)) {
            continue;
        }
        $body = str_replace(["\r\n", "\r"], "\n", (string)$j[$key]);
        if (strpos($body, "\0") !== false) {
            echo "ERROR: binary content rejected for {$key}\n";
            exit(1);
        }
        if (strlen($body) > XRAY_DNSTAP_MAX) {
            echo "ERROR: {$key} too large\n";
            exit(1);
        }
        if (!xray_dnstap_write_file($path, $body)) {
            echo "ERROR: cannot write {$path}\n";
            exit(1);
        }
    }
    if (xray_dnstap_running()) {
        exec('/usr/sbin/service dnstap_bgp restart 2>&1');
        echo "OK dnstap_bgp restarted\n";
    } else {
        echo "OK files written, dnstap_bgp not running\n";
    }
    exit(0);
}

$files = [];
foreach (XRAY_DNSTAP_FILES as $key => $path) {
    $files[$key] = [
        'path'   => $path,
        'exists' => is_readable($path),
        'body'   => xray_dnstap_read_file($path),
    ];
}
echo json_encode([
    'result'  => 'ok',
    'running' => xray_dnstap_running(),
    'files'   => $files,
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
