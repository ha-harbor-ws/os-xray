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
        return $this->searchBase('peer', [
            'enabled',
            'name',
            'neighbor',
            'neighbor_as',
            'local_as',
            'ipv4',
            'ipv6',
        ]);
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        return $this->toggleBase('peer', $uuid, $enabled);
    }

    public function startItemAction($uuid)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed', 'message' => 'POST required'];
        }
        return $this->toggleBase('peer', $uuid, '1');
    }

    public function stopItemAction($uuid)
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed', 'message' => 'POST required'];
        }
        return $this->toggleBase('peer', $uuid, '0');
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
        return $this->birdCmd('bgprestart');
    }

    public function startBirdAction()
    {
        return $this->birdCmd('birdstart');
    }

    public function stopBirdAction()
    {
        return $this->birdCmd('birdstop');
    }

    public function getItemAction($uuid = null)
    {
        $result = $this->getBase('peer', 'peer', $uuid);
        if (($uuid === null || $uuid === '') && isset($result['peer']) && is_array($result['peer'])) {
            $defaults = $this->defaultsFromBgpConf();
            foreach ($defaults as $key => $value) {
                if ($key === 'ipv4_import' || $key === 'ipv6_import') {
                    continue;
                }
                if (!array_key_exists($key, $result['peer'])) {
                    continue;
                }
                $cur = $result['peer'][$key];
                if (is_array($cur) && array_key_exists('value', $cur)) {
                    $cur['value'] = $value;
                    if (isset($cur['selected'])) {
                        $cur['selected'] = $value;
                    }
                    $result['peer'][$key] = $cur;
                    continue;
                }
                if (is_array($cur)) {
                    continue;
                }
                $result['peer'][$key] = $value;
            }
        }
        return $result;
    }

    public function addItemAction()
    {
        return $this->addBase('peer', 'peer');
    }

    public function setItemAction($uuid)
    {
        return $this->setBase('peer', 'peer', $uuid);
    }

    public function delItemAction($uuid)
    {
        return $this->delBase('peer', $uuid);
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

    private function defaultsFromBgpConf(): array
    {
        $script = '/usr/local/opnsense/scripts/Xray/xray-bird-peers.php';
        if (!is_readable($script)) {
            return [];
        }
        require_once $script;
        if (!function_exists('xray_bgp_conf_default_peer')) {
            return [];
        }
        return xray_bgp_conf_default_peer();
    }
}
