<?php
/**
 * Wire Unbound DNSTap include to dnstap-bgp socket on start; undo on stop.
 */

const XRAY_DNSTAP_UNBOUND_SAMPLE = '/usr/local/etc/unbound.opnsense.d/dnstap.conf.sample';
const XRAY_DNSTAP_UNBOUND_CONF   = '/usr/local/etc/unbound.opnsense.d/dnstap.conf';
const XRAY_DNSTAP_SOCK_DIR       = '/var/unbound/var/run/dnstap-bgp';
/** Host path for dnstap-bgp. Unbound chroots to /var/unbound and uses SOCK_CHROOT. */
const XRAY_DNSTAP_SOCK           = '/var/unbound/var/run/dnstap-bgp/dnstap.sock';
const XRAY_DNSTAP_SOCK_CHROOT    = '/var/run/dnstap-bgp/dnstap.sock';
const XRAY_DNSTAP_BGP_CONF       = '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf';
const XRAY_DNSTAP_BGP_SAMPLE     = '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf.sample';
const XRAY_DNSTAP_PERM           = '0666';
const XRAY_DNSTAP_RC             = '/usr/local/etc/rc.conf.d/dnstap_bgp';

/**
 * Rewrite an rc.conf-style assignment in place. Do not use sysrc: a
 * corrupted line like name=""YES""NO"" is invisible to sysrc -x, so the
 * next set appends another token. Strip every name=... line then append
 * a single name="VALUE".
 */
function xray_rc_conf_delete_var(string $path, string $name): void
{
    if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name) || !is_readable($path)) {
        return;
    }
    $text = (string)file_get_contents($path);
    $new = preg_replace('/^[ \t]*' . preg_quote($name, '/') . '[ \t]*=[^\n]*\r?\n?/m', '', $text);
    if ($new === null || $new === $text) {
        return;
    }
    if (file_put_contents($path, $new) === false) {
        echo "dnstap: cannot rewrite {$path}\n";
    }
}

function xray_sysrc_set(string $name, string $value, ?string $file = null): void
{
    if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $name)) {
        return;
    }
    $path = ($file !== null && $file !== '') ? $file : '/etc/rc.conf';
    $dir = dirname($path);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    xray_rc_conf_delete_var($path, $name);
    $line = $name . '="' . str_replace(['\\', '"'], ['\\\\', '\\"'], $value) . "\"\n";
    $body = is_readable($path) ? (string)file_get_contents($path) : '';
    $body = rtrim($body);
    $body = ($body === '') ? $line : ($body . "\n" . $line);
    if (file_put_contents($path, $body) === false) {
        echo "dnstap: cannot write {$path}\n";
        return;
    }
    @chmod($path, 0644);
}

function xray_dnstap_strip_cidr(string $s): string
{
    $s = trim($s, " \t\"'");
    if (preg_match('/^([^\/]+)\//', $s, $m)) {
        return $m[1];
    }
    return $s;
}

function xray_dnstap_bird_local_as(): int
{
    $as = 65103;
    try {
        $cfg = \OPNsense\Core\Config::getInstance();
        if (method_exists($cfg, 'forceReload')) {
            $cfg->forceReload();
        }
        $peers = $cfg->object()->OPNsense->xray->bgppeers->peer ?? null;
        if ($peers) {
            foreach ($peers as $peer) {
                if (strcasecmp(trim((string)($peer->name ?? '')), 'dnstap') === 0) {
                    continue;
                }
                $las = (int)($peer->local_as ?? 0);
                if ($las > 0) {
                    return $las;
                }
            }
        }
    } catch (\Throwable $e) {
    }
    return $as;
}

function xray_dnstap_ip_with_prefix(string $ip, int $prefix = 30): string
{
    $ip = trim($ip);
    if ($ip === '') {
        return '';
    }
    if (strpos($ip, '/') !== false) {
        return $ip;
    }
    return $ip . '/' . $prefix;
}

function xray_dnstap_first_peer_ip(string $raw): string
{
    if (preg_match('/peers\s*=\s*\[(.*?)\]/s', $raw, $m)) {
        if (preg_match('/"([^"]+)"/', $m[1], $q)) {
            return xray_dnstap_strip_cidr($q[1]);
        }
        if (preg_match('/([0-9]{1,3}(?:\.[0-9]{1,3}){3})/', $m[1], $q)) {
            return $q[1];
        }
    }
    return '';
}

function xray_dnstap_sync_rc_from_bgp(?array $rows = null): void
{
    $jail = '';
    $host = '';
    if (is_array($rows)) {
        foreach ($rows as $row) {
            $k = (string)($row['key'] ?? '');
            $v = (string)($row['value'] ?? '');
            if ($k === 'bgp.sourceIP' || $k === 'bgp.sourceip') {
                $jail = xray_dnstap_strip_cidr($v);
            }
            if ($k === 'bgp.peers') {
                $parts = preg_split('/\s*,\s*/', $v);
                $host = xray_dnstap_strip_cidr((string)($parts[0] ?? ''));
            }
        }
    } elseif (is_readable(XRAY_DNSTAP_BGP_CONF)) {
        $raw = (string)file_get_contents(XRAY_DNSTAP_BGP_CONF);
        $bgp = xray_dnstap_toml_section_kv($raw, 'bgp');
        foreach (['sourceIP', 'sourceip'] as $k) {
            if (!empty($bgp[$k])) {
                $jail = xray_dnstap_strip_cidr((string)$bgp[$k]);
                break;
            }
        }
        $host = xray_dnstap_first_peer_ip($raw);
    }
    $jailCidr = xray_dnstap_ip_with_prefix($jail);
    $hostCidr = xray_dnstap_ip_with_prefix($host);
    if ($jailCidr === '' && $hostCidr === '') {
        return;
    }
    $dir = dirname(XRAY_DNSTAP_RC);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    if ($hostCidr !== '') {
        xray_sysrc_set('dnstap_bgp_host_ip', $hostCidr, XRAY_DNSTAP_RC);
        echo "dnstap: rc dnstap_bgp_host_ip={$hostCidr} (from bgp.peers)\n";
    }
    if ($jailCidr !== '') {
        xray_sysrc_set('dnstap_bgp_jail_ip', $jailCidr, XRAY_DNSTAP_RC);
        echo "dnstap: rc dnstap_bgp_jail_ip={$jailCidr} (from bgp.sourceIP)\n";
    }
}

function xray_dnstap_bird_neighbor_params(): array
{
    $host = '192.168.113.1';
    $jail = '192.168.113.2';
    $ipv6 = false;
    $localAs = xray_dnstap_bird_local_as();
    if (is_readable(XRAY_DNSTAP_BGP_CONF)) {
        $raw = (string)file_get_contents(XRAY_DNSTAP_BGP_CONF);
        $bgp = xray_dnstap_toml_section_kv($raw, 'bgp');
        foreach (['sourceIP', 'sourceip', 'nextHop', 'nexthop'] as $k) {
            if (!empty($bgp[$k])) {
                $jail = xray_dnstap_strip_cidr((string)$bgp[$k]);
                break;
            }
        }
        $peer = xray_dnstap_first_peer_ip($raw);
        if ($peer !== '') {
            $host = $peer;
        }
        if (preg_match('/^ipv6\s*=\s*(true|false)/mi', $raw, $m)) {
            $ipv6 = strtolower($m[1]) === 'true';
        }
    }
    return [
        'host'        => $host,
        'jail'        => $jail,
        'neighbor_as' => $localAs,
        'local_as'    => $localAs,
        'ipv6'        => $ipv6,
    ];
}

function xray_dnstap_sync_bird(bool $enable): void
{
    $script = __DIR__ . '/xray-bird-peers.php';
    if (is_readable($script)) {
        require_once $script;
    }
    if (!function_exists('xray_dnstap_sync_bird_peer')) {
        echo "dnstap: BIRD peer sync skipped — xray-bird-peers.php unavailable\n";
        return;
    }
    xray_dnstap_sync_bird_peer($enable, xray_dnstap_bird_neighbor_params());
}

function xray_dnstap_toml_format_value(string $key, string $v): string
{
    $v = trim($v);
    $name = $key;
    $dot = strrpos($key, '.');
    if ($dot !== false) {
        $name = substr($key, $dot + 1);
    }
    if ($v === 'true' || $v === 'false') {
        return $v;
    }
    if ($name === 'as' && preg_match('/^-?\d+$/', $v)) {
        return (string)((int)$v);
    }
    return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $v) . '"';
}

function xray_dnstap_toml_kv_line(string $name, string $v): string
{
    return $name . ' = ' . xray_dnstap_toml_format_value($name, $v);
}

function xray_dnstap_toml_upsert_section(string $text, string $section, array $kv): string
{
    $lines = preg_split("/\r\n|\n|\r/", $text);
    if ($lines === false) {
        $lines = [];
    }
    $out = [];
    $in = false;
    $seen = [];
    $closed = false;
    $hadSection = false;

    $flushMissing = static function () use (&$out, &$seen, $kv): void {
        foreach ($kv as $k => $v) {
            if (empty($seen[$k])) {
                $out[] = xray_dnstap_toml_kv_line($k, (string)$v);
            }
        }
    };

    foreach ($lines as $line) {
        $trim = trim($line);
        if (preg_match('/^\[(.+)\]$/', $trim, $m)) {
            if ($in) {
                $flushMissing();
                $in = false;
                $closed = true;
            }
            $in = ($m[1] === $section);
            if ($in) {
                $hadSection = true;
                $seen = [];
            }
            $out[] = $line;
            continue;
        }
        if ($in && preg_match('/^([A-Za-z0-9_]+)\s*=/', $trim, $km) && isset($kv[$km[1]])) {
            $k = $km[1];
            $out[] = xray_dnstap_toml_kv_line($k, (string)$kv[$k]);
            $seen[$k] = true;
            continue;
        }
        $out[] = $line;
    }
    if ($in) {
        $flushMissing();
        $closed = true;
    }
    if (!$hadSection) {
        if ($out !== [] && trim((string)end($out)) !== '') {
            $out[] = '';
        }
        $out[] = '[' . $section . ']';
        foreach ($kv as $k => $v) {
            $out[] = xray_dnstap_toml_kv_line($k, (string)$v);
        }
    }
    unset($closed);
    return implode("\n", $out) . "\n";
}

function xray_dnstap_toml_section_kv(string $text, string $section): array
{
    $kv = [];
    $in = false;
    foreach (preg_split("/\r\n|\n|\r/", $text) as $line) {
        $trim = trim($line);
        if ($trim === '' || ($trim[0] ?? '') === '#') {
            continue;
        }
        if (preg_match('/^\[(.+)\]$/', $trim, $m)) {
            $in = ($m[1] === $section);
            continue;
        }
        if (!$in) {
            continue;
        }
        if (preg_match('/^([A-Za-z0-9_]+)\s*=\s*(.*)$/', $trim, $km)) {
            $v = trim($km[2]);
            if ($v !== '' && $v[0] === '"' && substr($v, -1) === '"') {
                $v = stripcslashes(substr($v, 1, -1));
            }
            $kv[$km[1]] = $v;
        }
    }
    return $kv;
}

function xray_dnstap_toml_upsert_root(string $text, array $kv): string
{
    $lines = preg_split("/\r\n|\n|\r/", $text);
    if ($lines === false) {
        $lines = [];
    }
    $out = [];
    $seen = [];
    $inSection = false;
    foreach ($lines as $line) {
        $trim = trim($line);
        if (preg_match('/^\[.+\]$/', $trim)) {
            $inSection = true;
            $out[] = $line;
            continue;
        }
        if (!$inSection && preg_match('/^([A-Za-z0-9_]+)\s*=/', $trim, $m) && isset($kv[$m[1]])) {
            $k = $m[1];
            $out[] = xray_dnstap_toml_kv_line($k, (string)$kv[$k]);
            $seen[$k] = true;
            continue;
        }
        $out[] = $line;
    }
    $missing = [];
    foreach ($kv as $k => $v) {
        if (empty($seen[$k])) {
            $missing[] = xray_dnstap_toml_kv_line($k, (string)$v);
        }
    }
    if ($missing === []) {
        return implode("\n", $out) . "\n";
    }
    $final = [];
    $inserted = false;
    foreach ($out as $line) {
        if (!$inserted && preg_match('/^\[.+\]$/', trim($line))) {
            foreach ($missing as $ins) {
                $final[] = $ins;
            }
            $final[] = '';
            $inserted = true;
        }
        $final[] = $line;
    }
    if (!$inserted) {
        if ($final !== [] && trim((string)end($final)) !== '') {
            $final[] = '';
        }
        foreach ($missing as $ins) {
            $final[] = $ins;
        }
    }
    return implode("\n", $final) . "\n";
}

function xray_dnstap_write_bgp_listen(): void
{
    $conf = XRAY_DNSTAP_BGP_CONF;
    $dir = dirname($conf);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $text = is_readable($conf) ? (string)file_get_contents($conf) : '';
    $kv = ['listen' => XRAY_DNSTAP_SOCK, 'perm' => XRAY_DNSTAP_PERM];
    $new = xray_dnstap_toml_upsert_section($text, 'dnstap', $kv);
    if (file_put_contents($conf, $new) === false) {
        echo "dnstap: cannot write {$conf}\n";
        return;
    }
    echo "dnstap: {$conf} [dnstap] listen={$kv['listen']} perm={$kv['perm']}\n";
}

function xray_dnstap_write_unbound_dnstap(bool $enable): void
{
    $dst = XRAY_DNSTAP_UNBOUND_CONF;
    $dir = dirname($dst);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $yesno = $enable ? 'yes' : 'no';
    $body = implode("\n", [
        '# managed by os-xray — do not paste into Unbound GUI Custom options',
        '# Unbound chroot /var/unbound: socket path below is inside the jail.',
        '# Host / dnstap-bgp listen: ' . XRAY_DNSTAP_SOCK,
        '',
        'dnstap:',
        "\tdnstap-enable: {$yesno}",
        "\tdnstap-socket-path: \"" . XRAY_DNSTAP_SOCK_CHROOT . '"',
        "\tdnstap-log-client-response-messages: yes",
        '',
    ]);
    if (file_put_contents($dst, $body) === false) {
        echo "dnstap: cannot write {$dst}\n";
        return;
    }
    @chmod($dst, 0644);
    echo "dnstap: {$dst} dnstap-enable={$yesno} socket=" . XRAY_DNSTAP_SOCK_CHROOT . "\n";
}

function xray_unbound_reload(): void
{
    $cmds = [
        '/usr/local/sbin/configctl unbound reload',
        '/usr/sbin/service unbound reload',
        '/usr/local/sbin/configctl unbound restart',
    ];
    foreach ($cmds as $cmd) {
        $out = [];
        exec($cmd . ' 2>&1', $out, $rc);
        if ($rc === 0) {
            echo "dnstap: unbound reloaded ({$cmd})\n";
            return;
        }
        echo "dnstap: {$cmd} failed: " . implode(' ', $out) . "\n";
    }
}

function xray_dnstap_ensure_domain_files(): void
{
    $dir = '/usr/local/etc/dnstap-bgp';
    if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
        echo "dnstap: cannot mkdir {$dir}\n";
        return;
    }
    $legacy = $dir . '/domains.txt';
    $blocked = $dir . '/blocked.txt';
    $unblocked = $dir . '/unblocked.txt';
    if (is_readable($legacy) && !is_file($blocked)) {
        @copy($legacy, $blocked);
        echo "dnstap: migrated {$legacy} → {$blocked}\n";
    }
    $emptyDomains = "# One lowercase FQDN per line. IDN/punycode is not supported.\n";
    $emptyUrls = "# HTTP(S) URLs of domain lists. One URL per line.\n";
    $files = [
        $blocked                      => $emptyDomains,
        $unblocked                    => $emptyDomains,
        $dir . '/blocked-extra.txt'   => $emptyDomains,
        $dir . '/unblocked-extra.txt' => $emptyDomains,
        $dir . '/blocked-urls.txt'    => $emptyUrls,
        $dir . '/unblocked-urls.txt'  => $emptyUrls,
    ];
    foreach ($files as $path => $body) {
        if (is_file($path)) {
            continue;
        }
        if (@file_put_contents($path, $body) === false) {
            echo "dnstap: cannot create {$path}\n";
            continue;
        }
        @chmod($path, 0644);
        echo "dnstap: created empty {$path}\n";
    }
}

function xray_dnstap_unbound_activate(): void
{
    exec('/usr/sbin/service dnstap_bgp stop 2>&1');

    if (!is_dir(XRAY_DNSTAP_SOCK_DIR) && !@mkdir(XRAY_DNSTAP_SOCK_DIR, 0755, true)) {
        echo "dnstap: cannot mkdir " . XRAY_DNSTAP_SOCK_DIR . "\n";
    } else {
        exec('chown unbound:unbound ' . escapeshellarg(XRAY_DNSTAP_SOCK_DIR) . ' 2>&1');
        echo "dnstap: " . XRAY_DNSTAP_SOCK_DIR . " unbound:unbound\n";
    }

    xray_dnstap_write_unbound_dnstap(true);
    xray_dnstap_write_bgp_listen();
    xray_dnstap_ensure_domain_files();
    $blockedList   = '/usr/local/etc/dnstap-bgp/blocked.txt';
    $unblockedList = '/usr/local/etc/dnstap-bgp/unblocked.txt';
    $as = xray_dnstap_bird_local_as();
    if (is_readable(XRAY_DNSTAP_BGP_CONF)) {
        $text = (string)file_get_contents(XRAY_DNSTAP_BGP_CONF);
        $text = xray_dnstap_toml_upsert_root($text, [
            'domains'           => $blockedList,
            'blocked_domains'   => $blockedList,
            'unblocked_domains' => $unblockedList,
        ]);
        $text = xray_dnstap_toml_upsert_section($text, 'bgp', ['as' => (string)$as]);
        @file_put_contents(XRAY_DNSTAP_BGP_CONF, $text);
        echo "dnstap: bgp.as={$as} (BIRD local AS)\n";
        echo "dnstap: blocked_domains={$blockedList} unblocked_domains={$unblockedList}\n";
    }
    xray_dnstap_sync_rc_from_bgp();
    xray_unbound_reload();
    exec('/usr/sbin/service dnstap_bgp start 2>&1');
    echo "dnstap: dnstap_bgp start (Unbound already reloaded)\n";
    xray_dnstap_sync_bird(true);
}

function xray_dnstap_unbound_deactivate(): void
{
    exec('/usr/sbin/service dnstap_bgp stop 2>&1');
    echo "dnstap: dnstap_bgp stop\n";

    xray_dnstap_write_unbound_dnstap(false);
    xray_unbound_reload();
    xray_dnstap_sync_bird(false);
}
