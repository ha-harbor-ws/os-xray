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
        $this->view->generalForm  = $this->getForm('general');
        $this->view->instanceForm = $this->getForm('instance');
        $this->view->bgppeerForm      = $this->getForm('bgppeer');
        $this->view->bgpfilterForm    = $this->getForm('bgpfilter');
        $this->view->bgpcommunityForm = $this->getForm('bgpcommunity');
        (new BgpCommunity())->seedDefaultCommunitiesIfEmpty();
        (new BgpCommunity())->migrateCommunityFileNames();
        (new BgpFilter())->seedDefaultFiltersIfEmpty();
        (new BgpFilter())->migrateAcceptFilterNames();
        (new BgpPeer())->seedDefaultPeersIfEmpty();
        (new BgpPeer())->migrateAcceptImportNames();
        $this->view->pick('OPNsense/Xray/general');
    }
}
