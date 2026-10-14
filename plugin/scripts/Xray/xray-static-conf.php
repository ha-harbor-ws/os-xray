#!/usr/local/bin/php
<?php
/**
 * Static IP list URLs → BIRD routes_static_v{4,6}_{PROXY,DIRECT,BLOCK}.inc
 *
 *   xray-static-conf.php get
 *   xray-static-conf.php write
 *   xray-static-conf.php geodatcats
 */

$xray_config_inc = '/usr/local/etc/inc/config.inc';
if (is_file($xray_config_inc)) {
    require_once $xray_config_inc;
} elseif (is_file('config.inc')) {
    require_once 'config.inc';
}
require_once __DIR__ . '/xray-dnstap-geosite.php';
require_once __DIR__ . '/xray-static-geoip.php';

const XRAY_STATIC_STAGED = '/tmp/xray_static_write.json';
const XRAY_STATIC_GEODAT_STAGED = '/tmp/xray_static_geodat.json';
const XRAY_STATIC_MAX_BODY = 67108864;
const XRAY_STATIC_BIRD_DIR = '/usr/local/etc/bird';
const XRAY_STATIC_FILES = [
    'proxy_urls'  => '/usr/local/etc/bird/static-proxy-urls.txt',
    'direct_urls' => '/usr/local/etc/bird/static-direct-urls.txt',
    'block_urls'  => '/usr/local/etc/bird/static-block-urls.txt',
    'geodat_urls' => '/usr/local/etc/bird/static-geodat-urls.txt',
    'v4_proxy'    => '/usr/local/etc/bird/routes_static_v4_PROXY.inc',
    'v4_direct'   => '/usr/local/etc/bird/routes_static_v4_DIRECT.inc',
    'v4_block'    => '/usr/local/etc/bird/routes_static_v4_BLOCK.inc',
    'v6_proxy'    => '/usr/local/etc/bird/routes_static_v6_PROXY.inc',
    'v6_direct'   => '/usr/local/etc/bird/routes_static_v6_DIRECT.inc',
    'v6_block'    => '/usr/local/etc/bird/routes_static_v6_BLOCK.inc',
];

function xray_static_read_file(string $path): string
{
    if (!is_readable($path)) {
        return '';
    }
    return (string)file_get_contents($path);
}

function xray_static_write_file(string $path, string $body): bool
{
    $dir = dirname($path);
    if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
        return false;
    }
    if (file_put_contents($path, $body) === false) {
        return false;
    }
    @chmod($path, 0644);
    return true;
}

function xray_static_rows_from_post($raw): array
{
    if (is_array($raw)) {
        $rows = [];
        foreach ($raw as $item) {
            if (!is_array($item)) {
                continue;
            }
            if (isset($item['key'])) {
                $rows[] = ['key' => (string)$item['key'], 'value' => (string)($item['value'] ?? '')];
                continue;
            }
            if (isset($item['name'])) {
                $rows[] = ['key' => (string)$item['name'], 'value' => (string)($item['action'] ?? $item['value'] ?? '')];
            }
        }
        return $rows;
    }
    if (is_string($raw) && $raw !== '') {
        $j = json_decode($raw, true);
        if (is_array($j)) {
            return xray_static_rows_from_post($j);
        }
    }
    return [];
}

function xray_static_parse_urls(string $text): array
{
    $rows = [];
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $u = trim($line);
        if ($u === '' || $u[0] === '#') {
            continue;
        }
        if (!preg_match('#^https?://#i', $u)) {
            continue;
        }
        $rows[] = ['key' => 'url', 'value' => $u];
    }
    return $rows;
}

function xray_static_render_urls(array $rows): string
{
    $lines = ['# os-xray Static IP list URLs (one URL per line)'];
    $seen = [];
    foreach ($rows as $row) {
        $u = trim((string)($row['value'] ?? ''));
        if ($u === '' || !preg_match('#^https?://#i', $u) || isset($seen[$u])) {
            continue;
        }
        $seen[$u] = true;
        $lines[] = $u;
    }
    return implode("\n", $lines) . "\n";
}

function xray_static_url_list(array $rows): array
{
    $out = [];
    $seen = [];
    foreach ($rows as $row) {
        $u = trim((string)($row['value'] ?? ''));
        if ($u === '' || !preg_match('#^https?://#i', $u) || isset($seen[$u])) {
            continue;
        }
        $seen[$u] = true;
        $out[] = $u;
    }
    return $out;
}

function xray_static_has_urls(array $rows): bool
{
    return xray_static_url_list($rows) !== [];
}

function xray_static_fetch_url(string $url): string
{
    $tmp = tempnam('/tmp', 'xray_static_dl_');
    if ($tmp === false) {
        return '';
    }
    $cmd = '/usr/bin/fetch -q -o ' . escapeshellarg($tmp) . ' -T 90 ' . escapeshellarg($url);
    exec($cmd . ' 2>&1', $out, $rc);
    if ($rc !== 0 || !is_readable($tmp)) {
        @unlink($tmp);
        $cmd = '/usr/local/bin/curl -fsSL --max-time 90 -o ' . escapeshellarg($tmp) . ' ' . escapeshellarg($url);
        exec($cmd . ' 2>&1', $out2, $rc2);
        if ($rc2 !== 0 || !is_readable($tmp)) {
            @unlink($tmp);
            return '';
        }
    }
    $size = (int)filesize($tmp);
    if ($size <= 0 || $size > XRAY_STATIC_MAX_BODY) {
        @unlink($tmp);
        return '';
    }
    $body = (string)file_get_contents($tmp);
    @unlink($tmp);
    return $body;
}

/**
 * Normalize a token to IPv4/IPv6 CIDR or empty.
 * Accepts: 1.2.3.4, 1.2.3.0/24, 2001:db8::1, 2001:db8::/32
 *
 * @return array{cidr:string,v6:bool}|null
 */
function xray_static_parse_prefix(string $raw): ?array
{
    $s = trim($raw);
    $s = preg_replace('/^\uFEFF/', '', $s) ?? $s;
    if ($s === '' || $s[0] === '#' || $s[0] === ';') {
        return null;
    }
    // strip optional trailing comma / bird keywords
    $s = rtrim($s, ",; \t");
    $s = preg_replace('/^(route|net)\s+/i', '', $s) ?? $s;
    $s = preg_replace('/\s+(via|blackhole|unreachable|prohibit).*$/i', '', $s) ?? $s;
    $s = trim($s, " \t\"'");
    if ($s === '') {
        return null;
    }
    if (strpos($s, '/') === false) {
        if (filter_var($s, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            return ['cidr' => $s . '/32', 'v6' => false];
        }
        if (filter_var($s, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
            return ['cidr' => $s . '/128', 'v6' => true];
        }
        return null;
    }
    if (!preg_match('#^([^/]+)/(\d{1,3})$#', $s, $m)) {
        return null;
    }
    $ip = $m[1];
    $p = (int)$m[2];
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
        if ($p < 0 || $p > 32) {
            return null;
        }
        return ['cidr' => $ip . '/' . $p, 'v6' => false];
    }
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
        if ($p < 0 || $p > 128) {
            return null;
        }
        return ['cidr' => $ip . '/' . $p, 'v6' => true];
    }
    return null;
}

/**
 * @return array{v4:array<string,true>,v6:array<string,true>}
 */
function xray_static_parse_prefix_text(string $text): array
{
    $v4 = [];
    $v6 = [];
    foreach (preg_split("/\r\n|\n|\r|,/", $text) as $line) {
        $p = xray_static_parse_prefix($line);
        if ($p === null) {
            continue;
        }
        if ($p['v6']) {
            $v6[$p['cidr']] = true;
        } else {
            $v4[$p['cidr']] = true;
        }
    }
    return ['v4' => $v4, 'v6' => $v6];
}

/**
 * One prefix per line; comma after each except the last. Empty → "#\n"
 */
function xray_static_render_prefix_list(array $cidrs): string
{
    $list = [];
    $seen = [];
    foreach ($cidrs as $c) {
        $c = trim((string)$c);
        if ($c === '' || isset($seen[$c])) {
            continue;
        }
        $seen[$c] = true;
        $list[] = $c;
    }
    if ($list === []) {
        return "#\n";
    }
    sort($list, SORT_STRING);
    $n = count($list);
    $lines = [];
    foreach ($list as $i => $c) {
        $lines[] = ($i === $n - 1) ? $c : ($c . ',');
    }
    return implode("\n", $lines) . "\n";
}

function xray_static_geodat_id(string $url): string
{
    return sha1(strtolower(rtrim(trim($url), '/')));
}

function xray_static_geodat_cat_dir(): string
{
    return XRAY_STATIC_BIRD_DIR . '/static-geodat-categories';
}

function xray_static_geodat_cat_path(string $url): string
{
    return xray_static_geodat_cat_dir() . '/' . xray_static_geodat_id($url) . '.txt';
}

function xray_static_geodat_assign_for_url(string $url): array
{
    return xray_geosite_parse_assignments(xray_static_read_file(xray_static_geodat_cat_path($url)));
}

function xray_static_geodat_has_any_assign(array $urlRows): bool
{
    foreach (xray_static_url_list($urlRows) as $url) {
        if (xray_static_geodat_assign_for_url($url) !== []) {
            return true;
        }
    }
    return false;
}

/**
 * @return array{proxy4:string[],proxy6:string[],direct4:string[],direct6:string[],block4:string[],block6:string[],fetched:int,failed:string[]}
 */
function xray_static_geoip_sets(array $urlRows): array
{
    $proxy4 = [];
    $proxy6 = [];
    $direct4 = [];
    $direct6 = [];
    $block4 = [];
    $block6 = [];
    $fetched = 0;
    $failed = [];
    foreach (xray_static_url_list($urlRows) as $url) {
        $assign = xray_static_geodat_assign_for_url($url);
        if ($assign === []) {
            continue;
        }
        $body = xray_static_fetch_url($url);
        if ($body === '') {
            $failed[] = $url;
            continue;
        }
        $fetched++;
        $cats = xray_geoip_parse_dat($body);
        $col = xray_geoip_collect_prefixes($cats, $assign);
        foreach ($col['proxy4'] as $c) {
            $proxy4[$c] = true;
        }
        foreach ($col['proxy6'] as $c) {
            $proxy6[$c] = true;
        }
        foreach ($col['direct4'] as $c) {
            $direct4[$c] = true;
        }
        foreach ($col['direct6'] as $c) {
            $direct6[$c] = true;
        }
        foreach ($col['block4'] as $c) {
            $block4[$c] = true;
        }
        foreach ($col['block6'] as $c) {
            $block6[$c] = true;
        }
    }
    return [
        'proxy4'  => array_keys($proxy4),
        'proxy6'  => array_keys($proxy6),
        'direct4' => array_keys($direct4),
        'direct6' => array_keys($direct6),
        'block4'  => array_keys($block4),
        'block6'  => array_keys($block6),
        'fetched' => $fetched,
        'failed'  => $failed,
    ];
}

/**
 * @return array{v4:array<string,true>,v6:array<string,true>,fetched:int,failed:string[]}
 */
function xray_static_fetch_prefix_urls(array $urlRows): array
{
    $v4 = [];
    $v6 = [];
    $fetched = 0;
    $failed = [];
    foreach (xray_static_url_list($urlRows) as $url) {
        $body = xray_static_fetch_url($url);
        if ($body === '') {
            $failed[] = $url;
            continue;
        }
        $fetched++;
        $parsed = xray_static_parse_prefix_text($body);
        foreach ($parsed['v4'] as $c => $_) {
            $v4[$c] = true;
        }
        foreach ($parsed['v6'] as $c => $_) {
            $v6[$c] = true;
        }
    }
    return ['v4' => $v4, 'v6' => $v6, 'fetched' => $fetched, 'failed' => $failed];
}

function xray_static_bird_reload(): void
{
    exec('/usr/sbin/service bird onestatus 2>&1', $stOut, $stRc);
    $stText = strtolower(implode("\n", $stOut));
    if ($stRc !== 0 || strpos($stText, 'not running') !== false) {
        echo "static: bird not running — skip configure\n";
        return;
    }
    foreach (['/usr/local/sbin/birdc', '/usr/local/bin/birdc'] as $bin) {
        if (is_executable($bin)) {
            exec(escapeshellarg($bin) . ' configure 2>&1', $out, $rc);
            echo $rc === 0
                ? "static: birdc configure OK\n"
                : ("static: birdc configure failed: " . trim(implode(' ', $out)) . "\n");
            return;
        }
    }
    echo "static: birdc not found\n";
}

/**
 * @return array{wrote:bool,proxy4:int,proxy6:int,direct4:int,direct6:int,block4:int,block6:int,fetched:int,failed:string[]}
 */
function xray_static_refresh(
    array $proxyUrls,
    array $directUrls,
    array $blockUrls,
    array $geodatUrls
): array {
    $failed = [];
    $fetched = 0;

    $proxy = xray_static_fetch_prefix_urls($proxyUrls);
    $direct = xray_static_fetch_prefix_urls($directUrls);
    $block = xray_static_fetch_prefix_urls($blockUrls);
    $fetched += $proxy['fetched'] + $direct['fetched'] + $block['fetched'];
    $failed = array_merge($failed, $proxy['failed'], $direct['failed'], $block['failed']);

    $p4 = $proxy['v4'];
    $p6 = $proxy['v6'];
    $d4 = $direct['v4'];
    $d6 = $direct['v6'];
    $b4 = $block['v4'];
    $b6 = $block['v6'];

    if (xray_static_has_urls($geodatUrls) && xray_static_geodat_has_any_assign($geodatUrls)) {
        $geo = xray_static_geoip_sets($geodatUrls);
        $fetched += $geo['fetched'];
        $failed = array_merge($failed, $geo['failed']);
        foreach ($geo['proxy4'] as $c) {
            $p4[$c] = true;
        }
        foreach ($geo['proxy6'] as $c) {
            $p6[$c] = true;
        }
        foreach ($geo['direct4'] as $c) {
            $d4[$c] = true;
        }
        foreach ($geo['direct6'] as $c) {
            $d6[$c] = true;
        }
        foreach ($geo['block4'] as $c) {
            $b4[$c] = true;
        }
        foreach ($geo['block6'] as $c) {
            $b6[$c] = true;
        }
    }

    // Priority: BLOCK > PROXY > DIRECT (drop overlaps)
    foreach ($b4 as $c => $_) {
        unset($p4[$c], $d4[$c]);
    }
    foreach ($b6 as $c => $_) {
        unset($p6[$c], $d6[$c]);
    }
    foreach ($p4 as $c => $_) {
        unset($d4[$c]);
    }
    foreach ($p6 as $c => $_) {
        unset($d6[$c]);
    }

    xray_static_write_file(XRAY_STATIC_FILES['v4_proxy'], xray_static_render_prefix_list(array_keys($p4)));
    xray_static_write_file(XRAY_STATIC_FILES['v6_proxy'], xray_static_render_prefix_list(array_keys($p6)));
    xray_static_write_file(XRAY_STATIC_FILES['v4_direct'], xray_static_render_prefix_list(array_keys($d4)));
    xray_static_write_file(XRAY_STATIC_FILES['v6_direct'], xray_static_render_prefix_list(array_keys($d6)));
    xray_static_write_file(XRAY_STATIC_FILES['v4_block'], xray_static_render_prefix_list(array_keys($b4)));
    xray_static_write_file(XRAY_STATIC_FILES['v6_block'], xray_static_render_prefix_list(array_keys($b6)));

    return [
        'wrote'    => true,
        'proxy4'   => count($p4),
        'proxy6'   => count($p6),
        'direct4'  => count($d4),
        'direct6'  => count($d6),
        'block4'   => count($b4),
        'block6'   => count($b6),
        'fetched'  => $fetched,
        'failed'   => $failed,
    ];
}

function xray_static_count_prefixes(string $text): int
{
    if (trim($text) === '' || trim($text) === '#') {
        return 0;
    }
    $n = 0;
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        if (xray_static_parse_prefix($line) !== null) {
            $n++;
        }
    }
    return $n;
}

$op = strtolower(trim((string)($argv[1] ?? 'get')));

if ($op === 'geodatcats') {
    $raw = is_readable(XRAY_STATIC_GEODAT_STAGED)
        ? (string)file_get_contents(XRAY_STATIC_GEODAT_STAGED)
        : '';
    @unlink(XRAY_STATIC_GEODAT_STAGED);
    $j = json_decode($raw, true);
    if (!is_array($j)) {
        echo json_encode(['result' => 'failed', 'message' => 'No staged geodat request'], JSON_UNESCAPED_SLASHES) . "\n";
        exit(1);
    }
    $urlRows = xray_static_rows_from_post($j['geodat_urls'] ?? []);
    if ($urlRows === []) {
        $urlRows = xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['geodat_urls']));
    }
    $target = trim((string)($j['geodat_url'] ?? ''));
    if ($target === '' && isset($urlRows[0]['value'])) {
        $target = trim((string)$urlRows[0]['value']);
    }
    $save = array_key_exists('geodat_categories', $j) || array_key_exists('categories', $j);
    $assign = $save
        ? xray_geosite_assignments_from_rows(xray_static_rows_from_post($j['geodat_categories'] ?? $j['categories'] ?? []))
        : ($target !== '' ? xray_static_geodat_assign_for_url($target) : []);

    xray_static_write_file(XRAY_STATIC_FILES['geodat_urls'], xray_static_render_urls($urlRows));
    if ($save && $target !== '') {
        if (!is_dir(xray_static_geodat_cat_dir())) {
            @mkdir(xray_static_geodat_cat_dir(), 0755, true);
        }
        xray_static_write_file(xray_static_geodat_cat_path($target), xray_geosite_render_assignments($assign, $target));
    }

    $categories = [];
    $message = '';
    if ($target === '') {
        $message = 'No geodat URL selected';
    } else {
        $body = xray_static_fetch_url($target);
        if ($body === '') {
            $message = 'Failed to download geodat URL';
        } else {
            $cats = xray_geoip_parse_dat($body);
            if ($cats === []) {
                $message = 'No geoip categories found (expect geoip.dat)';
            }
            foreach ($cats as $name => $info) {
                $categories[] = [
                    'name'   => $name,
                    'count'  => (int)($info['count'] ?? (count($info['v4']) + count($info['v6']))),
                    'action' => $assign[$name] ?? '',
                ];
            }
        }
    }

    echo json_encode([
        'result'     => 'ok',
        'message'    => $message,
        'geodat_url' => $target,
        'categories' => $categories,
        'saved'      => $save,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
    exit(0);
}

if ($op === 'write') {
    if (!is_readable(XRAY_STATIC_STAGED)) {
        echo "OK\n";
        exit(0);
    }
    $raw = (string)file_get_contents(XRAY_STATIC_STAGED);
    @unlink(XRAY_STATIC_STAGED);
    $j = json_decode($raw, true);
    if (!is_array($j)) {
        echo "ERROR: invalid staged static JSON\n";
        exit(1);
    }
    $proxyUrls  = array_key_exists('proxy_urls', $j)
        ? xray_static_rows_from_post($j['proxy_urls'])
        : xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['proxy_urls']));
    $directUrls = array_key_exists('direct_urls', $j)
        ? xray_static_rows_from_post($j['direct_urls'])
        : xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['direct_urls']));
    $blockUrls  = array_key_exists('block_urls', $j)
        ? xray_static_rows_from_post($j['block_urls'])
        : xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['block_urls']));
    $geodatUrls = array_key_exists('geodat_urls', $j)
        ? xray_static_rows_from_post($j['geodat_urls'])
        : xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['geodat_urls']));

    xray_static_write_file(XRAY_STATIC_FILES['proxy_urls'], xray_static_render_urls($proxyUrls));
    xray_static_write_file(XRAY_STATIC_FILES['direct_urls'], xray_static_render_urls($directUrls));
    xray_static_write_file(XRAY_STATIC_FILES['block_urls'], xray_static_render_urls($blockUrls));
    xray_static_write_file(XRAY_STATIC_FILES['geodat_urls'], xray_static_render_urls($geodatUrls));

    $sum = xray_static_refresh($proxyUrls, $directUrls, $blockUrls, $geodatUrls);
    xray_static_bird_reload();

    echo 'OK: static prefixes'
        . ' proxy4=' . $sum['proxy4'] . ' proxy6=' . $sum['proxy6']
        . ' direct4=' . $sum['direct4'] . ' direct6=' . $sum['direct6']
        . ' block4=' . $sum['block4'] . ' block6=' . $sum['block6']
        . ' fetched=' . $sum['fetched']
        . ($sum['failed'] !== [] ? (' failed=' . count($sum['failed'])) : '')
        . "\n";
    foreach ($sum['failed'] as $u) {
        echo "WARN: download failed: {$u}\n";
    }
    exit(0);
}

// get
$proxyUrls  = xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['proxy_urls']));
$directUrls = xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['direct_urls']));
$blockUrls  = xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['block_urls']));
$geodatUrls = xray_static_parse_urls(xray_static_read_file(XRAY_STATIC_FILES['geodat_urls']));

echo json_encode([
    'result'      => 'ok',
    'proxy_urls'  => $proxyUrls,
    'direct_urls' => $directUrls,
    'block_urls'  => $blockUrls,
    'geodat_urls' => $geodatUrls,
    'counts'      => [
        'proxy4'  => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v4_proxy'])),
        'proxy6'  => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v6_proxy'])),
        'direct4' => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v4_direct'])),
        'direct6' => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v6_direct'])),
        'block4'  => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v4_block'])),
        'block6'  => xray_static_count_prefixes(xray_static_read_file(XRAY_STATIC_FILES['v6_block'])),
    ],
], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";
