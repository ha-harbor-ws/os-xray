<?php

namespace OPNsense\Xray;

/**
 * Renders the main GUI page.
 * Passes both forms to the volt template.
 * Route: /ui/xray/  (matches Menu.xml url)
 */
class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        try {
            (new BgpCommunity())->seedDefaultCommunitiesIfEmpty();
            (new BgpCommunity())->migrateCommunityFileNames();
            (new BgpCommunity())->ensureDnstapBlockedCommunity();
            (new BgpFilter())->seedDefaultFiltersIfEmpty();
            (new BgpFilter())->migrateAcceptFilterNames();
            (new BgpFilter())->ensureDnstapFilters();
            (new BgpPeer())->seedDefaultPeersIfEmpty();
            (new BgpPeer())->migrateAcceptImportNames();
            (new BgpPeer())->ensureDnstapPeerFilters();
        } catch (\Throwable $e) {
            syslog(LOG_ERR, 'os-xray BGP seed: ' . $e->getMessage());
        }
        $this->view->generalForm  = $this->getForm('general');
        $this->view->instanceForm = $this->getForm('instance');
        $this->view->bgppeerForm      = $this->getForm('bgppeer');
        $this->view->bgpfilterForm    = $this->getForm('bgpfilter');
        $this->view->bgpcommunityForm = $this->getForm('bgpcommunity');
        $this->view->pick('OPNsense/Xray/general');
    }
}
