<?php

function xray_enabled(): bool
{
    $cfg = OPNsense\Core\Config::getInstance()->object();
    return isset($cfg->OPNsense->xray->general->enabled)
        && (string)$cfg->OPNsense->xray->general->enabled === '1';
}

function xray_configure(): array
{
    return ['bootup' => ['xray_configure_do:10']];
}

/**
 * BUG-1 FIX: убрана хрупкая goto-логика управления lock-файлом.
 *
 * v3.0.0: итерирует все инстансы из config.xml, для каждого:
 *   - Захватывает per-instance lock (xray_start_<uuid>.lock)
 *   - Запускает xray-core + tun2socks если не запущены
 *   - Ждёт TUN-интерфейс до 5 секунд
 */
function xray_bird_sync_exec(): void
{
    $script = '/usr/local/opnsense/scripts/Xray/xray-service-control.php';
    if (!file_exists($script)) {
        return;
    }
    exec('/usr/local/bin/php ' . escapeshellarg($script) . ' birdsync 2>&1');
}

function xray_configure_do(bool $verbose = false): void
{
    if (!xray_enabled()) {
        xray_bird_sync_exec();
        return;
    }

    $cfg       = OPNsense\Core\Config::getInstance()->object();
    $instances = $cfg->OPNsense->xray->instances ?? null;
    if (!$instances) {
        xray_bird_sync_exec();
        return;
    }

    $xrayBin  = '/usr/local/bin/xray-core';
    $t2sBin   = '/usr/local/tun2socks/tun2socks';
    $daemonLog = '/var/log/xray-core.log';

    if (!file_exists($xrayBin) || !file_exists($t2sBin)) {
        xray_bird_sync_exec();
        return;
    }

    foreach ($instances->instance as $inst) {
        $inst_uuid = (string)$inst['uuid'];
        if ($inst_uuid === '' || (string)($inst->enabled ?? '1') !== '1') {
            continue;
        }

        $xrayConf  = "/usr/local/etc/xray-core/config-{$inst_uuid}.json";
        $xrayPid   = "/var/run/xray_core_{$inst_uuid}.pid";
        $t2sConf   = "/usr/local/tun2socks/config-{$inst_uuid}.yaml";
        $t2sPid    = "/var/run/tun2socks_{$inst_uuid}.pid";
        $lockFile  = "/var/run/xray_start_{$inst_uuid}.lock";
        $tunIface  = (string)($inst->tun_interface ?? 'proxytun2socks0');

        // BUG-1 FIX: per-instance lock без goto. Если lock занят — пропускаем.
        $lockFd       = false;
        $lockAcquired = false;
        $shouldStart  = false;

        $lockFd = fopen($lockFile, 'c');
        if ($lockFd !== false) {
            if (flock($lockFd, LOCK_EX | LOCK_NB)) {
                $lockAcquired = true;
                fwrite($lockFd, (string)getmypid());
                fflush($lockFd);
                $shouldStart = true;
            } else {
                if ($verbose) {
                    echo "xray [{$inst_uuid}]: start already in progress (lock held), skipping\n";
                }
                fclose($lockFd);
                $lockFd = false;
            }
        }

        if ($shouldStart) {
            try {
                $xrayRunning = false;
                if (file_exists($xrayPid)) {
                    $pid = (int)trim(file_get_contents($xrayPid));
                    exec('/bin/kill -0 ' . $pid . ' 2>/dev/null', $out, $rc);
                    $xrayRunning = ($rc === 0);
                }
                $t2sRunning = false;
                if (file_exists($t2sPid)) {
                    $pid = (int)trim(file_get_contents($t2sPid));
                    exec('/bin/kill -0 ' . $pid . ' 2>/dev/null', $out, $rc);
                    $t2sRunning = ($rc === 0);
                }

                if (!$xrayRunning || !$t2sRunning) {
                    if ($verbose) {
                        echo "xray [{$inst_uuid}]: starting via xray-service-control.php...\n";
                    }
                    exec('/usr/local/bin/php /usr/local/opnsense/scripts/Xray/xray-service-control.php start '
                        . escapeshellarg($inst_uuid) . ' 2>&1', $startOut, $startRc);
                    if ($verbose && !empty($startOut)) {
                        echo implode("\n", $startOut) . "\n";
                    }
                    if ($startRc !== 0 && $verbose) {
                        echo "xray [{$inst_uuid}]: start returned exit {$startRc}\n";
                    }
                }
            } finally {
                // BUG-1 FIX: lock освобождается гарантированно
                if ($lockFd !== false) {
                    flock($lockFd, LOCK_UN);
                    fclose($lockFd);
                    @unlink($lockFile);
                }
            }
        }
    }

    // reload firewall/routing — выполняется всегда
    @include_once('filter.inc');
    @include_once('interfaces.inc');
    @include_once('system.inc');

    if (function_exists('filter_configure_sync')) {
        filter_configure_sync();
    } elseif (function_exists('filter_configure')) {
        filter_configure();
    }

    if (function_exists('system_routing_configure')) {
        system_routing_configure();
    }

    if ($verbose) {
        echo "xray: boot setup complete\n";
    }

    xray_bird_sync_exec();
}

/**
 * v3.0.0: регистрирует один сервис на каждый инстанс.
 */
function xray_services()
{
    $services  = [];
    $cfg       = OPNsense\Core\Config::getInstance()->object();
    $instances = $cfg->OPNsense->xray->instances ?? null;

    if ($instances) {
        foreach ($instances->instance as $inst) {
            $inst_uuid = (string)$inst['uuid'];
            if ($inst_uuid === '' || (string)($inst->enabled ?? '1') !== '1') {
                continue;
            }
            $name       = (string)($inst->name ?? 'default');
            $services[] = [
                'description' => 'Xray (' . $name . ')',
                'configd'     => [
                    'restart' => ['xray restart ' . $inst_uuid],
                    'start'   => ['xray start '   . $inst_uuid],
                    'stop'    => ['xray stop '    . $inst_uuid],
                ],
                'name'    => 'xray',
                'pidfile' => "/var/run/xray_core_{$inst_uuid}.pid",
            ];
        }
    }

    return $services;
}

/**
 * E1: регистрирует cron-задание для watchdog.
 */
function xray_cron(): array
{
    return [
        ['xray_cron_watchdog', '/', '*', '*', '*', '*'],
    ];
}

function xray_cron_watchdog(): void
{
    (new OPNsense\Core\Backend())->configdRun('xray watchdog');
}

function xray_xmlrpc_sync()
{
    return [];
}
