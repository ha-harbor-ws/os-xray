<div id="routing-peers" class="tab-pane fade in">
    {{ partial('OPNsense/Xray/partials/toolbar_bird') }}
    <div class="row">
        <section class="col-xs-12">
            <table id="grid-bgppeers"
                   class="table table-condensed table-hover table-striped"
                   data-editDialog="DialogBgpPeer">
                <thead>
                    <tr>
                        <th data-column-id="uuid"
                            data-type="string"
                            data-identifier="true"
                            data-visible="false">{{ lang._('ID') }}</th>
                        <th data-column-id="enabled"
                            data-width="6em"
                            data-type="string"
                            data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                        <th data-column-id="name"
                            data-type="string">{{ lang._('Name') }}</th>
                        <th data-column-id="neighbor"
                            data-type="string">{{ lang._('Neighbor') }}</th>
                        <th data-column-id="neighbor_as"
                            data-type="string"
                            data-width="8em">{{ lang._('Neighbor AS') }}</th>
                        <th data-column-id="local_as"
                            data-type="string"
                            data-width="7em">{{ lang._('Local AS') }}</th>
                        <th data-column-id="ipv4"
                            data-width="5em"
                            data-type="string">{{ lang._('IPv4') }}</th>
                        <th data-column-id="ipv6"
                            data-width="5em"
                            data-type="string">{{ lang._('IPv6') }}</th>
                        <th data-column-id="ipv4_route_int"
                            data-type="string"
                            data-width="14em">{{ lang._('IPv4 route int') }}</th>
                        <th data-column-id="ipv6_route_int"
                            data-type="string"
                            data-width="14em">{{ lang._('IPv6 route int') }}</th>
                        <th data-column-id="peer_status"
                            data-formatter="peerStatus"
                            data-sortable="false"
                            data-width="22em">{{ lang._('Status') }}</th>
                        <th data-column-id="commands"
                            data-formatter="commands"
                            data-sortable="false"
                            data-width="11em">{{ lang._('') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
                <tfoot>
                    <tr>
                        <td></td>
                        <td>
                            <button data-action="add" type="button" class="btn btn-xs btn-primary">
                                <span class="fa fa-fw fa-plus"></span>
                            </button>
                            <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default">
                                <span class="fa fa-fw fa-trash-o"></span>
                            </button>
                        </td>
                    </tr>
                </tfoot>
            </table>
            <div id="bgpPeerApplyBox" class="alert alert-warning" style="display: none; margin: 12px 15px;" role="alert">
                <p style="margin-bottom: 8px;">
                    {{ lang._('Peer configuration changed. Applying will restart BIRD and reset all BGP sessions.') }}
                </p>
                <button id="btnBgpApply" type="button" class="btn btn-primary">
                    <i class="fa fa-check fa-fw"></i> {{ lang._('Apply') }}
                </button>
            </div>
        </section>
    </div>
</div>

<div id="routing-filters" class="tab-pane fade">
    {{ partial('OPNsense/Xray/partials/toolbar_bird') }}
    <div class="row">
        <section class="col-xs-12">
            <table id="grid-bgpfilters"
                   class="table table-condensed table-hover table-striped"
                   data-editDialog="DialogBgpFilter"
                   data-editAlert="BgpFilterChangeMessage">
                <thead>
                    <tr>
                        <th data-column-id="uuid"
                            data-type="string"
                            data-identifier="true"
                            data-visible="false">{{ lang._('ID') }}</th>
                        <th data-column-id="enabled"
                            data-width="6em"
                            data-type="string"
                            data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                        <th data-column-id="name"
                            data-type="string">{{ lang._('Name') }}</th>
                        <th data-column-id="community"
                            data-type="string">{{ lang._('Community') }}</th>
                        <th data-column-id="family"
                            data-width="6em"
                            data-type="string">{{ lang._('Family') }}</th>
                        <th data-column-id="commands"
                            data-formatter="commands"
                            data-sortable="false"
                            data-width="7em">{{ lang._('') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
                <tfoot>
                    <tr>
                        <td></td>
                        <td>
                            <button data-action="add" type="button" class="btn btn-xs btn-primary">
                                <span class="fa fa-fw fa-plus"></span>
                            </button>
                            <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default">
                                <span class="fa fa-fw fa-trash-o"></span>
                            </button>
                        </td>
                    </tr>
                </tfoot>
            </table>
            <div id="BgpFilterChangeMessage" class="alert alert-info" style="display: none;" role="alert">
                {{ lang._('Each enabled filter is written to /usr/local/etc/bird/filter_NAME.inc and included from filters.inc. Use the filter name in a peer Import field.') }}
            </div>
        </section>
    </div>
</div>

<div id="routing-communities" class="tab-pane fade">
    {{ partial('OPNsense/Xray/partials/toolbar_bird') }}
    <div class="row">
        <section class="col-xs-12">
            <table id="grid-bgpcommunities"
                   class="table table-condensed table-hover table-striped"
                   data-editDialog="DialogBgpCommunity"
                   data-editAlert="BgpCommunityChangeMessage">
                <thead>
                    <tr>
                        <th data-column-id="uuid"
                            data-type="string"
                            data-identifier="true"
                            data-visible="false">{{ lang._('ID') }}</th>
                        <th data-column-id="enabled"
                            data-width="6em"
                            data-type="string"
                            data-formatter="rowtoggle">{{ lang._('Enabled') }}</th>
                        <th data-column-id="name"
                            data-type="string">{{ lang._('Name') }}</th>
                        <th data-column-id="communities"
                            data-type="string">{{ lang._('Communities') }}</th>
                        <th data-column-id="commands"
                            data-formatter="commands"
                            data-sortable="false"
                            data-width="7em">{{ lang._('') }}</th>
                    </tr>
                </thead>
                <tbody></tbody>
                <tfoot>
                    <tr>
                        <td></td>
                        <td>
                            <button data-action="add" type="button" class="btn btn-xs btn-primary">
                                <span class="fa fa-fw fa-plus"></span>
                            </button>
                            <button data-action="deleteSelected" type="button" class="btn btn-xs btn-default">
                                <span class="fa fa-fw fa-trash-o"></span>
                            </button>
                        </td>
                    </tr>
                </tfoot>
            </table>
            <div id="BgpCommunityChangeMessage" class="alert alert-info" style="display: none;" role="alert">
                {{ lang._('Each enabled community is written as /usr/local/etc/bird/NAME.inc (BIRD define NAME). The GUI name must match the file name without .inc.') }}
            </div>
        </section>
    </div>
</div>
