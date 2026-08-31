#!/usr/local/bin/php
<?php

require_once('config.inc');

// ─── Shared constants (not per-instance) ─────────────────────────────────────
define('XRAY_BIN',          '/usr/local/bin/xray-core');
define('XRAY_CONF_DIR',     '/usr/local/etc/xray-core');
define('T2S_BIN',           '/usr/local/tun2socks/tun2socks');
define('T2S_CONF_DIR',      '/usr/local/tun2socks');
// BUG-7 FIX: stderr демонов в лог-файл вместо /dev/null
define('XRAY_DAEMON_LOG',   '/var/log/xray-core.log'); // общий лог (fallback)
define('XRAY_VERSION_FILE', '/usr/local/opnsense/mvc/app/models/OPNsense/Xray/version.txt');

// ─── Per-instance path functions ─────────────────────────────────────────────
// v3.0.0: все runtime-файлы именуются по UUID инстанса, чтобы N инстансов
// не конфликтовали за один PID-файл / конфиг / lock.
function xray_conf_path(string $inst_uuid): string
{
    return XRAY_CONF_DIR . "/config-{$inst_uuid}.json";
}
function xray_pid_path(string $inst_uuid): string
{
    return "/var/run/xray_core_{$inst_uuid}.pid";
}
function t2s_conf_path(string $inst_uuid): string
{
    return T2S_CONF_DIR . "/config-{$inst_uuid}.yaml";
}
function t2s_pid_path(string $inst_uuid): string
{
    return "/var/run/tun2socks_{$inst_uuid}.pid";
}
function xray_lock_path(string $inst_uuid): string
{
    return "/var/run/xray_start_{$inst_uuid}.lock";
}
function xray_stopped_flag(string $inst_uuid): string
{
    return "/var/run/xray_stopped_{$inst_uuid}.flag";
}
function xray_instance_log(string $inst_uuid): string
{
    return "/var/log/xray-core-{$inst_uuid}.log";
}

// ─── Read config from OPNsense config.xml ────────────────────────────────────

/**
 * Парсит один <instance> SimpleXMLElement в плоский PHP-массив конфига.
 * globalEnabled — значение general.enabled (общий выключатель плагина).
 */
function xray_parse_instance($inst, bool $globalEnabled): array
{
    // B6: нормализация loglevel.
    // Старые: ключ "e" (до v1.0.1) → "error"
    // Новые:  ключ "loglevel_error" (v1.0.1+) → "error"
    $rawLevel = (string)($inst->loglevel ?? 'warning');
    $levelMap = [
        'e'              => 'error',
        'loglevel_error' => 'error',
    ];
    $loglevel = $levelMap[$rawLevel] ?? ($rawLevel ?: 'warning');

    return [
        'enabled'         => $globalEnabled && (string)($inst->enabled ?? '1') === '1',
        'name'            => (string)($inst->name             ?? 'default'),
        'outbound_config' => (string)($inst->outbound_config  ?? ''),
        'socks5_listen'   => (string)($inst->socks5_listen    ?? '127.0.0.1') ?: '127.0.0.1',
        'socks5_port'     => (int)(string)($inst->socks5_port ?? 10808) ?: 10808,
        'tun_iface'       => (string)($inst->tun_interface    ?? 'proxytun2socks0'),
        'mtu'             => (int)(string)($inst->mtu         ?? 1500),
        'use_ipv4'        => (string)($inst->use_ipv4         ?? '1'),
        'use_ipv6'        => (string)($inst->use_ipv6         ?? '0'),
        'dns_servers'     => (string)($inst->dns_servers      ?? '1.1.1.1,8.8.8.8') ?: '1.1.1.1,8.8.8.8',
        'loglevel'        => $loglevel,
        'bypass_networks' => (string)($inst->bypass_networks  ?? '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16')
                            ?: '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16',
    ];
}

function xray_ip_version_flags(array $c): array
{
    return [
        'use_ipv4' => (string)($c['use_ipv4'] ?? '1') === '1',
        'use_ipv6' => (string)($c['use_ipv6'] ?? '0') === '1',
    ];
}

function xray_ip_query_strategy(bool $useIpv4, bool $useIpv6): string
{
    if ($useIpv4 && $useIpv6) {
        return 'UseIP';
    }
    if ($useIpv6) {
        return 'UseIPv6';
    }
    return 'UseIPv4';
}

/**
 * routing.domainStrategy: AsIs / IPIfNonMatch / IPOnDemand.
 * Dual-stack → IPIfNonMatch; только IPv4 или только IPv6 → IPOnDemand.
 * Выбор семейства адресов — через dns.queryStrategy и правила block.
 */
function xray_routing_domain_strategy(bool $useIpv4, bool $useIpv6): string
{
    if ($useIpv4 && $useIpv6) {
        return 'IPIfNonMatch';
    }
    return 'IPOnDemand';
}

function xray_validate_ip_stack(array $c, string $inst_uuid = ''): bool
{
    $flags = xray_ip_version_flags($c);
    if ($flags['use_ipv4'] || $flags['use_ipv6']) {
        return true;
    }
    $suffix = $inst_uuid !== '' ? " for instance {$inst_uuid}" : '';
    echo "ERROR: At least one of IPv4 or IPv6 must be enabled{$suffix}.\n";
    return false;
}

/**
 * Читает все инстансы из config.xml.
 * Возвращает массив, индексированный по inst_uuid (UUID инстанса OPNsense).
 */
function xray_get_all_instances(): array
{
    $cfg = OPNsense\Core\Config::getInstance()->object();
    $g   = $cfg->OPNsense->xray->general   ?? null;
    $ins = $cfg->OPNsense->xray->instances  ?? null;

    $globalEnabled = (string)($g->enabled ?? '0') === '1';

    if (!$ins) {
        return [];
    }

    $result = [];
    foreach ($ins->instance as $inst) {
        // SimpleXML: атрибуты читаются через $element['attr']
        $inst_uuid = (string)$inst['uuid'];
        if ($inst_uuid === '') {
            continue;
        }
        $c = xray_parse_instance($inst, $globalEnabled);
        $c['inst_uuid'] = $inst_uuid;
        $result[$inst_uuid] = $c;
    }
    return $result;
}

/**
 * Читает конфиг конкретного инстанса по его UUID.
 * Если UUID не указан — возвращает первый найденный инстанс (обратная совместимость).
 */
function xray_get_config(string $inst_uuid = ''): array
{
    $all = xray_get_all_instances();
    if (empty($all)) {
        return [];
    }
    if ($inst_uuid !== '' && isset($all[$inst_uuid])) {
        return $all[$inst_uuid];
    }
    // Возвращаем первый инстанс если UUID не указан
    return reset($all);
}

// ─── Build routing block from comma-separated CIDR string ────────────────────
/**
 * domainStrategy на уровне outbound (proxy): только IPv4 → UseIPv4, только IPv6 → UseIPv6.
 * Dual-stack — поле не трогаем (оставляем как в outbound_config / дефолт xray).
 */
function xray_outbound_domain_strategy(bool $useIpv4, bool $useIpv6): ?string
{
    if ($useIpv4 && !$useIpv6) {
        return 'UseIPv4';
    }
    if ($useIpv6 && !$useIpv4) {
        return 'UseIPv6';
    }
    return null;
}

function xray_build_outbounds(array $proxyOutbound, array $c): array
{
    $flags = xray_ip_version_flags($c);
    $ds    = xray_outbound_domain_strategy($flags['use_ipv4'], $flags['use_ipv6']);
    if ($ds !== null) {
        $proxyOutbound['domainStrategy'] = $ds;
    }

    $outbounds = [
        $proxyOutbound,
        ['tag' => 'direct', 'protocol' => 'freedom'],
    ];
    if (!$flags['use_ipv4'] || !$flags['use_ipv6']) {
        $outbounds[] = ['tag' => 'block', 'protocol' => 'blackhole'];
    }
    return $outbounds;
}

function xray_build_routing(string $bypassRaw, array $c): array
{
    $bypassNets = array_values(array_filter(array_map('trim', explode(',', $bypassRaw))));
    if (empty($bypassNets)) {
        $bypassNets = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];
    }
    $flags = xray_ip_version_flags($c);
    $rules = [];

    // Блокировка IPv6 в routing, если чекбокс IPv6 выключен (TUN IPv6 при этом может быть назначен)
    if (!$flags['use_ipv6']) {
        $rules[] = [
            'type'        => 'field',
            'ip'          => ['::/0'],
            'outboundTag' => 'block',
        ];
    }
    if (!$flags['use_ipv4']) {
        $rules[] = [
            'type'        => 'field',
            'ip'          => ['0.0.0.0/0'],
            'outboundTag' => 'block',
        ];
    }

    $rules[] = [
        'type'        => 'field',
        'ip'          => $bypassNets,
        'outboundTag' => 'direct',
    ];

    return [
        'domainStrategy' => xray_routing_domain_strategy($flags['use_ipv4'], $flags['use_ipv6']),
        'rules'          => $rules,
    ];
}

// ─── DNS block: per-instance servers + IP stack query strategy ───────────────
function xray_build_dns(array $c): array
{
    $raw = trim($c['dns_servers'] ?? '');
    $servers = array_values(array_filter(array_map('trim', explode(',', $raw))));
    if (empty($servers)) {
        $servers = ['1.1.1.1', '8.8.8.8'];
    }
    $flags = xray_ip_version_flags($c);
    return [
        'servers'       => $servers,
        'queryStrategy' => xray_ip_query_strategy($flags['use_ipv4'], $flags['use_ipv6']),
    ];
}

/**
 * Собирает полный config.json для xray-core из параметров инстанса.
 *
 * @return array|null null при ошибке outbound_config
 */
function xray_build_config_array(array $c): ?array
{
    $raw = trim($c['outbound_config'] ?? '');
    if ($raw === '') {
        echo "ERROR: outbound_config is empty\n";
        return null;
    }
    $outbound = json_decode($raw, true);
    if ($outbound === null) {
        echo "ERROR: outbound_config is not valid JSON\n";
        return null;
    }

    return [
        'log'       => ['loglevel' => $c['loglevel'] ?? 'warning'],
        'dns'       => xray_build_dns($c),
        'inbounds'  => [[
            'tag'      => 'socks-in',
            'port'     => (int)($c['socks5_port'] ?? 10808),
            'listen'   => $c['socks5_listen'] ?? '127.0.0.1',
            'protocol' => 'socks',
            'settings' => ['auth' => 'noauth', 'udp' => true, 'ip' => $c['socks5_listen'] ?? '127.0.0.1'],
            'sniffing' => [
                'enabled'      => true,
                'destOverride' => ['http', 'tls', 'quic'],
                'metadataOnly' => false,
            ],
        ]],
        'outbounds' => xray_build_outbounds($outbound, $c),
        'routing'   => xray_build_routing($c['bypass_networks'] ?? '', $c),
    ];
}

// ─── P2.5: xhttp/splithttp compatibility ─────────────────────────────────────
function xray_normalize_transport(string $json): string
{
    if (!file_exists(XRAY_BIN)) {
        return $json;
    }
    exec(escapeshellarg(XRAY_BIN) . ' version 2>/dev/null', $out);
    $verLine = $out[0] ?? '';

    if (preg_match('/Xray\s+1\./', $verLine)) {
        $json = str_replace('"xhttp"', '"splithttp"', $json);
        $json = str_replace('"xhttpSettings"', '"splithttpSettings"', $json);
    }

    return $json;
}

// ─── Write xray config.json (per-instance) ───────────────────────────────────
function xray_write_config(array $c): bool
{
    if (!is_dir(XRAY_CONF_DIR)) {
        if (!mkdir(XRAY_CONF_DIR, 0750, true) && !is_dir(XRAY_CONF_DIR)) {
            echo "ERROR: Cannot create config directory " . XRAY_CONF_DIR . "\n";
            return false;
        }
    }

    $inst_uuid = $c['inst_uuid'] ?? '';
    if ($inst_uuid === '') {
        echo "ERROR: inst_uuid is empty, cannot write config\n";
        return false;
    }
    $confFile  = xray_conf_path($inst_uuid);

    $config = xray_build_config_array($c);
    if ($config === null) {
        return false;
    }
    $json = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        echo "ERROR: Failed to encode config JSON\n";
        return false;
    }
    $json = xray_normalize_transport($json);

    if (file_put_contents($confFile, $json) === false) {
        echo "ERROR: Failed to write config file {$confFile}\n";
        return false;
    }
    chmod($confFile, 0640);
    echo "INFO: Wrote xray config {$confFile}\n";
    return true;
}

// ─── Write tun2socks config.yaml (per-instance) ──────────────────────────────
function t2s_write_config(array $c): void
{
    if (!is_dir(T2S_CONF_DIR)) {
        mkdir(T2S_CONF_DIR, 0750, true);
    }
    $inst_uuid = $c['inst_uuid'];
    $yaml = "proxy: socks5://{$c['socks5_listen']}:{$c['socks5_port']}\n"
          . "device: {$c['tun_iface']}\n"
          . "mtu: {$c['mtu']}\n"
          . "loglevel: info\n";
    file_put_contents(t2s_conf_path($inst_uuid), $yaml);
    chmod(t2s_conf_path($inst_uuid), 0640);
}

// ─── PID helpers (FreeBSD: no posix extension — use /bin/kill) ───────────────
function proc_is_running(string $pidfile): bool
{
    if (!file_exists($pidfile)) {
        return false;
    }
    $pid = (int)trim(file_get_contents($pidfile));
    if ($pid <= 0) {
        return false;
    }
    exec('/bin/kill -0 ' . $pid . ' 2>/dev/null', $out, $rc);
    return $rc === 0;
}

function proc_kill(string $pidfile): void
{
    if (!file_exists($pidfile)) {
        return;
    }
    $pid = (int)trim(file_get_contents($pidfile));
    if ($pid > 0) {
        // БАГ-4 FIX: проверяем что PID принадлежит нашему процессу
        $comm = trim((string)shell_exec('ps -o comm= -p ' . $pid . ' 2>/dev/null'));
        if ($comm === '' || (strpos($comm, 'xray') === false && strpos($comm, 'tun2socks') === false)) {
            @unlink($pidfile);
            return;
        }

        exec('/bin/kill -TERM ' . $pid . ' 2>/dev/null');
        $i = 0;
        while ($i++ < 30) {
            exec('/bin/kill -0 ' . $pid . ' 2>/dev/null', $out, $rc);
            if ($rc !== 0) {
                break;
            }
            usleep(100000);
        }
        exec('/bin/kill -0 ' . $pid . ' 2>/dev/null', $out2, $rc2);
        if ($rc2 === 0) {
            exec('/bin/kill -KILL ' . $pid . ' 2>/dev/null');
        }
    }
    @unlink($pidfile);
}

function proc_start(string $bin, string $args, string $pidfile, string $logfile = ''): void
{
    // BUG-7 FIX: stderr демона → XRAY_DAEMON_LOG вместо /dev/null
    $log = escapeshellarg($logfile !== '' ? $logfile : XRAY_DAEMON_LOG);
    exec('/usr/sbin/daemon -p ' . escapeshellarg($pidfile)
       . ' ' . escapeshellarg($bin) . ' ' . $args . ' >> ' . $log . ' 2>&1 &');
}

// ─── Per-instance lock helpers ────────────────────────────────────────────────
/**
 * Захватывает эксклюзивный non-blocking lock для конкретного инстанса.
 * Возвращает дескриптор при успехе, false если lock уже захвачен.
 * Вызывающий ОБЯЗАН вызвать lock_release($fd, $inst_uuid) после завершения.
 *
 * @return resource|false
 */
function lock_acquire(string $inst_uuid)
{
    $lockPath = xray_lock_path($inst_uuid);
    $fd = fopen($lockPath, 'c');
    if ($fd === false) {
        return false;
    }
    if (!flock($fd, LOCK_EX | LOCK_NB)) {
        fclose($fd);
        return false;
    }
    fwrite($fd, (string)getmypid());
    fflush($fd);
    return $fd;
}

/**
 * Освобождает lock инстанса, закрывает дескриптор, удаляет lock-файл.
 *
 * @param resource $fd
 */
function lock_release($fd, string $inst_uuid): void
{
    flock($fd, LOCK_UN);
    fclose($fd);
    @unlink(xray_lock_path($inst_uuid));
}

// ─── BUG-3 FIX: config validation before start ──────────────────────────────
function xray_validate_config(string $confFile): bool
{
    if (!file_exists(XRAY_BIN)) {
        return true;
    }
    if (!file_exists($confFile)) {
        echo "ERROR: config file not found after write: {$confFile}\n";
        return false;
    }
    exec(escapeshellarg(XRAY_BIN) . ' -test -c ' . escapeshellarg($confFile) . ' 2>&1', $out, $rc);
    if ($rc !== 0) {
        echo "ERROR: xray config validation failed:\n" . implode("\n", $out) . "\n";
        return false;
    }
    return true;
}

// ─── lo0 alias management ─────────────────────────────────────────────────────
function lo0_needs_alias(string $addr): bool
{
    if ($addr === '127.0.0.1' || $addr === '0.0.0.0') {
        return false;
    }
    $parts = explode('.', $addr);
    return count($parts) === 4 && $parts[0] === '127';
}

function lo0_alias_ensure(string $addr): void
{
    if (!lo0_needs_alias($addr)) {
        return;
    }
    exec('/sbin/ifconfig lo0 2>/dev/null', $out, $rc);
    if ($rc !== 0) {
        echo "WARNING: Cannot read lo0 interface\n";
        return;
    }
    $ifOutput = implode("\n", $out);
    if (strpos($ifOutput, $addr) !== false) {
        return;
    }
    exec('/sbin/ifconfig lo0 alias ' . escapeshellarg($addr) . ' 2>/dev/null', $out2, $rc2);
    if ($rc2 !== 0) {
        echo "WARNING: Failed to add lo0 alias {$addr}\n";
    } else {
        echo "INFO: Added lo0 alias {$addr}\n";
    }
}

function lo0_alias_remove(string $addr): void
{
    if (!lo0_needs_alias($addr)) {
        return;
    }
    exec('/sbin/ifconfig lo0 -alias ' . escapeshellarg($addr) . ' 2>/dev/null', $out, $rc);
    if ($rc === 0) {
        echo "INFO: Removed lo0 alias {$addr}\n";
    }
}

// ─── B9: TUN interface teardown ───────────────────────────────────────────────
function tun_iface_exists(string $iface): bool
{
    if ($iface === '') {
        return false;
    }
    exec('/sbin/ifconfig ' . escapeshellarg($iface) . ' 2>/dev/null', $out, $rc);
    return $rc === 0;
}

function tun_destroy(string $iface): void
{
    if (empty($iface)) {
        return;
    }
    exec('/sbin/ifconfig ' . escapeshellarg($iface) . ' 2>/dev/null', $out, $rc);
    if ($rc !== 0) {
        return;
    }
    exec('/sbin/ifconfig ' . escapeshellarg($iface) . ' destroy 2>/dev/null');
}

/**
 * Перед стартом tun2socks: удалить stale PID и TUN, если процесс не запущен.
 * Иначе tun2socks падает с "interface already exists" (crash / leftover iface).
 * На stop destroy НЕ вызываем — TUN убирает сам tun2socks (как upstream).
 */
function t2s_prepare_start(string $iface, string $inst_uuid): void
{
    $pidPath = t2s_pid_path($inst_uuid);
    if (proc_is_running($pidPath)) {
        return;
    }
    @unlink($pidPath);
    if (tun_iface_exists($iface)) {
        echo "INFO: Removing stale TUN {$iface} before tun2socks start\n";
        tun_destroy($iface);
        usleep(300000);
    }
}

// ─── High-level per-instance actions ─────────────────────────────────────────

/**
 * do_stop() — останавливает tun2socks и xray-core инстанса, выставляет stopped flag.
 * TUN не destroy'им: tun2socks сам уничтожает интерфейс при SIGTERM (upstream 1.9.2).
 * Stale iface убирается только в t2s_prepare_start() при следующем старте.
 */
function do_stop(string $inst_uuid, ?string $tunIface = null): void
{
    if ($tunIface === null) {
        $c        = xray_get_config($inst_uuid);
        $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
    }

    // Останавливаем tun2socks первым — он держит TUN open и сам его destroy'ит.
    proc_kill(t2s_pid_path($inst_uuid));
    // Останавливаем xray-core
    proc_kill(xray_pid_path($inst_uuid));

    // Удаляем lo0 alias если был добавлен
    $c2 = xray_get_config($inst_uuid);
    lo0_alias_remove($c2['socks5_listen'] ?? '127.0.0.1');

    // БАГ-5 FIX: флаг намеренной остановки — watchdog не перезапускает
    file_put_contents(xray_stopped_flag($inst_uuid), date('Y-m-d H:i:s'));

    echo "Stopped.\n";
}

/**
 * do_start() — генерирует конфиги, запускает xray-core и tun2socks инстанса.
 */
function do_start(array $c): bool
{
    if (!file_exists(XRAY_BIN)) {
        echo "ERROR: xray-core not found at " . XRAY_BIN . "\n";
        return false;
    }
    if (!file_exists(T2S_BIN)) {
        echo "ERROR: tun2socks not found at " . T2S_BIN . "\n";
        return false;
    }

    $inst_uuid = $c['inst_uuid'];

    // B7: захватываем per-instance lock перед запуском
    $lock = lock_acquire($inst_uuid);
    if ($lock === false) {
        echo "INFO: Another start is already in progress for instance {$inst_uuid} (lock held). Skipping.\n";
        return true;
    }

    try {
        // БАГ-5 FIX: снимаем флаг намеренной остановки
        @unlink(xray_stopped_flag($inst_uuid));

        if (!xray_validate_ip_stack($c, $inst_uuid)) {
            return false;
        }

        if (!xray_write_config($c)) {
            return false;
        }
        t2s_write_config($c);

        lo0_alias_ensure($c['socks5_listen']);

        // BUG-3 FIX: валидация конфига до запуска
        if (!xray_validate_config(xray_conf_path($inst_uuid))) {
            return false;
        }

        $instLog = xray_instance_log($inst_uuid);
        if (!proc_is_running(xray_pid_path($inst_uuid))) {
            proc_start(XRAY_BIN, 'run -c ' . escapeshellarg(xray_conf_path($inst_uuid)), xray_pid_path($inst_uuid), $instLog);
            usleep(800000);
        }
        if (!proc_is_running(t2s_pid_path($inst_uuid))) {
            t2s_prepare_start($c['tun_iface'] ?? 'proxytun2socks0', $inst_uuid);
            proc_start(T2S_BIN, '-config ' . escapeshellarg(t2s_conf_path($inst_uuid)), t2s_pid_path($inst_uuid), $instLog);
            usleep(800000);
            if (!proc_is_running(t2s_pid_path($inst_uuid))) {
                echo "ERROR: tun2socks failed to start for instance {$inst_uuid}\n";
                return false;
            }
        }

        // Назначаем IP на TUN через syshook (ждёт TUN, читает IP из config, reload firewall)
        exec('/bin/sh /usr/local/etc/rc.syshook.d/start/50-xray ' . escapeshellarg($inst_uuid) . ' &');

        echo "Started.\n";
        return true;
    } finally {
        // B7: освобождаем lock гарантированно (даже при исключении)
        lock_release($lock, $inst_uuid);
    }
}

/**
 * do_delete() — останавливает instance, удаляет TUN и per-instance runtime-файлы.
 * Вызывается перед удалением записи из config.xml (delItem).
 */
function do_delete(string $inst_uuid): bool
{
    $c = xray_get_config($inst_uuid);
    if (empty($c)) {
        echo "ERROR: Instance {$inst_uuid} not found\n";
        return false;
    }

    $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
    $name     = $c['name'] ?? $inst_uuid;

    echo "Removing instance {$name} ({$inst_uuid})...\n";

    do_stop($inst_uuid, $tunIface);
    // Даём tun2socks время убрать TUN сам; если остался — destroy (instance уходит).
    usleep(500000);
    if (tun_iface_exists($tunIface)) {
        echo "INFO: Destroying TUN {$tunIface} after instance delete\n";
        tun_destroy($tunIface);
    }

    foreach ([
        xray_conf_path($inst_uuid),
        t2s_conf_path($inst_uuid),
        xray_pid_path($inst_uuid),
        t2s_pid_path($inst_uuid),
        xray_lock_path($inst_uuid),
        xray_stopped_flag($inst_uuid),
        xray_instance_log($inst_uuid),
    ] as $path) {
        if (file_exists($path)) {
            @unlink($path);
        }
    }

    echo "OK: instance resources removed\n";
    return true;
}

function do_status(string $inst_uuid = ''): void
{
    if ($inst_uuid !== '') {
        $xray = proc_is_running(xray_pid_path($inst_uuid));
        $t2s  = proc_is_running(t2s_pid_path($inst_uuid));
        echo json_encode([
            'status'      => ($xray && $t2s) ? 'ok' : 'stopped',
            'xray_core'   => $xray ? 'running' : 'stopped',
            'tun2socks'   => $t2s  ? 'running' : 'stopped',
            'inst_uuid'   => $inst_uuid,
        ]) . "\n";
        return;
    }

    // Без UUID: статус всех инстансов + агрегированный статус
    $all = xray_get_all_instances();
    if (empty($all)) {
        echo json_encode(['status' => 'stopped', 'xray_core' => 'stopped', 'tun2socks' => 'stopped']) . "\n";
        return;
    }
    // Для совместимости с текущим GUI: возвращаем статус первого инстанса
    $first = reset($all);
    $uuid0 = $first['inst_uuid'];
    $xray  = proc_is_running(xray_pid_path($uuid0));
    $t2s   = proc_is_running(t2s_pid_path($uuid0));
    echo json_encode([
        'status'    => ($xray && $t2s) ? 'ok' : 'stopped',
        'xray_core' => $xray ? 'running' : 'stopped',
        'tun2socks' => $t2s  ? 'running' : 'stopped',
    ]) . "\n";
}

function do_status_all(): void
{
    $all    = xray_get_all_instances();
    $result = [];
    foreach ($all as $inst_uuid => $c) {
        $xray = proc_is_running(xray_pid_path($inst_uuid));
        $t2s  = proc_is_running(t2s_pid_path($inst_uuid));
        $result[$inst_uuid] = [
            'name'      => $c['name'],
            'status'    => ($xray && $t2s) ? 'ok' : 'stopped',
            'xray_core' => $xray ? 'running' : 'stopped',
            'tun2socks' => $t2s  ? 'running' : 'stopped',
        ];
    }
    echo json_encode($result) . "\n";
}

// ─── Main ─────────────────────────────────────────────────────────────────────
$action    = $argv[1] ?? 'status';
$inst_uuid = isset($argv[2]) ? trim($argv[2]) : '';

// Базовая санитизация UUID аргумента
// configd передаёт литерал "%1" когда аргумент не указан — отбрасываем
if ($inst_uuid !== '') {
    $inst_uuid = preg_replace('/[^0-9a-fA-F\-]/', '', $inst_uuid);
    // UUID должен быть минимум 32 hex-символа + 4 дефиса = 36 символов
    if (strlen($inst_uuid) < 36) {
        $inst_uuid = '';
    }
}

switch ($action) {
    case 'start':
        if ($inst_uuid !== '') {
            $c = xray_get_config($inst_uuid);
            if (empty($c) || !$c['enabled']) {
                echo "Xray is disabled or instance not found.\n";
                exit(0);
            }
            $ok = do_start($c);
            exit($ok ? 0 : 1);
        }
        // Запускаем все включённые инстансы
        $all = xray_get_all_instances();
        if (empty($all)) {
            echo "No instances configured.\n";
            exit(0);
        }
        $anyFailed = false;
        foreach ($all as $uuid => $c) {
            if (!$c['enabled']) continue;
            if (!do_start($c)) {
                $anyFailed = true;
            }
        }
        exit($anyFailed ? 1 : 0);

    case 'stop':
        if ($inst_uuid !== '') {
            do_stop($inst_uuid);
        } else {
            foreach (array_keys(xray_get_all_instances()) as $uuid) {
                do_stop($uuid);
            }
        }
        break;

    case 'restart':
        if ($inst_uuid !== '') {
            $c        = xray_get_config($inst_uuid);
            $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
            do_stop($inst_uuid, $tunIface);
            sleep(1);
            if (!empty($c) && $c['enabled']) {
                do_start($c);
            }
        } else {
            $all = xray_get_all_instances();
            foreach ($all as $uuid => $c) {
                $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
                do_stop($uuid, $tunIface);
            }
            sleep(1);
            foreach ($all as $uuid => $c) {
                if ($c['enabled']) do_start($c);
            }
        }
        break;

    case 'reconfigure':
        // B10: возвращаем реальный статус
        if ($inst_uuid !== '') {
            $c        = xray_get_config($inst_uuid);
            $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
            do_stop($inst_uuid, $tunIface);
            sleep(1);
            if (!empty($c) && $c['enabled']) {
                $ok = do_start($c);
                if ($ok) {
                    echo "OK\n";
                    exit(0);
                } else {
                    echo "ERROR: Failed to start Xray services for instance {$inst_uuid}.\n";
                    exit(1);
                }
            } else {
                echo "Xray disabled — services stopped.\n";
                exit(0);
            }
        }
        // Без UUID: рекофигурируем все инстансы
        $all       = xray_get_all_instances();
        $allStopped = [];
        foreach ($all as $uuid => $c) {
            $tunIface = $c['tun_iface'] ?? 'proxytun2socks0';
            do_stop($uuid, $tunIface);
            $allStopped[$uuid] = $c;
        }
        sleep(1);
        $anyFailed = false;
        foreach ($allStopped as $uuid => $c) {
            if ($c['enabled']) {
                if (!do_start($c)) {
                    $anyFailed = true;
                }
            }
        }
        if ($anyFailed) {
            echo "ERROR: One or more instances failed to start.\n";
            exit(1);
        }
        echo "OK\n";
        exit(0);

    case 'status':
        do_status($inst_uuid);
        break;

    case 'statusall':
        do_status_all();
        break;

    case 'validate':
        // БАГ-6 FIX: сухой прогон через временный файл (рабочий конфиг не перезаписывается)
        $c = $inst_uuid !== '' ? xray_get_config($inst_uuid) : xray_get_config();
        if (empty($c)) {
            echo "ERROR: No xray config found in OPNsense config.xml\n";
            exit(1);
        }
        $tmpBase = tempnam('/tmp', 'xray-validate-');
        if ($tmpBase === false) {
            echo "ERROR: Cannot create temp file for validation\n";
            exit(1);
        }
        $tmpConf = $tmpBase . '.json';
        @unlink($tmpBase);
        try {
            if (!xray_validate_ip_stack($c, $inst_uuid)) {
                exit(1);
            }
            $config = xray_build_config_array($c);
            if ($config === null) {
                exit(1);
            }
            $json = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            $json = xray_normalize_transport($json);
            file_put_contents($tmpConf, $json);
            chmod($tmpConf, 0600);
            if (xray_validate_config($tmpConf)) {
                echo "OK: config is valid\n";
                exit(0);
            } else {
                exit(1);
            }
        } finally {
            @unlink($tmpConf);
        }

    case 'delete':
        if ($inst_uuid === '') {
            echo "ERROR: instance UUID required for delete\n";
            exit(1);
        }
        exit(do_delete($inst_uuid) ? 0 : 1);

    case 'version':
        $ver = file_exists(XRAY_VERSION_FILE) ? trim(file_get_contents(XRAY_VERSION_FILE)) : 'unknown';
        echo json_encode(['version' => $ver]) . "\n";
        break;

    default:
        echo "Unknown action: $action\n";
        exit(1);
}
