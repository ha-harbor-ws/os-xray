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
        $result = $this->toggleBase('peer', $uuid, $enabled);
        $this->syncBirdPeers();
        return $result;
    }

    public function getItemAction($uuid = null)
    {
        $result = $this->getBase('peer', 'peer', $uuid);
        if (($uuid === null || $uuid === '') && isset($result['peer']) && is_array($result['peer'])) {
            $defaults = $this->defaultsFromBgpConf();
            foreach ($defaults as $key => $value) {
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
        $result = $this->addBase('peer', 'peer');
        $this->syncBirdPeers();
        return $result;
    }

    public function setItemAction($uuid)
    {
        $result = $this->setBase('peer', 'peer', $uuid);
        $this->syncBirdPeers();
        return $result;
    }

    public function delItemAction($uuid)
    {
        $result = $this->delBase('peer', $uuid);
        $this->syncBirdPeers();
        return $result;
    }

    private function syncBirdPeers(): void
    {
        (new Backend())->configdRun('xray bgpwrite');
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
