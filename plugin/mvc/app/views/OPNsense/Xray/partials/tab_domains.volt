<div id="domains" class="tab-pane fade">
    <style>
        #domains .dnstap-row-edit {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        #domains .dnstap-row-edit .form-control {
            flex: 1;
            min-width: 0;
            height: 28px;
            padding: 4px 8px;
            font-size: 13px;
        }
        #domains .dnstap-row-edit .btn {
            flex-shrink: 0;
        }
        #domains .xray-block {
            margin-bottom: 8px;
        }
    </style>

    <div class="row">
        <section class="col-xs-12">
            <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                        display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
                <a href="#" class="xray-showhelp" id="help_for_domains_check">
                    <i class="fa fa-info-circle"></i>
                </a>
                <span>{{ lang._('Check domain and IP route') }}</span>
                <div class="dnstap-row-edit" style="flex: 1; min-width: 220px; max-width: 480px;">
                    <input type="text" class="form-control" id="domainsCheckInput"
                           placeholder="{{ lang._('example.com or 1.1.1.1') }}"/>
                    <button type="button" class="btn btn-xs btn-primary" id="domainsCheckBtn"
                            title="{{ lang._('Check') }}">
                        <i class="fa fa-search fa-fw"></i> {{ lang._('Check') }}
                    </button>
                </div>
                {{ partial('OPNsense/Xray/partials/help_toggle') }}
                <div class="hidden" data-for="help_for_domains_check" style="flex-basis: 100%;">
                    <small class="text-muted">{{ lang._('Enter a domain or an IPv4/IPv6 address. Domains are resolved; for each IP birdcl show route for IP all is run. For a direct IP the Domain column stays empty. Active is the BIRD * route. If Network not found: peer N/A, instance N/A, interface WAN4/WAN6, Active yes.') }}</small>
                </div>
            </div>
        </section>
    </div>

    <div class="row">
        <section class="col-xs-12">
            <div class="xray-block">
                <table class="table table-condensed table-hover table-striped" id="domainsCheckTable" style="display: none;">
                    <thead>
                        <tr>
                            <th>{{ lang._('Domain') }}</th>
                            <th>{{ lang._('IP address') }}</th>
                            <th>{{ lang._('BGP peer') }}</th>
                            <th>{{ lang._('Instance') }}</th>
                            <th>{{ lang._('Interface') }}</th>
                            <th>{{ lang._('Active') }}</th>
                        </tr>
                    </thead>
                    <tbody id="domainsCheckRows"></tbody>
                </table>
                <p class="text-muted" id="domainsCheckMsg" style="margin: 8px 0 0; font-size: 12px; display: none;"></p>
            </div>

            <div class="xray-block">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_domains_proxy">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Extra PROXY domains') }}
                                <span id="domainsProxyCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>
                                <div class="dnstap-row-edit">
                                    <input type="text" class="form-control" id="domainsProxyInput"
                                           placeholder="{{ lang._('example.com') }}"/>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                    <tfoot>
                        <tr>
                            <td>
                                <button type="button" class="btn btn-xs btn-primary" id="domainsProxyAdd"
                                        title="{{ lang._('Add') }}">
                                    <span class="fa fa-fw fa-plus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsProxyRemove"
                                        title="{{ lang._('Remove') }}">
                                    <span class="fa fa-fw fa-minus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsProxySearch"
                                        title="{{ lang._('Show PROXY domains') }}">
                                    <span class="fa fa-fw fa-search"></span>
                                </button>
                            </td>
                        </tr>
                    </tfoot>
                </table>
                <div class="hidden" data-for="help_for_domains_proxy" style="padding: 8px 0 0;">
                    <small class="text-muted">{{ lang._('Add a domain to the extra PROXY list. Remove deletes the domain in the field. The magnifying glass shows all extra PROXY names.') }}</small>
                </div>
            </div>

            <div class="xray-block">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_domains_direct">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Extra DIRECT domains') }}
                                <span id="domainsDirectCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>
                                <div class="dnstap-row-edit">
                                    <input type="text" class="form-control" id="domainsDirectInput"
                                           placeholder="{{ lang._('example.com') }}"/>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                    <tfoot>
                        <tr>
                            <td>
                                <button type="button" class="btn btn-xs btn-primary" id="domainsDirectAdd"
                                        title="{{ lang._('Add') }}">
                                    <span class="fa fa-fw fa-plus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsDirectRemove"
                                        title="{{ lang._('Remove') }}">
                                    <span class="fa fa-fw fa-minus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsDirectSearch"
                                        title="{{ lang._('Show DIRECT domains') }}">
                                    <span class="fa fa-fw fa-search"></span>
                                </button>
                            </td>
                        </tr>
                    </tfoot>
                </table>
                <div class="hidden" data-for="help_for_domains_direct" style="padding: 8px 0 0;">
                    <small class="text-muted">{{ lang._('Add a domain to the extra DIRECT list. Names also present in BLOCK or PROXY are dropped on Apply.') }}</small>
                </div>
            </div>

            <div class="xray-block">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_domains_block">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Extra BLOCK domains') }}
                                <span id="domainsBlockCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>
                                <div class="dnstap-row-edit">
                                    <input type="text" class="form-control" id="domainsBlockInput"
                                           placeholder="{{ lang._('example.com') }}"/>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                    <tfoot>
                        <tr>
                            <td>
                                <button type="button" class="btn btn-xs btn-primary" id="domainsBlockAdd"
                                        title="{{ lang._('Add') }}">
                                    <span class="fa fa-fw fa-plus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsBlockRemove"
                                        title="{{ lang._('Remove') }}">
                                    <span class="fa fa-fw fa-minus"></span>
                                </button>
                                <button type="button" class="btn btn-xs btn-default" id="domainsBlockSearch"
                                        title="{{ lang._('Show BLOCK domains') }}">
                                    <span class="fa fa-fw fa-search"></span>
                                </button>
                            </td>
                        </tr>
                    </tfoot>
                </table>
                <div class="hidden" data-for="help_for_domains_block" style="padding: 8px 0 0;">
                    <small class="text-muted">{{ lang._('Add a domain to the extra BLOCK list. If a name is also in PROXY or DIRECT, BLOCK wins.') }}</small>
                </div>
            </div>
        </section>
    </div>
</div>

<div class="modal fade" id="domainsListModal" tabindex="-1" role="dialog">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal"><span>&times;</span></button>
                <h4 class="modal-title" id="domainsListModalTitle">{{ lang._('Extra PROXY domains') }}</h4>
            </div>
            <div class="modal-body">
                <input type="text" class="form-control input-sm" id="domainsListFilter"
                       placeholder="{{ lang._('Filter') }}" style="margin-bottom: 8px;"/>
                <div id="domainsListBody"
                     style="max-height: 55vh; overflow-y: auto;">
                    <table class="table table-condensed table-striped table-hover" style="margin-bottom: 0;">
                        <tbody id="domainsListRows"></tbody>
                    </table>
                </div>
                <p class="text-muted" style="margin: 8px 0 0; font-size: 12px;" id="domainsListCount"></p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Close') }}</button>
            </div>
        </div>
    </div>
</div>
