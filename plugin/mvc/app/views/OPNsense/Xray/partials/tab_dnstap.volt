<div id="dnstap" class="tab-pane fade">
    <style>
        #dnstap table.table {
            border: 1px solid #ddd;
            margin-bottom: 0;
        }
        #dnstap table.table > thead > tr > th,
        #dnstap table.table > tbody > tr > th,
        #dnstap table.table > tbody > tr > td {
            border: 1px solid #ddd;
            vertical-align: middle;
        }
        #dnstap table.table > thead > tr > th {
            background: #f5f5f5;
            font-weight: 600;
            color: #333;
        }
        #dnstap td.dnstap-k {
            width: 22%;
            background: #f9f9f9;
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
        #dnstap tr.dnstap-help-col,
        #dnstap th.dnstap-help-col,
        #dnstap td.dnstap-help-col {
            display: none;
        }
        #dnstap.dnstap-help-on tr.dnstap-help-col {
            display: table-row;
        }
        #dnstap.dnstap-help-on th.dnstap-help-col,
        #dnstap.dnstap-help-on td.dnstap-help-col {
            display: table-cell;
        }
        #dnstap td.dnstap-help-col,
        #dnstap th.dnstap-help-text {
            font-weight: normal;
            color: #737373;
            font-size: 12px;
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
                <button type="button" class="btn btn-xs btn-default" id="dnstapHelpToggle"
                        title="{{ lang._('Show or hide field help') }}">
                    <i class="fa fa-question-circle fa-fw"></i> {{ lang._('Help') }}
                </button>
            </div>
        </section>
    </div>
    <div class="row">
        <section class="col-xs-12">
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>{{ lang._('Config') }}</th>
                            <th>{{ lang._('Value') }}</th>
                            <th class="dnstap-help-col">{{ lang._('Help') }}</th>
                        </tr>
                        <tr class="dnstap-help-col">
                            <th colspan="3" class="dnstap-help-text">
                                {{ lang._('If a name is in both lists, blocked wins. Communities are applied on SIGHUP.') }}
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
                                {{ lang._('Blocked domain list URLs') }}
                                <span id="dnstapBlockedCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                            </th>
                        </tr>
                        <tr class="dnstap-help-col">
                            <th class="dnstap-help-text">
                                {{ lang._('HTTP(S) links to blocked domain lists. Apply downloads them and writes a unique summarized file.') }}
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
                                {{ lang._('Unblocked domain list URLs') }}
                                <span id="dnstapUnblockedCount" class="label label-info" style="font-size:11px; margin-left:8px; display:none;"></span>
                            </th>
                        </tr>
                        <tr class="dnstap-help-col">
                            <th class="dnstap-help-text">
                                {{ lang._('HTTP(S) links to unblocked domain lists. Names also present in blocked are dropped.') }}
                            </th>
                        </tr>
                    </thead>
                    <tbody id="dnstapUnblockedUrlsKv" data-row-key="url" data-del-class="dnstap-unblocked-url-del"></tbody>
                </table>
            </div>
        </section>
    </div>
</div>
