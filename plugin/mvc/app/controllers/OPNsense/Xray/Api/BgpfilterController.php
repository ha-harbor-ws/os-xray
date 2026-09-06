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
        (new \OPNsense\Xray\BgpFilter())->seedDefaultFiltersIfEmpty();
        (new \OPNsense\Xray\BgpFilter())->migrateAcceptFilterNames();
        return $this->searchBase('filter', [
            'enabled',
            'name',
            'community',
            'family',
            'reject_default',
        ]);
    }

    public function toggleItemAction($uuid, $enabled = null)
    {
        $result = $this->toggleBase('filter', $uuid, $enabled);
        $this->syncBird();
        return $result;
    }

    public function getItemAction($uuid = null)
    {
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
