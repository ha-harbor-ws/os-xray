#!/usr/local/bin/php
<?php
/**
 * Read/write os-dnstap-bgp files as key/value for the Xray DNStap tab.
 *
 *   xray-dnstap-conf.php get
 *   xray-dnstap-conf.php write
 */

require_once __DIR__ . '/xray-dnstap-unbound.php';

const XRAY_DNSTAP_STAGED = '/tmp/xray_dnstap_write.json';
const XRAY_DNSTAP_MAX = 524288;
const XRAY_DNSTAP_DOMAINS_MAX = 33554432;
const XRAY_DNSTAP_CONF_HIDDEN = [
    'domains',
    'blocked_domains',
    'unblocked_domains',
    'cache',
    'dnstap.listen',
    'dnstap.perm',
    'bgp.as',
    'bgp.routerID',
    'bgp.nextHop',
];
const XRAY_DNSTAP_FILES = [
    'conf'            => '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf',
    'blocked'         => '/usr/local/etc/dnstap-bgp/blocked.txt',
    'unblocked'       => '/usr/local/etc/dnstap-bgp/unblocked.txt',
    'blocked_extra'   => '/usr/local/etc/dnstap-bgp/blocked-extra.txt',
    'unblocked_extra' => '/usr/local/etc/dnstap-bgp/unblocked-extra.txt',
    'blocked_urls'    => '/usr/local/etc/dnstap-bgp/blocked-urls.txt',
    'unblocked_urls'  => '/usr/local/etc/dnstap-bgp/unblocked-urls.txt',
    'rc'              => '/usr/local/etc/rc.conf.d/dnstap_bgp',
];
const XRAY_DNSTAP_LEGACY = [
    'domains' => '/usr/local/etc/dnstap-bgp/domains.txt',
    'extra'   => '/usr/local/etc/dnstap-bgp/domains-extra.txt',
    'urls'    => '/usr/local/etc/dnstap-bgp/domain-urls.txt',
];

function xray_dnstap_running(): bool
{
    if (!is_executable('/usr/local/sbin/dnstap-bgp')
        && !is_file('/usr/local/etc/rc.d/dnstap_bgp')
        && !is_file('/etc/rc.d/dnstap_bgp')) {
        return false;
    }
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

function xray_dnstap_rc_is_enabled(string $path): bool
{
    return (bool)preg_match('/^dnstap_bgp_enable\s*=\s*"?YES"?/mi', xray_dnstap_read_file($path));
}

function xray_dnstap_reload(): bool
{
    if (!xray_dnstap_running()) {
        return false;
    }
    exec('/usr/sbin/service dnstap_bgp reload 2>&1', $out, $rc);
    if ($rc === 0) {
        return true;
    }
    return xray_dnstap_sighup();
}

function xray_dnstap_sighup(): bool
{
    $pid = 0;
    foreach (['/var/run/dnstap_bgp.pid', '/var/run/dnstap-bgp.pid'] as $pidfile) {
        if (!is_readable($pidfile)) {
            continue;
        }
        $pid = (int)trim((string)file_get_contents($pidfile));
        if ($pid > 0) {
            break;
        }
    }
    if ($pid <= 0) {
        exec("pgrep -x dnstap-bgp 2>/dev/null", $out, $rc);
        $pid = (int)trim((string)($out[0] ?? '0'));
    }
    if ($pid <= 0) {
        return false;
    }
    exec('kill -HUP ' . $pid . ' 2>&1', $kout, $krc);
    return $krc === 0;
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

function xray_dnstap_parse_toml_scalar(string $v)
{
    $v = trim($v);
    $v = rtrim($v, ',');
    if ($v === 'true') {
        return 'true';
    }
    if ($v === 'false') {
        return 'false';
    }
    if ($v !== '' && ($v[0] === '"' || $v[0] === "'")) {
        $q = $v[0];
        if (preg_match('/^' . preg_quote($q, '/') . '(.*)' . preg_quote($q, '/') . '/', $v, $m)) {
            return $m[1];
        }
    }
    if (preg_match('/^-?\d+$/', $v)) {
        return $v;
    }
    return $v;
}

function xray_dnstap_parse_toml(string $text): array
{
    $out     = [];
    $section = '';
    $arrKey  = null;
    $arr     = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $trim = trim($line);
        if ($trim === '' || $trim[0] === '#') {
            continue;
        }
        if ($arrKey !== null) {
            if (strpos($trim, ']') === 0) {
                $out[] = ['key' => $arrKey, 'value' => implode(', ', $arr)];
                $arrKey = null;
                $arr    = [];
                continue;
            }
            if (preg_match('/^"([^"]*)"/', $trim, $m) || preg_match("/^'([^']*)'/", $trim, $m)) {
                $arr[] = $m[1];
            } elseif (preg_match('/^([^,#\]]+)/', $trim, $m)) {
                $item = trim($m[1], " \t\",");
                if ($item !== '') {
                    $arr[] = $item;
                }
            }
            continue;
        }
        if (preg_match('/^\[([^\]]+)\]/', $trim, $m)) {
            $section = trim($m[1]);
            continue;
        }
        if (preg_match('/^([A-Za-z0-9_]+)\s*=\s*(.*)$/', $trim, $m)) {
            $k = $section !== '' ? $section . '.' . $m[1] : $m[1];
            $v = trim($m[2]);
            if ($v === '[' || preg_match('/^\[\s*$/', $v)) {
                $arrKey = $k;
                $arr    = [];
                continue;
            }
            if (preg_match('/^\[(.*)\]$/', $v, $am)) {
                $items = [];
                if (preg_match_all('/"([^"]*)"/', $am[1], $qm)) {
                    $items = $qm[1];
                }
                $out[] = ['key' => $k, 'value' => implode(', ', $items)];
                continue;
            }
            $out[] = ['key' => $k, 'value' => (string)xray_dnstap_parse_toml_scalar($v)];
        }
    }
    if ($arrKey !== null) {
        $out[] = ['key' => $arrKey, 'value' => implode(', ', $arr)];
    }
    return $out;
}

function xray_dnstap_is_array_key(string $key): bool
{
    $name = $key;
    $dot = strrpos($key, '.');
    if ($dot !== false) {
        $name = substr($key, $dot + 1);
    }
    return $name === 'peers'
        || $name === 'blocked_communities'
        || $name === 'unblocked_communities'
        || substr($name, -12) === '_communities';
}

function xray_dnstap_toml_scalar(string $key, string $v): string
{
    $v = trim($v);
    if ($v === 'true' || $v === 'false') {
        return $v;
    }
    if ($key === 'bgp.as' || $key === 'as' || preg_match('/^-?[1-9]\d*$/', $v) || $v === '0') {
        if (preg_match('/^-?\d+$/', $v) && ($v === '0' || $v[0] !== '0')) {
            return $v;
        }
    }
    return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $v) . '"';
}

function xray_dnstap_conf_is_hidden(string $key): bool
{
    return in_array($key, XRAY_DNSTAP_CONF_HIDDEN, true);
}

function xray_dnstap_conf_managed_rows(): array
{
    $as = function_exists('xray_dnstap_bird_local_as') ? xray_dnstap_bird_local_as() : 65103;
    $sock = defined('XRAY_DNSTAP_SOCK') ? XRAY_DNSTAP_SOCK : '/var/unbound/var/run/dnstap-bgp/dnstap.sock';
    $perm = defined('XRAY_DNSTAP_PERM') ? XRAY_DNSTAP_PERM : '0666';
    return [
        ['key' => 'domains', 'value' => XRAY_DNSTAP_FILES['blocked']],
        ['key' => 'blocked_domains', 'value' => XRAY_DNSTAP_FILES['blocked']],
        ['key' => 'unblocked_domains', 'value' => XRAY_DNSTAP_FILES['unblocked']],
        ['key' => 'cache', 'value' => '/var/db/dnstap-bgp/cache.db'],
        ['key' => 'dnstap.listen', 'value' => $sock],
        ['key' => 'dnstap.perm', 'value' => $perm],
        ['key' => 'bgp.as', 'value' => (string)$as],
    ];
}

function xray_dnstap_default_communities(): array
{
    $as = function_exists('xray_dnstap_bird_local_as') ? xray_dnstap_bird_local_as() : 65103;
    return [
        'bgp.blocked_communities'   => $as . ':666',
        'bgp.unblocked_communities' => $as . ':100',
    ];
}

function xray_dnstap_ensure_community_rows(array $rows): array
{
    $have = [];
    foreach ($rows as $row) {
        $have[trim((string)($row['key'] ?? ''))] = true;
    }
    foreach (xray_dnstap_default_communities() as $k => $v) {
        if (empty($have[$k])) {
            $rows[] = ['key' => $k, 'value' => $v];
        }
    }
    return $rows;
}

function xray_dnstap_conf_merge_managed(array $guiRows): array
{
    $out = [];
    $source = '';
    foreach ($guiRows as $row) {
        $k = trim((string)($row['key'] ?? ''));
        $v = (string)($row['value'] ?? '');
        if ($k === '' || xray_dnstap_conf_is_hidden($k)) {
            continue;
        }
        if ($k === 'ipv6') {
            $on = in_array(strtolower($v), ['1', 'true', 'yes', 'on'], true);
            $v = $on ? 'true' : 'false';
        }
        if ($k === 'bgp.sourceIP') {
            $source = function_exists('xray_dnstap_strip_cidr')
                ? xray_dnstap_strip_cidr($v)
                : trim($v);
        }
        $out[] = ['key' => $k, 'value' => $v];
    }
    if ($source !== '') {
        $out[] = ['key' => 'bgp.routerID', 'value' => $source];
        $out[] = ['key' => 'bgp.nextHop', 'value' => $source];
    }
    $out = xray_dnstap_ensure_community_rows($out);
    foreach (xray_dnstap_conf_managed_rows() as $row) {
        $out[] = $row;
    }
    return $out;
}

function xray_dnstap_conf_for_ui(array $rows): array
{
    $out = [];
    foreach ($rows as $row) {
        $k = trim((string)($row['key'] ?? ''));
        if ($k === '' || xray_dnstap_conf_is_hidden($k)) {
            continue;
        }
        $out[] = $row;
    }
    return xray_dnstap_ensure_community_rows($out);
}

function xray_dnstap_render_toml(array $rows): string
{
    $root = [];
    $secs = [];
    foreach ($rows as $row) {
        $k = trim((string)($row['key'] ?? ''));
        $v = (string)($row['value'] ?? '');
        if ($k === '') {
            continue;
        }
        $dot = strpos($k, '.');
        if ($dot === false) {
            $root[] = [$k, $v];
        } else {
            $sec = substr($k, 0, $dot);
            $name = substr($k, $dot + 1);
            if (!isset($secs[$sec])) {
                $secs[$sec] = [];
            }
            $secs[$sec][] = [$name, $v, $k];
        }
    }
    $lines = [
        '# generated by os-xray DNStap tab',
        '',
    ];
    foreach ($root as [$k, $v]) {
        $lines[] = xray_dnstap_render_toml_assign($k, $v, $k);
    }
    foreach ($secs as $sec => $pairs) {
        $lines[] = '';
        $lines[] = '[' . $sec . ']';
        foreach ($pairs as [$name, $v, $full]) {
            $lines[] = xray_dnstap_render_toml_assign($name, $v, $full);
        }
    }
    return implode("\n", $lines) . "\n";
}

function xray_dnstap_render_toml_assign(string $name, string $v, string $fullKey): string
{
    if (xray_dnstap_is_array_key($fullKey)) {
        $items = [];
        foreach (preg_split('/\s*,\s*/', $v) as $item) {
            $item = trim($item);
            if ($item === '') {
                continue;
            }
            $items[] = '  "' . str_replace(['\\', '"'], ['\\\\', '\\"'], $item) . '",';
        }
        return $name . " = [\n" . implode("\n", $items) . "\n]";
    }
    return $name . ' = ' . xray_dnstap_toml_scalar($fullKey, $v);
}

function xray_dnstap_parse_rc(string $text): array
{
    $out = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $trim = trim($line);
        if ($trim === '' || $trim[0] === '#') {
            continue;
        }
        if (preg_match('/^([A-Za-z0-9_]+)\s*=\s*"(.*)"\s*$/', $trim, $m)) {
            $out[] = ['key' => $m[1], 'value' => $m[2]];
            continue;
        }
        if (preg_match('/^([A-Za-z0-9_]+)\s*=\s*(\S+)\s*$/', $trim, $m)) {
            $out[] = ['key' => $m[1], 'value' => $m[2]];
        }
    }
    return $out;
}

function xray_dnstap_render_rc(array $rows): string
{
    $lines = [
        '# /usr/local/etc/rc.conf.d/dnstap_bgp',
        '# generated by os-xray DNStap tab',
        '',
    ];
    foreach ($rows as $row) {
        $k = trim((string)($row['key'] ?? ''));
        $v = (string)($row['value'] ?? '');
        if ($k === '' || !preg_match('/^[A-Za-z0-9_]+$/', $k)) {
            continue;
        }
        $lines[] = $k . '="' . str_replace(['\\', '"'], ['\\\\', '\\"'], $v) . '"';
    }
    return implode("\n", $lines) . "\n";
}

function xray_dnstap_parse_domains(string $text): array
{
    $out = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $trim = trim($line);
        if ($trim === '' || $trim[0] === '#') {
            continue;
        }
        $out[] = ['key' => 'domain', 'value' => $trim];
    }
    return $out;
}

function xray_dnstap_render_domains(array $rows): string
{
    $lines = [
        '# One lowercase FQDN per line. IDN/punycode is not supported.',
        '',
    ];
    foreach ($rows as $row) {
        $v = strtolower(trim((string)($row['value'] ?? '')));
        if ($v === '' || $v[0] === '#') {
            continue;
        }
        $lines[] = $v;
    }
    return implode("\n", $lines) . "\n";
}

function xray_dnstap_normalize_domain(string $raw): string
{
    $v = strtolower(trim($raw));
    $v = preg_replace('/#.*$/', '', $v);
    $v = trim($v);
    if ($v === '') {
        return '';
    }
    $v = preg_replace('/^https?:\/\//', '', $v);
    $v = preg_replace('/\/.*$/', '', $v);
    $v = rtrim($v, '.');
    if (!preg_match('/^[a-z0-9][a-z0-9._-]*\.[a-z0-9._-]+$/', $v)) {
        return '';
    }
    return $v;
}

function xray_dnstap_parse_domain_text(string $text): array
{
    $out = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $d = xray_dnstap_normalize_domain($line);
        if ($d !== '') {
            $out[$d] = true;
        }
    }
    return $out;
}

function xray_dnstap_parse_urls(string $text): array
{
    $out = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $trim = trim($line);
        if ($trim === '' || $trim[0] === '#') {
            continue;
        }
        $out[] = ['key' => 'url', 'value' => $trim];
    }
    return $out;
}

function xray_dnstap_render_urls(array $rows, string $kind = 'blocked'): string
{
    $lines = [
        '# HTTP(S) URLs of ' . $kind . ' domain lists. One URL per line.',
        '# Generated by os-xray DNStap tab.',
        '',
    ];
    $seen = [];
    foreach ($rows as $row) {
        $v = trim((string)($row['value'] ?? ''));
        if ($v === '' || $v[0] === '#') {
            continue;
        }
        if (!preg_match('#^https?://#i', $v)) {
            continue;
        }
        if (isset($seen[$v])) {
            continue;
        }
        $seen[$v] = true;
        $lines[] = $v;
    }
    return implode("\n", $lines) . "\n";
}

function xray_dnstap_url_list(array $rows): array
{
    $urls = [];
    $seen = [];
    foreach ($rows as $row) {
        $v = trim((string)($row['value'] ?? ''));
        if ($v === '' || !preg_match('#^https?://#i', $v)) {
            continue;
        }
        if (isset($seen[$v])) {
            continue;
        }
        $seen[$v] = true;
        $urls[] = $v;
    }
    return $urls;
}

function xray_dnstap_fetch_url(string $url): string
{
    $tmp = tempnam('/tmp', 'dnstap_dl_');
    if ($tmp === false) {
        return '';
    }
    $cmd = '/usr/bin/fetch -q -o ' . escapeshellarg($tmp) . ' -T 45 ' . escapeshellarg($url);
    exec($cmd . ' 2>&1', $out, $rc);
    if ($rc !== 0 || !is_readable($tmp)) {
        @unlink($tmp);
        $cmd = '/usr/local/bin/curl -fsSL --max-time 45 -o ' . escapeshellarg($tmp) . ' ' . escapeshellarg($url);
        exec($cmd . ' 2>&1', $out2, $rc2);
        if ($rc2 !== 0 || !is_readable($tmp)) {
            @unlink($tmp);
            return '';
        }
    }
    $size = (int)filesize($tmp);
    if ($size <= 0 || $size > XRAY_DNSTAP_DOMAINS_MAX) {
        @unlink($tmp);
        return '';
    }
    $body = (string)file_get_contents($tmp);
    @unlink($tmp);
    return $body;
}

function xray_dnstap_count_domains(string $text): int
{
    $n = 0;
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        if (xray_dnstap_normalize_domain($line) !== '') {
            $n++;
        }
    }
    return $n;
}

function xray_dnstap_read_first(array $paths): string
{
    foreach ($paths as $path) {
        $text = xray_dnstap_read_file($path);
        if (trim($text) !== '') {
            return $text;
        }
    }
    return '';
}

function xray_dnstap_merge_domains(array $extraRows, array $urlRows, string $kind = 'blocked', array $exclude = []): array
{
    $set = [];
    foreach ($extraRows as $row) {
        $d = xray_dnstap_normalize_domain((string)($row['value'] ?? ''));
        if ($d !== '' && !isset($exclude[$d])) {
            $set[$d] = true;
        }
    }
    $fetched = 0;
    $failed  = [];
    foreach (xray_dnstap_url_list($urlRows) as $url) {
        $body = xray_dnstap_fetch_url($url);
        if ($body === '') {
            $failed[] = $url;
            continue;
        }
        $fetched++;
        foreach (xray_dnstap_parse_domain_text($body) as $d => $_) {
            if (!isset($exclude[$d])) {
                $set[$d] = true;
            }
        }
    }
    $list = array_keys($set);
    sort($list, SORT_STRING);
    $lines = [
        '# Summarized ' . $kind . ' domains (unique). Generated by os-xray.',
        '',
    ];
    foreach ($list as $d) {
        $lines[] = $d;
    }
    return [
        'body'    => implode("\n", $lines) . "\n",
        'count'   => count($list),
        'fetched' => $fetched,
        'failed'  => $failed,
    ];
}

function xray_dnstap_has_urls(array $urlRows): bool
{
    return xray_dnstap_url_list($urlRows) !== [];
}

function xray_dnstap_refresh_from_urls(): array
{
    xray_dnstap_ensure_domain_files();
    $blockedExtra = xray_dnstap_parse_domains(xray_dnstap_read_first([
        XRAY_DNSTAP_FILES['blocked_extra'],
        XRAY_DNSTAP_LEGACY['extra'],
    ]));
    $blockedUrls = xray_dnstap_parse_urls(xray_dnstap_read_first([
        XRAY_DNSTAP_FILES['blocked_urls'],
        XRAY_DNSTAP_LEGACY['urls'],
    ]));
    $unblockedExtra = xray_dnstap_parse_domains(xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked_extra']));
    $unblockedUrls = xray_dnstap_parse_urls(xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked_urls']));

    $wrote = false;
    $failed = [];
    $blockedCount = 0;
    $unblockedCount = 0;
    $fetched = 0;
    $hasUrls = xray_dnstap_has_urls($blockedUrls) || xray_dnstap_has_urls($unblockedUrls);

    if (xray_dnstap_has_urls($blockedUrls)) {
        $merged = xray_dnstap_merge_domains($blockedExtra, $blockedUrls, 'blocked');
        if (!xray_dnstap_write_file(XRAY_DNSTAP_FILES['blocked'], $merged['body'])) {
            echo "ERROR: cannot write " . XRAY_DNSTAP_FILES['blocked'] . "\n";
        } else {
            $wrote = true;
            $blockedCount = $merged['count'];
            $fetched += $merged['fetched'];
            $failed = array_merge($failed, $merged['failed']);
        }
        $exclude = xray_dnstap_parse_domain_text($merged['body']);
    } else {
        $exclude = xray_dnstap_parse_domain_text(xray_dnstap_read_file(XRAY_DNSTAP_FILES['blocked']));
    }

    if (xray_dnstap_has_urls($unblockedUrls)) {
        $mergedU = xray_dnstap_merge_domains($unblockedExtra, $unblockedUrls, 'unblocked', $exclude);
        if (!xray_dnstap_write_file(XRAY_DNSTAP_FILES['unblocked'], $mergedU['body'])) {
            echo "ERROR: cannot write " . XRAY_DNSTAP_FILES['unblocked'] . "\n";
        } else {
            $wrote = true;
            $unblockedCount = $mergedU['count'];
            $fetched += $mergedU['fetched'];
            $failed = array_merge($failed, $mergedU['failed']);
        }
    }

    return [
        'wrote'     => $wrote,
        'blocked'   => $blockedCount,
        'unblocked' => $unblockedCount,
        'fetched'   => $fetched,
        'failed'    => $failed,
        'has_urls'  => $hasUrls,
    ];
}

function xray_dnstap_rows_from_post($raw): array
{
    if (is_array($raw)) {
        $rows = [];
        foreach ($raw as $item) {
            if (is_array($item) && isset($item['key'])) {
                $rows[] = ['key' => (string)$item['key'], 'value' => (string)($item['value'] ?? '')];
            }
        }
        return $rows;
    }
    if (is_string($raw) && $raw !== '') {
        $j = json_decode($raw, true);
        if (is_array($j)) {
            return xray_dnstap_rows_from_post($j);
        }
    }
    return [];
}

$op = strtolower(trim((string)($argv[1] ?? 'get')));

if ($op === 'start') {
    xray_dnstap_unbound_activate();
    echo "OK\n";
    exit(0);
}

if ($op === 'stop') {
    xray_dnstap_unbound_deactivate();
    echo "OK\n";
    exit(0);
}

if ($op === 'fetch') {
    $result = xray_dnstap_refresh_from_urls();
    if (!$result['has_urls'] && !$result['wrote']) {
        echo "OK no domain list URLs — skip download\n";
        exit(0);
    }
    echo "OK fetched {$result['fetched']} URL(s), {$result['blocked']} blocked + {$result['unblocked']} unblocked\n";
    if ($result['failed'] !== []) {
        echo "WARN could not download: " . implode(' ', $result['failed']) . "\n";
    }
    if (xray_dnstap_running()) {
        if (xray_dnstap_reload()) {
            echo "OK dnstap_bgp reload\n";
        } else {
            echo "ERROR: dnstap_bgp reload failed\n";
            exit(1);
        }
    } else {
        echo "OK files written, dnstap_bgp not running\n";
    }
    exit(0);
}

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
    $blockedExtra   = xray_dnstap_rows_from_post($j['blocked'] ?? $j['domains'] ?? []);
    $blockedUrls    = xray_dnstap_rows_from_post($j['blocked_urls'] ?? $j['urls'] ?? []);
    $unblockedExtra = xray_dnstap_rows_from_post($j['unblocked'] ?? []);
    $unblockedUrls  = xray_dnstap_rows_from_post($j['unblocked_urls'] ?? []);
    $confRows       = xray_dnstap_conf_merge_managed(xray_dnstap_rows_from_post($j['conf'] ?? []));
    $mergedBlocked  = xray_dnstap_merge_domains($blockedExtra, $blockedUrls, 'blocked');
    $exclude        = xray_dnstap_parse_domain_text($mergedBlocked['body']);
    $mergedUnblocked = xray_dnstap_merge_domains($unblockedExtra, $unblockedUrls, 'unblocked', $exclude);
    $map = [
        'conf'            => xray_dnstap_render_toml($confRows),
        'blocked_extra'   => xray_dnstap_render_domains($blockedExtra),
        'unblocked_extra' => xray_dnstap_render_domains($unblockedExtra),
        'blocked_urls'    => xray_dnstap_render_urls($blockedUrls, 'blocked'),
        'unblocked_urls'  => xray_dnstap_render_urls($unblockedUrls, 'unblocked'),
        'blocked'         => $mergedBlocked['body'],
        'unblocked'       => $mergedUnblocked['body'],
    ];
    foreach ($map as $key => $body) {
        $limit = ($key === 'blocked' || $key === 'unblocked') ? XRAY_DNSTAP_DOMAINS_MAX : XRAY_DNSTAP_MAX;
        if (strlen($body) > $limit) {
            echo "ERROR: {$key} too large\n";
            exit(1);
        }
        if (!xray_dnstap_write_file(XRAY_DNSTAP_FILES[$key], $body)) {
            echo "ERROR: cannot write " . XRAY_DNSTAP_FILES[$key] . "\n";
            exit(1);
        }
    }
    echo "OK merged {$mergedBlocked['count']} blocked + {$mergedUnblocked['count']} unblocked"
        . " from " . ($mergedBlocked['fetched'] + $mergedUnblocked['fetched']) . " URL(s)\n";
    xray_dnstap_sync_rc_from_bgp($confRows);
    $failed = array_merge($mergedBlocked['failed'], $mergedUnblocked['failed']);
    if ($failed !== []) {
        echo "WARN could not download: " . implode(' ', $failed) . "\n";
    }
    if (xray_dnstap_rc_is_enabled(XRAY_DNSTAP_FILES['rc'])) {
        if (xray_dnstap_running()) {
            if (xray_dnstap_sighup()) {
                echo "OK dnstap_bgp running — sent SIGHUP (Unbound not restarted)\n";
            } else {
                echo "ERROR: dnstap_bgp running but SIGHUP failed\n";
                exit(1);
            }
        } else {
            echo "OK files written, dnstap_bgp not running (Unbound not restarted)\n";
        }
    } elseif (xray_dnstap_running()) {
        xray_dnstap_unbound_deactivate();
        echo "OK dnstap_bgp stopped, Unbound DNSTap include removed\n";
    } else {
        echo "OK files written, dnstap_bgp not running\n";
    }
    exit(0);
}

$blockedUrlsText = xray_dnstap_read_first([
    XRAY_DNSTAP_FILES['blocked_urls'],
    XRAY_DNSTAP_LEGACY['urls'],
]);
$blockedExtraText = xray_dnstap_read_first([
    XRAY_DNSTAP_FILES['blocked_extra'],
    XRAY_DNSTAP_LEGACY['extra'],
]);
$hasBlockedUrls = trim($blockedUrlsText) !== '' && preg_match('#https?://#i', $blockedUrlsText);
$blockedSrc = $blockedExtraText;
if ($blockedExtraText === '' && !$hasBlockedUrls) {
    $blockedSrc = xray_dnstap_read_first([
        XRAY_DNSTAP_FILES['blocked'],
        XRAY_DNSTAP_LEGACY['domains'],
    ]);
}
$unblockedUrlsText = xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked_urls']);
$unblockedExtraText = xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked_extra']);
$hasUnblockedUrls = trim($unblockedUrlsText) !== '' && preg_match('#https?://#i', $unblockedUrlsText);
$unblockedSrc = $unblockedExtraText;
if ($unblockedExtraText === '' && !$hasUnblockedUrls) {
    $unblockedSrc = xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked']);
}
$blockedRows   = xray_dnstap_parse_domains($blockedSrc);
$unblockedRows = xray_dnstap_parse_domains($unblockedSrc);
$blockedUrlRows = xray_dnstap_parse_urls($blockedUrlsText);
$unblockedUrlRows = xray_dnstap_parse_urls($unblockedUrlsText);

echo json_encode([
    'result'           => 'ok',
    'running'          => xray_dnstap_running(),
    'paths'            => XRAY_DNSTAP_FILES,
    'conf'             => xray_dnstap_conf_for_ui(xray_dnstap_parse_toml(xray_dnstap_read_file(XRAY_DNSTAP_FILES['conf']))),
    'blocked'          => $blockedRows,
    'unblocked'        => $unblockedRows,
    'blocked_urls'     => $blockedUrlRows,
    'unblocked_urls'   => $unblockedUrlRows,
    'domains'          => $blockedRows,
    'urls'             => $blockedUrlRows,
    'blocked_count'    => xray_dnstap_count_domains(xray_dnstap_read_first([
        XRAY_DNSTAP_FILES['blocked'],
        XRAY_DNSTAP_LEGACY['domains'],
    ])),
    'unblocked_count'  => xray_dnstap_count_domains(xray_dnstap_read_file(XRAY_DNSTAP_FILES['unblocked'])),
    'domains_count'    => xray_dnstap_count_domains(xray_dnstap_read_first([
        XRAY_DNSTAP_FILES['blocked'],
        XRAY_DNSTAP_LEGACY['domains'],
    ])),
    'rc'               => xray_dnstap_parse_rc(xray_dnstap_read_file(XRAY_DNSTAP_FILES['rc'])),
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
