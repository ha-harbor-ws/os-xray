<?php

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class BgppeerController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Xray\BgpPeer';
    protected static $internalModelName  = 'peer';

    public function searchItemAction()
    {
        (new \OPNsense\Xray\BgpFilter())->seedDefaultFiltersIfEmpty();
        (new \OPNsense\Xray\BgpFilter())->migrateAcceptFilterNames();
        (new \OPNsense\Xray\BgpPeer())->seedDefaultPeersIfEmpty();
        (new \OPNsense\Xray\BgpPeer())->migrateAcceptImportNames();
        $response = $this->searchBase('peer', [
            'enabled',
            'name',
            'neighbor',
            'neighbor_as',
            'local_as',
            'ipv4',
            'ipv6',
        ]);
        $tun4 = '';
        $tun6 = '';
        $script = '/usr/local/opnsense/scripts/Xray/xray-bird-peers.php';
        if (is_readable($script)) {
            require_once $script;
            if (function_exists('xray_bird_active_tun_if')) {
                $tun4 = xray_bird_active_tun_if('ipv4');
                $tun6 = xray_bird_active_tun_if('ipv6');
            }
        }
        $byTun = $this->instanceNamesByTun();
        if (!empty($response['rows'])) {
            foreach ($response['rows'] as &$row) {
                $row['ipv4_route_int'] = $this->formatRouteInt($tun4, $byTun);
                $row['ipv6_route_int'] = $this->formatRouteInt($tun6, $byTun);
            }
            unset($row);
        }
        return $response;
    }

    private function instanceNamesByTun(): array
    {
        $map = [];
        $mdl = new \OPNsense\Xray\Instance();
        if (!method_exists($mdl->instance, 'iterateItems')) {
            return $map;
        }
        foreach ($mdl->instance->iterateItems() as $item) {
            $tun = trim((string)$item->tun_interface);
            if ($tun === '') {
                continue;
            }
            $name = trim((string)$item->name);
            $map[$tun][] = $name !== '' ? $name : $tun;
        }
        return $map;
    }

    private function formatRouteInt(string $tun, array $byTun): string
    {
        if ($tun === '') {
            return '';
        }
        $names = $byTun[$tun] ?? [];
        if ($names === []) {
            return $tun;
        }
        return $tun . ' (' . implode(', ', $names) . ')';
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        return $this->toggleBase('peer', $uuid, $enabled);
    }

    public function startItemAction($uuid)
    {
        return $this->setPeerEnabledAndReload($uuid, '1');
    }

    public function stopItemAction($uuid)
    {
        return $this->setPeerEnabledAndReload($uuid, '0');
    }

    public function statusAllAction()
    {
        $backend = new Backend();
        $result  = $backend->configdRun('xray bgpstatus');
        $decoded = json_decode($result, true);
        if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
            return $decoded;
        }
        return ['error' => trim((string)$result), 'running' => false, 'peers' => []];
    }

    public function applyAction()
    {
        return $this->birdCmd('bgpwrite');
    }

    public function getItemAction($uuid = null)
    {
        return $this->getBase('peer', 'peer', $uuid);
    }

    public function addItemAction()
    {
        $result = $this->addBase('peer', 'peer');
        $this->syncBirdFiles();
        return $result;
    }

    public function setItemAction($uuid)
    {
        $result = $this->setBase('peer', 'peer', $uuid);
        $this->syncBirdFiles();
        return $result;
    }

    public function delItemAction($uuid)
    {
        $result = $this->delBase('peer', $uuid);
        $this->syncBirdFiles();
        return $result;
    }

    private function syncBirdFiles(): void
    {
        (new Backend())->configdRun('xray bgpwrite');
    }

    private function setPeerEnabledAndReload($uuid, string $enabled): array
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed', 'message' => 'POST required'];
        }
        $result = $this->toggleBase('peer', $uuid, $enabled);
        if (($result['result'] ?? '') === 'failed') {
            return $result;
        }
        $bird = $this->birdCmd('bgprestart');
        if (($bird['result'] ?? '') === 'failed') {
            $result['result'] = 'failed';
            $result['message'] = $bird['message'] ?? 'Failed to rewrite includes and restart BIRD';
        }
        return $result;
    }

    private function birdCmd(string $action): array
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed', 'message' => 'POST required'];
        }
        $output = trim((new Backend())->configdRun('xray ' . $action));
        $failed = $output === ''
            || stripos($output, 'ERROR') !== false
            || stripos($output, 'failed') !== false;
        return [
            'result'  => $failed ? 'failed' : 'ok',
            'message' => $output !== '' ? $output : 'No response from configd',
        ];
    }
}
