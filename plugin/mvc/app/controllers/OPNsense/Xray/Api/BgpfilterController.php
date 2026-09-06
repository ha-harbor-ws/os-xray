<?php

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class BgpfilterController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\Xray\BgpFilter';
    protected static $internalModelName  = 'filter';

    public function searchItemAction()
    {
        (new \OPNsense\Xray\BgpCommunity())->seedDefaultCommunitiesIfEmpty();
        (new \OPNsense\Xray\BgpCommunity())->migrateCommunityFileNames();
        (new \OPNsense\Xray\BgpFilter())->seedDefaultFiltersIfEmpty();
        (new \OPNsense\Xray\BgpFilter())->migrateAcceptFilterNames();
        $response = $this->searchBase('filter', [
            'enabled',
            'name',
            'community',
            'family',
        ]);
        if (!empty($response['rows'])) {
            $names = [];
            $comms = new \OPNsense\Xray\BgpCommunity();
            if (method_exists($comms->community, 'iterateItems')) {
                foreach ($comms->community->iterateItems() as $uuid => $item) {
                    $names[$uuid] = (string)$item->name;
                }
            }
            foreach ($response['rows'] as &$row) {
                $c = (string)($row['community'] ?? '');
                if ($c !== '' && isset($names[$c])) {
                    $row['community'] = $names[$c];
                }
            }
            unset($row);
        }
        return $response;
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        $result = $this->toggleBase('filter', $uuid, $enabled);
        $this->syncBird();
        return $result;
    }

    public function getItemAction($uuid = null)
    {
        (new \OPNsense\Xray\BgpCommunity())->seedDefaultCommunitiesIfEmpty();
        (new \OPNsense\Xray\BgpFilter())->migrateAcceptFilterNames();
        return $this->getBase('filter', 'filter', $uuid);
    }

    public function addItemAction()
    {
        $result = $this->addBase('filter', 'filter');
        $this->syncBird();
        return $result;
    }

    public function setItemAction($uuid)
    {
        $result = $this->setBase('filter', 'filter', $uuid);
        $this->syncBird();
        return $result;
    }

    public function delItemAction($uuid)
    {
        $result = $this->delBase('filter', $uuid);
        $this->syncBird();
        return $result;
    }

    private function syncBird(): void
    {
        (new Backend())->configdRun('xray bgpwrite');
    }
}
