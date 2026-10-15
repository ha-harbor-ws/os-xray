#!/usr/local/bin/php
<?php
/**
 * Проверка маршрута домена или IP в BIRD: resolv (для имени) → birdcl show route for <ip> all.
 * JSON для вкладки Domains. Для прямого IP колонка Domain пустая.
 */

$xray_config_inc = '/usr/local/etc/inc/config.inc';
if (is_file($xray_config_inc)) {
    require_once $xray_config_inc;
} elseif (is_file('config.inc')) {
    require_once 'config.inc';
}

function xray_domain_route_birdcl(): string
{
    foreach (['/usr/local/birdcl', '/usr/local/sbin/birdcl', '/usr/local/sbin/birdc'] as $bin) {
        if (is_executable($bin)) {
            return $bin;
        }
    }
    return '';
}

function xray_domain_route_sanitize(string $raw): string
{
    $raw = trim($raw);
    $raw = preg_replace('#^https?://#i', '', $raw) ?? $raw;

    // [IPv6] или [IPv6]:port
    if (preg_match('/^\[([0-9a-fA-F:.]+)\](?::\d+)?/', $raw, $m)) {
        return strtolower($m[1]);
    }

    $raw = preg_replace('#/.*$#', '', $raw) ?? $raw;
    $raw = rtrim($raw, '.');

    if (filter_var($raw, FILTER_VALIDATE_IP) !== false) {
        return strtolower($raw);
    }

    // IPv4:port
    if (preg_match('/^(\d{1,3}(?:\.\d{1,3}){3}):\d+$/', $raw, $m)
        && filter_var($m[1], FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false) {
        return $m[1];
    }

    // hostname:port
    $raw = preg_replace('/:\d+$/', '', $raw) ?? $raw;
    return strtolower(trim($raw, " \t\n\r."));
}

function xray_domain_route_is_ip(string $s): bool
{
    return filter_var($s, FILTER_VALIDATE_IP) !== false;
}

function xray_domain_route_is_ip6(string $s): bool
{
    return filter_var($s, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) !== false;
}

function xray_domain_route_general_if(string $key, string $default): string
{
    try {
        if (class_exists('OPNsense\\Core\\Config')) {
            $cfg = OPNsense\Core\Config::getInstance()->object();
            $v   = trim((string)($cfg->OPNsense->xray->general->{$key} ?? ''));
            if ($v !== '') {
                return $v;
            }
        }
    } catch (Throwable $e) {
    }
    return $default;
}

function xray_domain_route_if_label(string $dev, string $ip): string
{
    $v6    = xray_domain_route_is_ip6($ip);
    $wan4  = xray_domain_route_general_if('bgp_if_wan4', '');
    $wan6  = xray_domain_route_general_if('bgp_if_wan6', '');
    $low   = strtolower($dev);
    if ($low === 'lo0' || $low === 'lo' || $low === 'blackhole' || strncmp($low, 'blackhole', 9) === 0) {
        return 'Null';
    }
    if ($dev === $wan6 && $v6) {
        return 'WAN6';
    }
    if ($dev === $wan4 || $dev === $wan6) {
        return $v6 ? 'WAN6' : 'WAN4';
    }
    return $dev;
}

function xray_domain_route_is_host(string $s): bool
{
    if ($s === '' || strlen($s) > 253) {
        return false;
    }
    return (bool)preg_match('/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)*$/i', $s);
}

function xray_domain_route_resolve(string $host): array
{
    if (xray_domain_route_is_ip($host)) {
        return [$host];
    }
    $ips = [];
    foreach ([DNS_A, DNS_AAAA] as $type) {
        $recs = @dns_get_record($host, $type);
        if (!is_array($recs)) {
            continue;
        }
        foreach ($recs as $r) {
            if ($type === DNS_A && !empty($r['ip'])) {
                $ips[] = $r['ip'];
            }
            if ($type === DNS_AAAA && !empty($r['ipv6'])) {
                $ips[] = $r['ipv6'];
            }
        }
    }
    $v4 = @gethostbynamel($host);
    if (is_array($v4)) {
        foreach ($v4 as $ip) {
            $ips[] = $ip;
        }
    }
    $ips = array_values(array_unique($ips));
    return array_slice($ips, 0, 32);
}

function xray_domain_route_tun_map(): array
{
    $map = [];
    if (!class_exists('OPNsense\\Core\\Config')) {
        return $map;
    }
    try {
        $cfg = OPNsense\Core\Config::getInstance()->object();
        $ins = $cfg->OPNsense->xray->instances ?? null;
        if (!$ins) {
            return $map;
        }
        foreach ($ins->instance as $inst) {
            if ((string)($inst->enabled ?? '1') !== '1') {
                continue;
            }
            $tun = trim((string)($inst->tun_interface ?? ''));
            if ($tun === '') {
                continue;
            }
            $name = trim((string)($inst->name ?? ''));
            $map[$tun] = $name !== '' ? $name : $tun;
        }
    } catch (Throwable $e) {
        return $map;
    }
    return $map;
}

function xray_domain_route_query(string $birdcl, string $ip): string
{
    $out = [];
    exec(
        escapeshellarg($birdcl) . ' show route for ' . escapeshellarg($ip) . ' all 2>&1',
        $out
    );
    return implode("\n", $out);
}

function xray_domain_route_not_found(string $text): bool
{
    return (bool)preg_match('/network not (found|in table)/i', $text);
}

function xray_domain_route_line_active(string $line): bool
{
    return (bool)preg_match('/\]\s*\*/', $line);
}

/**
 * Разбор `show route for <ip> all`: протокол в [name …], устройство в dev, * = active.
 */
function xray_domain_route_parse(string $text, string $ip): array
{
    $paths = [];
    $cur = null;
    $flush = static function () use (&$paths, &$cur): void {
        if (is_array($cur)) {
            $paths[] = $cur;
        }
        $cur = null;
    };
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        if (preg_match('/^([0-9a-fA-F:.]+\/\d+)\s+(unicast|blackhole)\s+\[(\S+)/', $line, $m)) {
            $flush();
            $cur = [
                'prefix' => $m[1],
                'peer'   => $m[3],
                'dev'    => ($m[2] === 'blackhole') ? 'blackhole' : '',
                'active' => xray_domain_route_line_active($line),
            ];
            continue;
        }
        if (preg_match('/^\s+(unicast|blackhole)\s+\[(\S+)/', $line, $m)) {
            $flush();
            $cur = [
                'prefix' => $ip,
                'peer'   => $m[2],
                'dev'    => ($m[1] === 'blackhole') ? 'blackhole' : '',
                'active' => xray_domain_route_line_active($line),
            ];
            continue;
        }
        if ($cur !== null && preg_match('/^\s+dev\s+(\S+)/', $line, $m)) {
            $cur['dev'] = $m[1];
        }
    }
    $flush();
    return $paths;
}

$raw = isset($argv[1]) ? (string)$argv[1] : '';
$query = xray_domain_route_sanitize($raw);
$isIp = xray_domain_route_is_ip($query);
$domainLabel = $isIp ? '' : $query;

$fail = static function (string $msg) use ($query, $domainLabel): void {
    echo json_encode([
        'result' => 'failed',
        'domain' => $domainLabel,
        'query'  => $query,
        'message' => $msg,
        'rows' => [],
    ], JSON_UNESCAPED_SLASHES) . "\n";
    exit(0);
};

if ($query === '' || (!$isIp && !xray_domain_route_is_host($query))) {
    $fail('Invalid domain or IP');
}

$ips = xray_domain_route_resolve($query);
if ($ips === []) {
    $fail($isIp ? 'Invalid IP' : 'No A/AAAA records');
}

$birdcl = xray_domain_route_birdcl();
if ($birdcl === '') {
    $fail('birdcl not found');
}

$tunMap = xray_domain_route_tun_map();
$rows = [];
foreach ($ips as $ip) {
    $text = xray_domain_route_query($birdcl, $ip);
    $paths = xray_domain_route_parse($text, $ip);
    if ($paths === [] || xray_domain_route_not_found($text)) {
        $rows[] = [
            'domain'   => $domainLabel,
            'ip'       => $ip,
            'peer'     => 'N/A',
            'instance' => 'N/A',
            'dev'      => xray_domain_route_is_ip6($ip) ? 'WAN6' : 'WAN4',
            'active'   => true,
        ];
        continue;
    }
    foreach ($paths as $p) {
        $dev = trim((string)($p['dev'] ?? ''));
        $iface = $dev !== '' ? xray_domain_route_if_label($dev, $ip) : (xray_domain_route_is_ip6($ip) ? 'WAN6' : 'WAN4');
        $inst = 'N/A';
        if ($dev !== '' && isset($tunMap[$dev])) {
            $inst = $tunMap[$dev];
        }
        $peer = trim((string)($p['peer'] ?? ''));
        $rows[] = [
            'domain'   => $domainLabel,
            'ip'       => $ip,
            'peer'     => $peer !== '' ? $peer : 'N/A',
            'instance' => $inst,
            'dev'      => $iface,
            'active'   => !empty($p['active']),
        ];
    }
}

echo json_encode([
    'result' => 'ok',
    'domain' => $domainLabel,
    'query'  => $query,
    'rows'   => $rows,
], JSON_UNESCAPED_SLASHES) . "\n";
