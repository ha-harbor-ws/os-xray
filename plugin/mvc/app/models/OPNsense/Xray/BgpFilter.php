<?php

namespace OPNsense\Xray;

use OPNsense\Base\BaseModel;
use OPNsense\Core\Config;

class BgpFilter extends BaseModel
{
    public static function builtinFilterRows(): array
    {
        return [
            [
                'enabled'        => '1',
                'name'           => 'filter_refilter',
                'community'      => '',
                'family'         => 'ipv4',
                'reject_default' => '1',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_download',
                'community'      => 'community_ANTIFILTER_DOWNLOAD',
                'family'         => 'ipv4',
                'reject_default' => '1',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_network_v4',
                'community'      => 'community_ANTIFILTER_NETWORK',
                'family'         => 'ipv4',
                'reject_default' => '1',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_network_v6',
                'community'      => 'community_ANTIFILTER_NETWORK',
                'family'         => 'ipv6',
                'reject_default' => '1',
                'tun_if'         => 'ACTIVE_TUN6_IF',
            ],
        ];
    }

    public function seedDefaultFiltersIfEmpty(): void
    {
        if (method_exists($this->filter, 'iterateItems')) {
            foreach ($this->filter->iterateItems() as $item) {
                return;
            }
        }
        if (!method_exists($this->filter, 'add')) {
            return;
        }
        foreach (self::builtinFilterRows() as $data) {
            $uuid = $this->filter->add();
            $node = $this->filter->{$uuid};
            if ($node !== null && method_exists($node, 'setNodes')) {
                $node->setNodes($data);
            }
        }
        $this->serializeToConfig();
        Config::getInstance()->save();
    }

    public function migrateAcceptFilterNames(): void
    {
        if (!method_exists($this->filter, 'iterateItems')) {
            return;
        }
        $changed = false;
        foreach ($this->filter->iterateItems() as $item) {
            $n = (string)$item->name;
            if (strncasecmp($n, 'accept_', 7) !== 0) {
                continue;
            }
            $item->name = 'filter_' . substr($n, 7);
            $changed = true;
        }
        foreach ($this->filter->iterateItems() as $item) {
            $c = trim((string)$item->community);
            if ($c === '' || strncasecmp($c, 'community_', 10) === 0) {
                continue;
            }
            $item->community = 'community_' . $c;
            $changed = true;
        }
        $byName = [];
        $uuids  = [];
        $comms = new BgpCommunity();
        if (method_exists($comms->community, 'iterateItems')) {
            foreach ($comms->community->iterateItems() as $uuid => $item) {
                $n = (string)$item->name;
                $byName[$n] = $uuid;
                $uuids[$uuid] = true;
            }
        }
        foreach ($this->filter->iterateItems() as $item) {
            $c = trim((string)$item->community);
            if ($c === '' || isset($uuids[$c])) {
                continue;
            }
            if (isset($byName[$c])) {
                $item->community = $byName[$c];
                $changed = true;
            }
        }
        if ($changed) {
            $this->serializeToConfig();
            Config::getInstance()->save();
        }
    }
}
