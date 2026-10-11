<div id="dnstap" class="tab-pane fade">
    <style>
        #dnstap table.table {
            border: 1px solid;
            margin-bottom: 0;
            background-color: transparent;
        }
        #dnstap table.table > thead > tr > th,
        #dnstap table.table > tbody > tr > th,
        #dnstap table.table > tbody > tr > td {
            border: 1px solid;
            vertical-align: middle;
            background-color: inherit;
            color: inherit;
        }
        #dnstap table.table > thead > tr > th {
            font-weight: 600;
        }
        #dnstap td.dnstap-k {
            width: 22%;
            font-weight: 600;
            white-space: nowrap;
        }
        #dnstap .dnstap-row-edit {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        #dnstap .dnstap-row-edit .form-control {
            flex: 1;
            min-width: 0;
            height: 28px;
            padding: 4px 8px;
            font-size: 13px;
        }
        #dnstap #dnstapConfKv .form-control {
            height: 28px;
            padding: 4px 8px;
            font-size: 13px;
        }
        #dnstap .dnstap-row-edit .btn {
            flex-shrink: 0;
        }
        #dnstap .dnstap-section-wrap {
            margin-top: 16px;
        }
        #dnstap .dnstap-section-wrap:first-child {
            margin-top: 0;
        }
    </style>
    <div class="row xray-bird-toolbar">
        <section class="col-xs-12">
            <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                        display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
                <div>
                    <span class="xray-badge-dnstap label label-default">dnstap_bgp: ...</span>
                </div>
                <div style="width: 1px; height: 22px; background: #ddd;"></div>
                <button type="button" class="btn btn-xs btn-primary" id="dnstapStart">
                    <i class="fa fa-play fa-fw"></i> {{ lang._('Start') }}
                </button>
                <button type="button" class="btn btn-xs btn-default" id="dnstapStop">
                    <i class="fa fa-stop fa-fw"></i> {{ lang._('Stop') }}
                </button>
                {{ partial('OPNsense/Xray/partials/help_toggle') }}
            </div>
        </section>
    </div>
    <div class="row">
        <section class="col-xs-12">
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_config">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Config') }}
                            </th>
                            <th>
                                {{ lang._('Value') }}
                                <div class="hidden" data-for="help_for_dnstap_config">
                                    <small>{{ lang._('If a name is in both lists, PROXY wins. Communities are applied on SIGHUP.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapConfKv"></tbody>
                </table>
            </div>
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_proxy_urls">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('PROXY domain list URLs') }}
                                <span id="dnstapProxyCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                                <div class="hidden" data-for="help_for_dnstap_proxy_urls">
                                    <small>{{ lang._('HTTP(S) links to PROXY domain lists. Apply downloads them and writes a unique summarized file.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapProxyUrlsKv" data-row-key="url" data-del-class="dnstap-proxy-url-del"></tbody>
                </table>
            </div>
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_direct_urls">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('DIRECT domain list URLs') }}
                                <span id="dnstapDirectCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                                <div class="hidden" data-for="help_for_dnstap_direct_urls">
                                    <small>{{ lang._('HTTP(S) links to DIRECT domain lists. Names also present in PROXY are dropped.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapDirectUrlsKv" data-row-key="url" data-del-class="dnstap-direct-url-del"></tbody>
                </table>
            </div>
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_geodat_urls">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Geodat domain list URLs') }}
                                <button type="button" class="btn btn-xs btn-default" id="dnstapGeodatCategory" style="margin-left:8px;">
                                    {{ lang._('Category') }}
                                </button>
                                <div class="hidden" data-for="help_for_dnstap_geodat_urls">
                                    <small>{{ lang._('HTTP(S) links to geosite.dat. Category is unique per file: assign PROXY or DIRECT. Unassigned categories are ignored. Apply and daily fetch add only assigned domains.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapGeodatUrlsKv" data-row-key="url" data-del-class="dnstap-geodat-url-del"></tbody>
                </table>
            </div>
        </section>
    </div>
    <div class="modal fade" id="dnstapGeodatModal" tabindex="-1" role="dialog">
        <div class="modal-dialog" role="document">
            <div class="modal-content">
                <div class="modal-header">
                    <button type="button" class="close" data-dismiss="modal"><span>&times;</span></button>
                    <h4 class="modal-title">{{ lang._('Geodat categories') }}</h4>
                </div>
                <div class="modal-body">
                    <p class="text-muted" id="dnstapGeodatStatus" style="margin-bottom:8px;"></p>
                    <select class="form-control" id="dnstapGeodatUrlPick" style="margin-bottom:8px;"></select>
                    <input type="text" class="form-control" id="dnstapGeodatFilter"
                           placeholder="{{ lang._('Filter') }}" style="margin-bottom:8px;">
                    <div style="max-height:360px; overflow:auto;">
                        <table class="table table-condensed table-hover table-striped">
                            <thead>
                                <tr>
                                    <th>{{ lang._('Category') }}</th>
                                    <th style="width:90px;">{{ lang._('Domains') }}</th>
                                    <th style="width:140px;">{{ lang._('List') }}</th>
                                </tr>
                            </thead>
                            <tbody id="dnstapGeodatCats"></tbody>
                        </table>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Close') }}</button>
                    <button type="button" class="btn btn-primary" id="dnstapGeodatSave">{{ lang._('Save') }}</button>
                </div>
            </div>
        </div>
    </div>
</div>
