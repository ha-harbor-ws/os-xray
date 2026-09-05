<?php
/**
 * Parse bgp.conf templates and generate per-peer BIRD includes.
 */

if (!defined('XRAY_BGP_CONF')) {
    define('XRAY_BGP_CONF', '/usr/local/etc/bird/bgp.conf');
}
if (!defined('XRAY_BIRD_INC_DIR')) {
    define('XRAY_BIRD_INC_DIR', '/usr/local/etc/bird');
}
if (!defined('XRAY_BIRD_PEERS_INC')) {
    define('XRAY_BIRD_PEERS_INC', '/usr/local/etc/bird/bgp.conf');
}
if (!defined('XRAY_BIRD_GENERATED_LIST')) {
    define('XRAY_BIRD_GENERATED_LIST', '/usr/local/etc/bird/.xray-bgp-generated');
}

function xray_bgp_template_names(): array
{
    return ['refilter', 'antifilter_download', 'antifilter_network'];
}

function xray_load_interface_helpers(): void
{
    static $done = false;
    if ($done) {
        return;
    }
    $done = true;
    $inc = '/usr/local/etc/inc/interfaces.inc';
    if (is_readable($inc)) {
        @include_once $inc;
    }
}

function xray_is_ipv4_addr(string $ip): bool
{
    return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false
        && $ip !== '0.0.0.0'
        && strncmp($ip, '127.', 4) !== 0;
}

function xray_is_ipv6_addr(string $ip): bool
{
    $ip = explode('%', $ip)[0];
    if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) === false) {
        return false;
    }
    if ($ip === '::1' || $ip === '::' || strncasecmp($ip, 'fe80:', 5) === 0) {
        return false;
    }
    return true;
}

function xray_ifconfig_wan_addrs(string $if): array
{
    $v4 = '';
    $v6 = '';
    if ($if === '') {
        return ['', ''];
    }
    exec('/sbin/ifconfig ' . escapeshellarg($if) . ' 2>/dev/null', $out);
    foreach ($out as $line) {
        if ($v4 === '' && preg_match('/\binet\s+(\d+\.\d+\.\d+\.\d+)\s/', $line, $m) && xray_is_ipv4_addr($m[1])) {
            $v4 = $m[1];
        }
        if ($v6 === '' && preg_match('/\binet6\s+([0-9a-fA-F:]+)/', $line, $m) && xray_is_ipv6_addr($m[1])) {
            $v6 = $m[1];
        }
    }
    return [$v4, $v6];
}

function xray_wan_ipv4(): string
{
    xray_load_interface_helpers();
    if (function_exists('get_interface_ip')) {
        $ip = trim((string)get_interface_ip('wan'));
        if (xray_is_ipv4_addr($ip)) {
            return $ip;
        }
    }
    $cfg = OPNsense\Core\Config::getInstance()->object();
    $wan = $cfg->interfaces->wan ?? null;
    if (!$wan) {
        return '';
    }
    $ip = trim((string)($wan->ipaddr ?? ''));
    if (xray_is_ipv4_addr($ip)) {
        return $ip;
    }
    [$v4] = xray_ifconfig_wan_addrs(trim((string)($wan->if ?? '')));
    return $v4;
}

function xray_wan_ipv6(): string
{
    xray_load_interface_helpers();
    if (function_exists('get_interface_ipv6')) {
        $ip = explode('%', trim((string)get_interface_ipv6('wan')))[0];
        if (xray_is_ipv6_addr($ip)) {
            return $ip;
        }
    }
    $cfg = OPNsense\Core\Config::getInstance()->object();
    $wan = $cfg->interfaces->wan ?? null;
    if (!$wan) {
        return '';
    }
    $ip = explode('%', trim((string)($wan->ipaddrv6 ?? '')))[0];
    if (xray_is_ipv6_addr($ip)) {
        return $ip;
    }
    [, $v6] = xray_ifconfig_wan_addrs(trim((string)($wan->if ?? '')));
    return $v6;
}

function xray_source_for_peer(array $p): string
{
    $src = trim((string)($p['source_address'] ?? ''));
    $src = explode('%', $src)[0];
    if ($src !== '' && (xray_is_ipv4_addr($src) || xray_is_ipv6_addr($src))) {
        return $src;
    }
    $neighbor = explode('%', trim((string)($p['neighbor'] ?? '')))[0];
    $v6only   = (($p['ipv6'] ?? '0') === '1') && (($p['ipv4'] ?? '0') !== '1');
    if ($v6only || xray_is_ipv6_addr($neighbor)) {
        return xray_wan_ipv6();
    }
    return xray_wan_ipv4();
}

function xray_bird_write_router_id(): void
{
    $dir = XRAY_BIRD_INC_DIR;
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $v4   = xray_wan_ipv4();
    $file = $dir . '/router_id.inc';
    if ($v4 !== '') {
        file_put_contents($file, 'router id ' . $v4 . ";\n");
    } else {
        file_put_contents($file, "# router id: WAN IPv4 not found\n");
    }
    @chmod($file, 0644);
}

function xray_bird_apply_source_placeholders(): void
{
    foreach (xray_bgp_template_names() as $name) {
        $path = XRAY_BIRD_INC_DIR . '/' . $name . '.inc';
        if (!is_readable($path)) {
            continue;
        }
        $text = (string)file_get_contents($path);
        $neighbor = '';
        if (preg_match('/\bneighbor\s+([0-9a-fA-F.:]+)\s+as\s+/i', $text, $m)) {
            $neighbor = $m[1];
        }
        $hasv4 = preg_match('/\bipv4\s*\{/', $text) === 1;
        $hasv6 = preg_match('/\bipv6\s*\{/', $text) === 1;
        $src   = xray_source_for_peer([
            'neighbor'        => $neighbor,
            'source_address'  => '',
            'ipv4'            => $hasv4 ? '1' : '0',
            'ipv6'            => $hasv6 ? '1' : '0',
        ]);
        if ($src === '') {
            continue;
        }
        $repl = '    source address ' . $src . ';';
        $n    = 0;
        $text = preg_replace('/^[ \t]*#?\s*source address\s+[^;\n]*;/m', $repl, $text, 1, $n);
        if ($n === 0) {
            $text = preg_replace(
                '/(\bneighbor\s+[^\n]+)/',
                "$1\n" . $repl,
                $text,
                1
            );
        }
        file_put_contents($path, $text);
    }
}

function xray_bird_apply_wan_addresses(): void
{
    xray_bird_write_router_id();
    xray_bird_apply_source_placeholders();
}

function xray_bgp_read_with_includes(string $path): string
{
    if (!is_readable($path)) {
        return '';
    }
    $out = '';
    foreach (explode("\n", (string)file_get_contents($path)) as $line) {
        if (preg_match('/^\s*include\s+"([^"]+)";/', $line, $m)) {
            $inc = $m[1];
            if (is_readable($inc)) {
                $out .= (string)file_get_contents($inc) . "\n";
            }
            continue;
        }
        $out .= $line . "\n";
    }
    return $out;
}

function xray_bird_extract_block(string $text, int $openBracePos): ?string
{
    $len   = strlen($text);
    $depth = 0;
    for ($i = $openBracePos; $i < $len; $i++) {
        $ch = $text[$i];
        if ($ch === '{') {
            $depth++;
        } elseif ($ch === '}') {
            $depth--;
            if ($depth === 0) {
                return substr($text, $openBracePos + 1, $i - $openBracePos - 1);
            }
        }
    }
    return null;
}

function xray_bird_parse_impexp(string $block, string $family): array
{
    $import = 'none';
    $export = 'none';
    $enabled = false;
    if (!preg_match('/\b' . preg_quote($family, '/') . '\s*\{/i', $block, $m, PREG_OFFSET_CAPTURE)) {
        return ['enabled' => false, 'import' => $import, 'export' => $export];
    }
    $pos  = strpos($block, '{', $m[0][1]);
    $body = $pos === false ? '' : (string)xray_bird_extract_block($block, $pos);
    $enabled = true;
    if (preg_match('/\bimport\s+filter\s+([A-Za-z_][A-Za-z0-9_]*)/i', $body, $mm)) {
        $import = $mm[1];
    } elseif (preg_match('/\bimport\s+(none|all)\b/i', $body, $mm)) {
        $import = strtolower($mm[1]);
    }
    if (preg_match('/\bexport\s+filter\s+([A-Za-z_][A-Za-z0-9_]*)/i', $body, $mm)) {
        $export = $mm[1];
    } elseif (preg_match('/\bexport\s+(none|all)\b/i', $body, $mm)) {
        $export = strtolower($mm[1]);
    }
    return ['enabled' => $enabled, 'import' => $import, 'export' => $export];
}

function xray_parse_bgp_conf_protocols(string $text): array
{
    $text = preg_replace('/^\s*#.*$/m', '', $text);
    $peers = [];
    if (!preg_match_all('/protocol\s+bgp\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{/i', $text, $m, PREG_OFFSET_CAPTURE)) {
        return [];
    }
    foreach ($m[1] as $i => $nameCap) {
        $open = strpos($text, '{', $m[0][$i][1]);
        if ($open === false) {
            continue;
        }
        $body = xray_bird_extract_block($text, $open);
        if ($body === null) {
            continue;
        }
        $v4 = xray_bird_parse_impexp($body, 'ipv4');
        $v6 = xray_bird_parse_impexp($body, 'ipv6');
        $localAs    = preg_match('/\blocal\s+as\s+(\d+)/i', $body, $mm) ? $mm[1] : '65103';
        $neighbor   = '';
        $neighborAs = '65412';
        if (preg_match('/\bneighbor\s+([0-9a-fA-F.:]+)\s+as\s+(\d+)/i', $body, $mm)) {
            $neighbor   = $mm[1];
            $neighborAs = $mm[2];
        }
        $source = '';
        if (preg_match('/\bsource\s+address\s+([0-9a-fA-F.:]+)/i', $body, $mm)) {
            $source = $mm[1];
        }
        $hold = preg_match('/\bhold\s+time\s+(\d+)/i', $body, $mm) ? $mm[1] : '240';
        $peers[] = [
            'enabled'        => '1',
            'name'           => $nameCap[0],
            'local_as'       => $localAs,
            'neighbor'       => $neighbor,
            'neighbor_as'    => $neighborAs,
            'source_address' => $source,
            'ipv4'           => $v4['enabled'] ? '1' : '0',
            'ipv4_import'    => $v4['import'],
            'ipv4_export'    => $v4['export'],
            'ipv6'           => $v6['enabled'] ? '1' : '0',
            'ipv6_import'    => $v6['import'],
            'ipv6_export'    => $v6['export'],
            'multihop'       => preg_match('/\bmultihop\b/i', $body) ? '1' : '0',
            'hold_time'      => $hold,
        ];
    }
    return $peers;
}

function xray_bgp_conf_default_peer(): array
{
    $text = '';
    foreach (xray_bgp_template_names() as $name) {
        $path = XRAY_BIRD_INC_DIR . '/' . $name . '.inc';
        if (is_readable($path)) {
            $text .= (string)file_get_contents($path) . "\n";
        }
    }
    if ($text === '') {
        $text = xray_bgp_read_with_includes(XRAY_BGP_CONF);
    }
    $peers = xray_parse_bgp_conf_protocols($text);
    return $peers[0] ?? [];
}

function xray_bgp_community_ident(string $name): string
{
    $name = basename(trim($name));
    $name = preg_replace('/\.inc$/i', '', $name);
    $name = preg_replace('/[^A-Za-z0-9_]/', '_', $name);
    $name = trim($name, '_');
    if ($name === '' || !preg_match('/^[A-Za-z_]/', $name)) {
        return '';
    }
    return $name;
}

function xray_bgp_parse_communities(string $raw): array
{
    $raw = trim($raw);
    if ($raw === '') {
        return [];
    }
    $raw = preg_replace('/(\d+)\s*,\s*:/', '$1:', $raw);
    $pairs = [];
    if (preg_match_all('/\(\s*(\d+)\s*,\s*(\d+)\s*\)/', $raw, $m, PREG_SET_ORDER)) {
        foreach ($m as $row) {
            $pairs[] = [(int)$row[1], (int)$row[2]];
        }
        return $pairs;
    }
    $tokens = preg_split('/\s*,\s*/', $raw);
    $buf    = [];
    foreach ($tokens as $t) {
        $t = trim((string)$t);
        if ($t === '') {
            continue;
        }
        if (preg_match('/^(\d+)\s*:\s*(\d+)$/', $t, $mm)) {
            $pairs[] = [(int)$mm[1], (int)$mm[2]];
            continue;
        }
        if (preg_match('/^\d+$/', $t)) {
            $buf[] = (int)$t;
            if (count($buf) >= 2) {
                $pairs[] = [$buf[0], $buf[1]];
                $buf     = [];
            }
        }
    }
    return $pairs;
}

function xray_bgp_format_communities_inc(array $pairs): string
{
    $parts = [];
    foreach ($pairs as $pair) {
        $parts[] = '(' . (int)$pair[0] . ', ' . (int)$pair[1] . ')';
    }
    return implode(', ', $parts);
}

function xray_bird_write_community_file(string $dir, string $ident, array $pairs): string
{
    $file = $dir . '/' . $ident . '.inc';
    $body = 'define ' . $ident . ' = [ ' . xray_bgp_format_communities_inc($pairs) . ' ];' . "\n";
    file_put_contents($file, $body);
    @chmod($file, 0644);
    return $file;
}

function xray_bird_impexp_line(string $kind, string $value): string
{
    $value = trim($value);
    if ($value === '' || strcasecmp($value, 'none') === 0) {
        return "        {$kind} none;";
    }
    if (strcasecmp($value, 'all') === 0) {
        return "        {$kind} all;";
    }
    $ident = preg_replace('/[^A-Za-z0-9_]/', '', $value);
    if ($ident === '') {
        return "        {$kind} none;";
    }
    return "        {$kind} filter {$ident};";
}

function xray_bird_protocol_name(string $name, string $uuid, array &$used): string
{
    $n = preg_replace('/[^A-Za-z0-9_]/', '_', $name);
    $n = trim($n, '_');
    if ($n === '' || !preg_match('/^[A-Za-z_]/', $n)) {
        $n = 'peer_' . substr(str_replace('-', '', $uuid), 0, 8);
    }
    $base = $n;
    $i    = 2;
    while (isset($used[$n])) {
        $n = $base . '_' . $i;
        $i++;
    }
    $used[$n] = true;
    return $n;
}

function xray_bird_render_peer(array $p, string $protoName): string
{
    $lines   = [];
    $lines[] = 'protocol bgp ' . $protoName . ' {';
    $lines[] = '    local as ' . (int)$p['local_as'] . ';';
    $lines[] = '    neighbor ' . $p['neighbor'] . ' as ' . (int)$p['neighbor_as'] . ';';
    $src = xray_source_for_peer($p);
    if ($src !== '') {
        $lines[] = '    source address ' . $src . ';';
    }
    if (($p['ipv4'] ?? '0') === '1') {
        $lines[] = '    ipv4 {';
        $lines[] = xray_bird_impexp_line('import', (string)($p['ipv4_import'] ?? 'none'));
        $lines[] = '        export none;';
        $lines[] = '    };';
    }
    if (($p['ipv6'] ?? '0') === '1') {
        $lines[] = '    ipv6 {';
        $lines[] = xray_bird_impexp_line('import', (string)($p['ipv6_import'] ?? 'none'));
        $lines[] = '        export none;';
        $lines[] = '    };';
    }
    $lines[] = '    multihop;';
    $lines[] = '    hold time ' . (int)$p['hold_time'] . ';';
    $lines[] = '}';
    $lines[] = '';
    return implode("\n", $lines);
}

function xray_get_bgp_peers_from_config(): array
{
    $cfg  = OPNsense\Core\Config::getInstance()->object();
    $node = $cfg->OPNsense->xray->bgppeers ?? null;
    if (!$node || !isset($node->peer)) {
        return [];
    }
    $result = [];
    foreach ($node->peer as $peer) {
        $uuid = (string)$peer['uuid'];
        if ($uuid === '') {
            continue;
        }
        $result[$uuid] = [
            'enabled'        => (string)($peer->enabled ?? '1') === '1' ? '1' : '0',
            'name'           => (string)($peer->name ?? ''),
            'local_as'       => (string)($peer->local_as ?? '65103'),
            'neighbor'       => (string)($peer->neighbor ?? ''),
            'neighbor_as'    => (string)($peer->neighbor_as ?? '65412'),
            'source_address' => (string)($peer->source_address ?? ''),
            'ipv4'           => (string)($peer->ipv4 ?? '1') === '1' ? '1' : '0',
            'ipv4_import'          => (string)($peer->ipv4_import ?? 'none'),
            'ipv4_community_name'  => (string)($peer->ipv4_community_name ?? ''),
            'ipv4_community'       => (string)($peer->ipv4_community ?? ''),
            'ipv6'                 => (string)($peer->ipv6 ?? '0') === '1' ? '1' : '0',
            'ipv6_import'          => (string)($peer->ipv6_import ?? 'none'),
            'ipv6_community_name'  => (string)($peer->ipv6_community_name ?? ''),
            'ipv6_community'       => (string)($peer->ipv6_community ?? ''),
            'hold_time'            => (string)($peer->hold_time ?? '240'),
        ];
    }
    return $result;
}

function xray_bird_inc_filename(string $protoName): string
{
    $reserved = [
        'active_tun_v4' => true,
        'active_tun_v6' => true,
        'ANTIFILTER_DOWNLOAD'           => true,
        'ANTIFILTER_NETWORK'            => true,
        'communities'                   => true,
        'router_id'                     => true,
        'accept_refilter'               => true,
        'accept_antifilter_download'    => true,
        'accept_antifilter_network_v4'  => true,
        'accept_antifilter_network_v6'  => true,
        'community_ANTIFILTER_DOWNLOAD' => true,
        'community_ANTIFILTER_NETWORK'  => true,
        'bgp'                           => true,
        'peers'                         => true,
    ];
    if (isset($reserved[$protoName])) {
        $protoName = 'peer_' . $protoName;
    }
    return $protoName . '.inc';
}

function xray_bird_write_peers(): void
{
    $dir = XRAY_BIRD_INC_DIR;
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    xray_bird_write_router_id();

    $peers     = xray_get_bgp_peers_from_config();
    $used      = [];
    $written   = [];
    $incLines  = ['# generated by os-xray — BGP peer includes', ''];
    $templates = array_fill_keys(array_merge(
        xray_bgp_template_names(),
        ['ANTIFILTER_DOWNLOAD', 'ANTIFILTER_NETWORK', 'communities',
         'community_ANTIFILTER_DOWNLOAD', 'community_ANTIFILTER_NETWORK',
         'filters', 'accept_refilter', 'accept_antifilter_download',
         'accept_antifilter_network_v4', 'accept_antifilter_network_v6', 'router_id']
    ), true);
    $commFiles = [];

    foreach ($peers as $uuid => $p) {
        foreach ([
            ['ipv4_community_name', 'ipv4_community'],
            ['ipv6_community_name', 'ipv6_community'],
        ] as $keys) {
            $ident = xray_bgp_community_ident((string)($p[$keys[0]] ?? ''));
            if ($ident === '') {
                continue;
            }
            $pairs = xray_bgp_parse_communities((string)($p[$keys[1]] ?? ''));
            if ($pairs === []) {
                continue;
            }
            $cfile = xray_bird_write_community_file($dir, $ident, $pairs);
            $commFiles[$cfile] = true;
            $written[$cfile]   = true;
        }
    }

    foreach ($peers as $uuid => $p) {
        if ($p['enabled'] !== '1') {
            continue;
        }
        if ($p['neighbor'] === '' || (($p['ipv4'] !== '1') && ($p['ipv6'] !== '1'))) {
            continue;
        }
        $proto = xray_bird_protocol_name($p['name'], $uuid, $used);
        $file  = $dir . '/' . xray_bird_inc_filename($proto);
        file_put_contents($file, xray_bird_render_peer($p, $proto));
        @chmod($file, 0644);
        $written[$file] = true;
        $incLines[] = 'include "' . $file . '";';
    }

    $commLines = ['# generated by os-xray — BGP community defines', ''];
    if (count($commFiles) === 0) {
        foreach (['community_ANTIFILTER_DOWNLOAD', 'community_ANTIFILTER_NETWORK'] as $ident) {
            $commLines[] = 'include "' . $dir . '/' . $ident . '.inc";';
        }
    } else {
        foreach (array_keys($commFiles) as $cfile) {
            $commLines[] = 'include "' . $cfile . '";';
        }
        foreach (['community_ANTIFILTER_DOWNLOAD', 'community_ANTIFILTER_NETWORK',
                  'ANTIFILTER_DOWNLOAD', 'ANTIFILTER_NETWORK'] as $ident) {
            $cfile = $dir . '/' . $ident . '.inc';
            if (!isset($commFiles[$cfile]) && is_file($cfile)) {
                $commLines[] = 'include "' . $cfile . '";';
            }
        }
    }
    $commLines[] = '';
    file_put_contents($dir . '/communities.inc', implode("\n", $commLines));
    @chmod($dir . '/communities.inc', 0644);

    $oldList = [];
    if (is_readable(XRAY_BIRD_GENERATED_LIST)) {
        $oldList = file(XRAY_BIRD_GENERATED_LIST, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    }
    foreach ($oldList as $old) {
        if (isset($written[$old])) {
            continue;
        }
        $base = basename($old, '.inc');
        if (isset($templates[$base])) {
            continue;
        }
        if (is_file($old)) {
            @unlink($old);
        }
    }

    $legacy = glob($dir . '/peer-*.inc');
    if ($legacy !== false) {
        foreach ($legacy as $path) {
            if (!isset($written[$path])) {
                @unlink($path);
            }
        }
    }

    $listBody = implode("\n", array_keys($written));
    if ($listBody !== '') {
        $listBody .= "\n";
    }
    file_put_contents(XRAY_BIRD_GENERATED_LIST, $listBody);
    @chmod(XRAY_BIRD_GENERATED_LIST, 0644);

    $incLines[] = '';
    file_put_contents(XRAY_BIRD_PEERS_INC, implode("\n", $incLines));
    @chmod(XRAY_BIRD_PEERS_INC, 0644);
}

function xray_bird_reload_config(): void
{
    if (!is_executable('/usr/local/sbin/birdc')) {
        return;
    }
    exec('/usr/bin/pgrep -x bird >/dev/null 2>&1', $o, $rc);
    if ($rc !== 0) {
        return;
    }
    exec('/usr/local/sbin/birdc configure 2>&1');
}
