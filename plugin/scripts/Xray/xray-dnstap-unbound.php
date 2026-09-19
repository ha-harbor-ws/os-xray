<?php
/**
 * Wire Unbound DNSTap include to dnstap-bgp socket on start; undo on stop.
 */

const XRAY_DNSTAP_UNBOUND_SAMPLE = '/usr/local/etc/unbound.opnsense.d/dnstap.conf.sample';
const XRAY_DNSTAP_UNBOUND_CONF   = '/usr/local/etc/unbound.opnsense.d/dnstap.conf';
const XRAY_DNSTAP_SOCK_DIR       = '/var/unbound/var/run/dnstap-bgp';
const XRAY_DNSTAP_SOCK           = '/var/unbound/var/run/dnstap-bgp/dnstap.sock';
const XRAY_DNSTAP_BGP_CONF       = '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf';
const XRAY_DNSTAP_BGP_SAMPLE     = '/usr/local/etc/dnstap-bgp/dnstap-bgp.conf.sample';
const XRAY_DNSTAP_PERM           = '0666';

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
                $out[] = $k . ' = "' . str_replace(['\\', '"'], ['\\\\', '\\"'], (string)$v) . '"';
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
            $out[] = $k . ' = "' . str_replace(['\\', '"'], ['\\\\', '\\"'], (string)$kv[$k]) . '"';
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
            $out[] = $k . ' = "' . str_replace(['\\', '"'], ['\\\\', '\\"'], (string)$v) . '"';
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

function xray_dnstap_write_bgp_listen(bool $enable): void
{
    $conf = XRAY_DNSTAP_BGP_CONF;
    $dir = dirname($conf);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $text = is_readable($conf) ? (string)file_get_contents($conf) : '';
    if ($enable) {
        $kv = ['listen' => XRAY_DNSTAP_SOCK, 'perm' => XRAY_DNSTAP_PERM];
    } else {
        $kv = ['listen' => '/var/run/dnstap-bgp/dnstap.sock', 'perm' => XRAY_DNSTAP_PERM];
        if (is_readable(XRAY_DNSTAP_BGP_SAMPLE)) {
            $fromSample = xray_dnstap_toml_section_kv(
                (string)file_get_contents(XRAY_DNSTAP_BGP_SAMPLE),
                'dnstap'
            );
            if (isset($fromSample['listen'])) {
                $kv['listen'] = $fromSample['listen'];
            }
            if (isset($fromSample['perm'])) {
                $kv['perm'] = $fromSample['perm'];
            }
        }
    }
    $new = xray_dnstap_toml_upsert_section($text, 'dnstap', $kv);
    if (file_put_contents($conf, $new) === false) {
        echo "dnstap: cannot write {$conf}\n";
        return;
    }
    echo "dnstap: {$conf} [dnstap] listen={$kv['listen']} perm={$kv['perm']}\n";
}

function xray_unbound_reload(): void
{
    exec('/usr/local/sbin/configctl unbound restart 2>&1', $out, $rc);
    if ($rc === 0) {
        echo "dnstap: unbound restarted (configctl unbound restart)\n";
        return;
    }
    echo "dnstap: configctl unbound restart failed: " . implode(' ', $out) . "\n";
}

function xray_dnstap_unbound_activate(): void
{
    exec('/usr/sbin/service dnstap_bgp stop 2>&1');
    $sample = XRAY_DNSTAP_UNBOUND_SAMPLE;
    $dst = XRAY_DNSTAP_UNBOUND_CONF;
    $dir = dirname($dst);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    if (!is_file($sample)) {
        echo "dnstap: missing {$sample} — Unbound include not copied\n";
    } elseif (!@copy($sample, $dst)) {
        echo "dnstap: cannot copy {$sample} → {$dst}\n";
    } else {
        @chmod($dst, 0644);
        echo "dnstap: {$dst} from sample\n";
    }

    if (!is_dir(XRAY_DNSTAP_SOCK_DIR) && !@mkdir(XRAY_DNSTAP_SOCK_DIR, 0755, true)) {
        echo "dnstap: cannot mkdir " . XRAY_DNSTAP_SOCK_DIR . "\n";
    } else {
        exec('chown unbound:unbound ' . escapeshellarg(XRAY_DNSTAP_SOCK_DIR) . ' 2>&1');
        echo "dnstap: " . XRAY_DNSTAP_SOCK_DIR . " unbound:unbound\n";
    }

    xray_dnstap_write_bgp_listen(true);
    xray_unbound_reload();
    exec('/usr/sbin/service dnstap_bgp start 2>&1');
    echo "dnstap: dnstap_bgp start\n";
}

function xray_dnstap_unbound_deactivate(): void
{
    exec('/usr/sbin/service dnstap_bgp stop 2>&1');
    echo "dnstap: dnstap_bgp stop\n";

    if (is_file(XRAY_DNSTAP_UNBOUND_CONF)) {
        @unlink(XRAY_DNSTAP_UNBOUND_CONF);
        echo "dnstap: removed " . XRAY_DNSTAP_UNBOUND_CONF . "\n";
    }

    xray_dnstap_write_bgp_listen(false);
    xray_unbound_reload();
}
