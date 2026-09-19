<div id="dnstap" class="tab-pane fade">
    <div class="row">
        <section class="col-xs-12">
            <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                        display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
                <span class="xray-badge-dnstap label label-default">dnstap_bgp: ...</span>
                <button type="button" class="btn btn-xs btn-primary" id="dnstapStart">
                    <i class="fa fa-play fa-fw"></i> {{ lang._('Start') }}
                </button>
                <button type="button" class="btn btn-xs btn-default" id="dnstapStop">
                    <i class="fa fa-stop fa-fw"></i> {{ lang._('Stop') }}
                </button>
                <span class="text-muted" style="font-size: 12px;">
                    {{ lang._('Values are loaded from the current files. Apply writes them back.') }}
                </span>
            </div>
        </section>
    </div>
    <div class="row">
        <section class="col-xs-12" style="padding: 15px;">
            <h4 style="margin-top: 0;">{{ lang._('Config') }}
                <small class="text-muted" id="dnstapConfPath"></small>
            </h4>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('Key') }}</th>
                        <th>{{ lang._('Value') }}</th>
                    </tr>
                </thead>
                <tbody id="dnstapConfKv"></tbody>
            </table>

            <h4>{{ lang._('Domains') }}
                <small class="text-muted" id="dnstapDomainsPath"></small>
            </h4>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('Key') }}</th>
                        <th>{{ lang._('Value') }}</th>
                        <th style="width: 4em;"></th>
                    </tr>
                </thead>
                <tbody id="dnstapDomainsKv"></tbody>
            </table>
            <button type="button" class="btn btn-xs btn-primary" id="dnstapDomainAdd">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add domain') }}
            </button>

            <h4 style="margin-top: 20px;">{{ lang._('rc.conf') }}
                <small class="text-muted" id="dnstapRcPath"></small>
            </h4>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('Key') }}</th>
                        <th>{{ lang._('Value') }}</th>
                    </tr>
                </thead>
                <tbody id="dnstapRcKv"></tbody>
            </table>
        </section>
    </div>
</div>
