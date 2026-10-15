#!/usr/local/bin/php
<?php
/**
 * Cron IF health (every 5 min): Test all IF for enabled+running instances.
 * If the current ACTIVE_TUN4/6 instance fails the SOCKS IF probe — one-shot
 * reselect active tun2socks (same as Test auto route).
 */

require_once('config.inc');
require_once(__DIR__ . '/xray-boot-log.inc.php');
require_once(__DIR__ . '/xray-bird-active-tun.php');

function xray_if_health_curl(string $listen, int $port): array
{
    $connectAddr = ($listen === '0.0.0.0') ? '127.0.0.1' : $listen;
    if ($port < 1 || $port > 65535) {
        $port = 10808;
    }
    $proxy = $connectAddr . ':' . $port;
    $out   = [];
    exec(
        '/usr/local/bin/curl'
        . ' --socks5 ' . escapeshellarg($proxy)
        . ' -s -L -o /dev/null'
        . ' -w %{http_code}'
        . ' ' . escapeshellarg('https://1.1.1.1')
        . ' --max-time 10',
        $out,
        $rc
    );
    $code = trim(implode('', $out));
    $http = (int)$code;
    $ok   = ($rc === 0 && $http >= 200 && $http < 400);
    return [
        'ok'    => $ok,
        'http'  => $http,
        'proxy' => $proxy,
        'code'  => $code !== '' ? $code : '0',
    ];
}

$cfg     = OPNsense\Core\Config::getInstance()->object();
$general = $cfg->OPNsense->xray->general ?? null;
$ins     = $cfg->OPNsense->xray->instances ?? null;

if ((string)($general->enabled ?? '0') !== '1' || !$ins) {
    echo "if health: plugin disabled or no instances\n";
    exit(0);
}

$cands = xray_bird_active_tun_candidates($ins);
if ($cands === []) {
    echo "if health: no enabled running instances\n";
    exit(0);
}

$byTun  = [];
$lines  = [];
$failed = [];
foreach ($cands as $c) {
    $byTun[$c['tun']] = $c;
    $p = xray_if_health_curl($c['listen'], $c['port']);
    $status = $p['ok'] ? 'ok' : 'failed';
    $lines[] = "[{$c['name']}] tun={$c['tun']} socks={$p['proxy']} HTTP {$p['code']} {$status}";
    echo $lines[count($lines) - 1] . "\n";
    if (!$p['ok']) {
        $failed[$c['uuid']] = $c;
    }
}

$act4 = xray_bird_active_tun_current(
    XRAY_BIRD_INC_DIR . '/active_tun_v4.inc',
    'ACTIVE_TUN4_IF'
);
$act6 = xray_bird_active_tun_current(
    XRAY_BIRD_INC_DIR . '/active_tun_v6.inc',
    'ACTIVE_TUN6_IF'
);

$activeFailed = [];
foreach (['v4' => $act4, 'v6' => $act6] as $fam => $tun) {
    if ($tun === '') {
        continue;
    }
    if (!isset($byTun[$tun])) {
        $activeFailed[] = "ACTIVE_TUN{$fam}={$tun} not enabled/running";
        continue;
    }
    $c = $byTun[$tun];
    if (isset($failed[$c['uuid']])) {
        $activeFailed[] = "ACTIVE_TUN{$fam}={$tun} ({$c['name']}) IF failed";
    }
}

$reselected = false;
$selMsg     = '';
if ($activeFailed !== []) {
    echo "if health: active IF failed — " . implode('; ', $activeFailed) . "\n";
    echo "if health: reselecting active tun\n";
    $sel = xray_bird_select_and_write_active_tun();
    if (!empty($sel['changed'])) {
        $cfgObj = OPNsense\Core\Config::getInstance()->object();
        $bgpOn  = (string)($cfgObj->OPNsense->xray->general->bgp_enabled ?? '0') === '1';
        if ($bgpOn) {
            xray_bird_active_tun_configure();
            $selMsg = 'active tun changed — birdc configure';
        } else {
            $selMsg = 'active tun changed — BGP off, files only';
        }
        $reselected = true;
    } else {
        $selMsg = 'reselect ran, active tun unchanged';
    }
    echo "if health: {$selMsg}\n";
} else {
    echo "if health: active IF ok (v4={$act4}, v6={$act6})\n";
}

$body = implode("\n", $lines) . "\n"
    . "active_v4={$act4} active_v6={$act6}\n";
if ($activeFailed !== []) {
    $body .= 'active failed: ' . implode('; ', $activeFailed) . "\n"
        . ($selMsg !== '' ? "action: {$selMsg}\n" : '');
} else {
    $body .= "action: none (active IF ok)\n";
}

xray_boot_log_block('IF health (cron)', $body);
echo "RESULT:OK\n";
exit(0);
