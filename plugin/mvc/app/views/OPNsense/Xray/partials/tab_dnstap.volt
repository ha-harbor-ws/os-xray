<div id="dnstap" class="tab-pane fade">
    <style>
        #dnstap table.table {
            border: 1px solid #ddd;
            margin-bottom: 0;
            background-color: #f9f9f9;
        }
        #dnstap table.table > thead > tr > th,
        #dnstap table.table > tbody > tr > th,
        #dnstap table.table > tbody > tr > td {
            border: 1px solid #ddd;
            vertical-align: middle;
            background-color: #f9f9f9;
        }
        #dnstap table.table > thead > tr > th {
            background-color: #f5f5f5;
            font-weight: 600;
            color: #333;
        }
        #dnstap table.table-striped > tbody > tr:nth-of-type(even) > td,
        #dnstap table.table-striped > tbody > tr:nth-of-type(even) > th {
            background-color: #f3f3f3;
        }
        #dnstap table.table-hover > tbody > tr:hover > td,
        #dnstap table.table-hover > tbody > tr:hover > th {
            background-color: #ececec;
        }
        #dnstap td.dnstap-k {
            width: 22%;
            background-color: #f5f5f5;
            font-weight: 600;
            color: #333;
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
                <div style="width: 1px; height: 22px; background: #ddd;"></div>
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
                                    <small>{{ lang._('If a name is in both lists, blocked wins. Communities are applied on SIGHUP.') }}</small>
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
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_blocked_urls">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Blocked domain list URLs') }}
                                <span id="dnstapBlockedCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                                <div class="hidden" data-for="help_for_dnstap_blocked_urls">
                                    <small>{{ lang._('HTTP(S) links to blocked domain lists. Apply downloads them and writes a unique summarized file.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapBlockedUrlsKv" data-row-key="url" data-del-class="dnstap-blocked-url-del"></tbody>
                </table>
            </div>
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_dnstap_unblocked_urls">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Unblocked domain list URLs') }}
                                <span id="dnstapUnblockedCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                                <div class="hidden" data-for="help_for_dnstap_unblocked_urls">
                                    <small>{{ lang._('HTTP(S) links to unblocked domain lists. Names also present in blocked are dropped.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapUnblockedUrlsKv" data-row-key="url" data-del-class="dnstap-unblocked-url-del"></tbody>
                </table>
            </div>
        </section>
    </div>
</div>
