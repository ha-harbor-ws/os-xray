<div id="routing" class="tab-pane fade in">
    <div class="row">
        <section class="col-xs-12">
            <table id="grid-bgppeers"
                   class="table table-condensed table-hover table-striped"
                   data-editDialog="DialogBgpPeer"
                   data-editAlert="BgpPeerChangeMessage">
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

            <div id="BgpPeerChangeMessage" class="alert alert-info" style="display: none;" role="alert">
                {{ lang._('Each peer is written to /usr/local/etc/bird as NAME.inc and listed in bgp.conf. Enable BGP on the General tab, then click Apply to start BIRD.') }}
            </div>
        </section>
    </div>
</div>
