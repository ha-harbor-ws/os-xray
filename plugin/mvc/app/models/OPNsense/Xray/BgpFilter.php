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
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_download',
                'community'      => 'community_ANTIFILTER_DOWNLOAD',
                'family'         => 'ipv4',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_network_v4',
                'community'      => 'community_ANTIFILTER_NETWORK',
                'family'         => 'ipv4',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_antifilter_network_v6',
                'community'      => 'community_ANTIFILTER_NETWORK',
                'family'         => 'ipv6',
                'tun_if'         => 'ACTIVE_TUN6_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_dnstap_v4',
                'community'      => 'community_DNSTAP_BLOCKED',
                'family'         => 'ipv4',
                'tun_if'         => 'ACTIVE_TUN4_IF',
            ],
            [
                'enabled'        => '1',
                'name'           => 'filter_dnstap_v6',
                'community'      => 'community_DNSTAP_BLOCKED',
                'family'         => 'ipv6',
                'tun_if'         => 'ACTIVE_TUN6_IF',
            ],
        ];
    }

    public static function liveNames(): array
    {
        $out = [];
        $mdl = new self();
        if (!method_exists($mdl->filter, 'iterateItems')) {
            return $out;
        }
        foreach ($mdl->filter->iterateItems() as $uuid => $item) {
            $out[(string)$uuid] = (string)$item->name;
        }
        natcasesort($out);
        return $out;
    }

    public static function overlayDropdown($current): array
    {
        return BgpCommunity::overlayDropdownFromNames(self::liveNames(), $current);
    }

    public function filterUuidByName(string $name): string
    {
        $name = trim($name);
        if ($name === '' || !method_exists($this->filter, 'iterateItems')) {
            return '';
        }
        foreach ($this->filter->iterateItems() as $uuid => $item) {
            if (strcasecmp(trim((string)$item->name), $name) === 0) {
                return (string)$uuid;
            }
        }
        return '';
    }

    public function ensureDnstapFilters(): void
    {
        $commUuid = (new BgpCommunity())->ensureDnstapBlockedCommunity();
        $want = [
            'filter_dnstap_v4' => ['family' => 'ipv4', 'tun_if' => 'ACTIVE_TUN4_IF'],
            'filter_dnstap_v6' => ['family' => 'ipv6', 'tun_if' => 'ACTIVE_TUN6_IF'],
        ];
        $have = [];
        $changed = false;
        if (method_exists($this->filter, 'iterateItems')) {
            foreach ($this->filter->iterateItems() as $item) {
                $n = trim((string)$item->name);
                $have[$n] = true;
                if (!isset($want[$n])) {
                    continue;
                }
                if ((string)$item->enabled !== '1') {
                    $item->enabled = '1';
                    $changed = true;
                }
                if ($commUuid !== '' && (string)$item->community !== $commUuid) {
                    $item->community = $commUuid;
                    $changed = true;
                }
                if ((string)$item->family !== $want[$n]['family']) {
                    $item->family = $want[$n]['family'];
                    $changed = true;
                }
                if ((string)$item->tun_if !== $want[$n]['tun_if']) {
                    $item->tun_if = $want[$n]['tun_if'];
                    $changed = true;
                }
            }
        }
        foreach ($want as $name => $meta) {
            if (!empty($have[$name])) {
                continue;
            }
            if (!method_exists($this->filter, 'add')) {
                return;
            }
            $uuid = $this->filter->add();
            $node = $this->filter->{$uuid};
            if ($node !== null && method_exists($node, 'setNodes')) {
                $node->setNodes([
                    'enabled'   => '1',
                    'name'      => $name,
                    'community' => $commUuid !== '' ? $commUuid : 'community_DNSTAP_BLOCKED',
                    'family'    => $meta['family'],
                    'tun_if'    => $meta['tun_if'],
                ]);
                $changed = true;
            }
        }
        if ($changed) {
            $this->serializeToConfig();
            Config::getInstance()->save();
            if (method_exists(self::class, 'flushCacheData')) {
                self::flushCacheData();
            }
        }
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
            if ($c === '' || strcasecmp($c, 'none') === 0) {
                if ($c !== '') {
                    $item->community = '';
                    $changed = true;
                }
                continue;
            }
            if (isset($uuids[$c])) {
                continue;
            }
            if (preg_match('/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/', $c)) {
                continue;
            }
            if (strncasecmp($c, 'community_', 10) === 0) {
                $rest = substr($c, 10);
                if (isset($uuids[$rest])) {
                    $item->community = $rest;
                    $changed = true;
                    continue;
                }
                if (isset($byName[$c])) {
                    $item->community = $byName[$c];
                    $changed = true;
                    continue;
                }
                if (isset($byName[$rest])) {
                    $item->community = $byName[$rest];
                    $changed = true;
                }
                continue;
            }
            $prefixed = 'community_' . $c;
            if (isset($byName[$prefixed])) {
                $item->community = $byName[$prefixed];
                $changed = true;
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
