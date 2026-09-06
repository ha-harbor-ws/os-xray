<?php

namespace OPNsense\Xray;

use OPNsense\Base\BaseModel;
use OPNsense\Core\Config;

class BgpCommunity extends BaseModel
{
    public static function builtinCommunityRows(): array
    {
        $networkComm = '65444:120, 65444:200, 65444:210, 65444:700, 65444:710, 65444:720, 65444:730, 65444:740, 65444:750, 65444:760, 65444:770, 65444:780, 65444:790, 65444:800';
        return [
            [
                'enabled'      => '1',
                'name'         => 'community_ANTIFILTER_DOWNLOAD',
                'communities'  => '65432:500',
            ],
            [
                'enabled'      => '1',
                'name'         => 'community_ANTIFILTER_NETWORK',
                'communities'  => $networkComm,
            ],
        ];
    }

    public function seedDefaultCommunitiesIfEmpty(): void
    {
        if (method_exists($this->community, 'iterateItems')) {
            foreach ($this->community->iterateItems() as $item) {
                return;
            }
        }
        if (!method_exists($this->community, 'add')) {
            return;
        }
        foreach (self::builtinCommunityRows() as $data) {
            $uuid = $this->community->add();
            $node = $this->community->{$uuid};
            if ($node !== null && method_exists($node, 'setNodes')) {
                $node->setNodes($data);
            }
        }
        $this->serializeToConfig();
        Config::getInstance()->save();
    }

    public function migrateCommunityFileNames(): void
    {
        if (!method_exists($this->community, 'iterateItems')) {
            return;
        }
        $changed = false;
        foreach ($this->community->iterateItems() as $item) {
            $n = trim((string)$item->name);
            if ($n === '' || strncasecmp($n, 'community_', 10) === 0) {
                continue;
            }
            $item->name = 'community_' . $n;
            $changed = true;
        }
        $script = '/usr/local/opnsense/scripts/Xray/xray-bird-peers.php';
        if (is_readable($script)) {
            require_once $script;
        }
        if (function_exists('xray_bgp_parse_communities') && function_exists('xray_bgp_format_communities_gui')) {
            foreach ($this->community->iterateItems() as $item) {
                $raw = trim((string)$item->communities);
                if ($raw === '') {
                    continue;
                }
                if (preg_match('/^\d+:\d+(\s*,\s*\d+:\d+)*$/', $raw)) {
                    continue;
                }
                $pairs = xray_bgp_parse_communities($raw);
                if ($pairs === []) {
                    continue;
                }
                $item->communities = xray_bgp_format_communities_gui($pairs);
                $changed = true;
            }
        }
        if ($changed) {
            $this->serializeToConfig();
            Config::getInstance()->save();
        }
    }
}
