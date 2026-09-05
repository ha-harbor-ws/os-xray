<?php

namespace OPNsense\Xray;

use OPNsense\Base\BaseModel;
use OPNsense\Core\Config;

class BgpPeer extends BaseModel
{
    public static function builtinPeerRows(): array
    {
        $networkComm = '65444, 120, 65444:200, 65444:210, 65444:700, 65444:710, 65444:720, 65444:730, 65444:740, 65444:750, 65444:760, 65444:770, 65444:780, 65444:790, 65444:800';
        return [
            [
                'enabled'              => '0',
                'name'                 => 'refilter',
                'local_as'             => '65103',
                'neighbor'             => '165.22.127.207',
                'neighbor_as'          => '65412',
                'source_address'       => '',
                'ipv4'                 => '1',
                'ipv4_import'          => 'accept_refilter',
                'ipv4_community_name'  => '',
                'ipv4_community'       => '',
                'ipv6'                 => '0',
                'ipv6_import'          => '',
                'ipv6_community_name'  => '',
                'ipv6_community'       => '',
                'hold_time'            => '240',
            ],
            [
                'enabled'              => '0',
                'name'                 => 'antifilter_download',
                'local_as'             => '65103',
                'neighbor'             => '45.154.73.71',
                'neighbor_as'          => '65432',
                'source_address'       => '',
                'ipv4'                 => '1',
                'ipv4_import'          => 'accept_antifilter_download',
                'ipv4_community_name'  => 'ANTIFILTER_DOWNLOAD',
                'ipv4_community'       => '65432, 500',
                'ipv6'                 => '0',
                'ipv6_import'          => '',
                'ipv6_community_name'  => '',
                'ipv6_community'       => '',
                'hold_time'            => '240',
            ],
            [
                'enabled'              => '0',
                'name'                 => 'antifilter_network',
                'local_as'             => '65103',
                'neighbor'             => '45.148.244.55',
                'neighbor_as'          => '65444',
                'source_address'       => '',
                'ipv4'                 => '1',
                'ipv4_import'          => 'accept_antifilter_network_v4',
                'ipv4_community_name'  => 'ANTIFILTER_NETWORK',
                'ipv4_community'       => $networkComm,
                'ipv6'                 => '1',
                'ipv6_import'          => 'accept_antifilter_network_v6',
                'ipv6_community_name'  => 'ANTIFILTER_NETWORK',
                'ipv6_community'       => $networkComm,
                'hold_time'            => '240',
            ],
        ];
    }

    public function seedDefaultPeersIfEmpty(): void
    {
        if (method_exists($this->peer, 'iterateItems')) {
            foreach ($this->peer->iterateItems() as $item) {
                return;
            }
        }

        if (!method_exists($this->peer, 'add')) {
            return;
        }

        foreach (self::builtinPeerRows() as $data) {
            $script = '/usr/local/opnsense/scripts/Xray/xray-bird-peers.php';
            if (is_readable($script)) {
                require_once $script;
                if (function_exists('xray_source_for_peer')) {
                    $data['source_address'] = xray_source_for_peer($data);
                }
            }
            $uuid = $this->peer->add();
            $node = $this->peer->{$uuid};
            if ($node !== null && method_exists($node, 'setNodes')) {
                $node->setNodes($data);
            }
        }

        $this->serializeToConfig();
        Config::getInstance()->save();
    }
}
