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
            <p class="text-muted" style="font-size: 12px;">
                {{ lang._('If a name is in both lists, blocked wins. Communities are applied on SIGHUP.') }}
            </p>

            <h4>{{ lang._('Blocked domain list URLs') }}
                <small class="text-muted" id="dnstapBlockedUrlsPath"></small>
            </h4>
            <p class="text-muted" style="font-size: 12px; margin-top: -6px;">
                {{ lang._('HTTP(S) links to blocked domain lists. Apply downloads them and writes a unique summarized file.') }}
                <span id="dnstapBlockedCount"></span>
            </p>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('URL') }}</th>
                        <th>{{ lang._('Value') }}</th>
                        <th style="width: 6em;"></th>
                    </tr>
                </thead>
                <tbody id="dnstapBlockedUrlsKv"></tbody>
            </table>
            <button type="button" class="btn btn-xs btn-primary" id="dnstapBlockedUrlAdd">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add URL') }}
            </button>

            <h4 style="margin-top: 20px;">{{ lang._('Extra blocked domains') }}
                <small class="text-muted" id="dnstapBlockedPath"></small>
            </h4>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('Key') }}</th>
                        <th>{{ lang._('Value') }}</th>
                        <th style="width: 4em;"></th>
                    </tr>
                </thead>
                <tbody id="dnstapBlockedKv"></tbody>
            </table>
            <button type="button" class="btn btn-xs btn-primary" id="dnstapBlockedAdd">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add domain') }}
            </button>

            <h4 style="margin-top: 28px;">{{ lang._('Unblocked domain list URLs') }}
                <small class="text-muted" id="dnstapUnblockedUrlsPath"></small>
            </h4>
            <p class="text-muted" style="font-size: 12px; margin-top: -6px;">
                {{ lang._('HTTP(S) links to unblocked domain lists. Names also present in blocked are dropped.') }}
                <span id="dnstapUnblockedCount"></span>
            </p>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('URL') }}</th>
                        <th>{{ lang._('Value') }}</th>
                        <th style="width: 6em;"></th>
                    </tr>
                </thead>
                <tbody id="dnstapUnblockedUrlsKv"></tbody>
            </table>
            <button type="button" class="btn btn-xs btn-primary" id="dnstapUnblockedUrlAdd">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add URL') }}
            </button>

            <h4 style="margin-top: 20px;">{{ lang._('Extra unblocked domains') }}
                <small class="text-muted" id="dnstapUnblockedPath"></small>
            </h4>
            <table class="table table-condensed table-striped">
                <thead>
                    <tr>
                        <th style="width: 28%;">{{ lang._('Key') }}</th>
                        <th>{{ lang._('Value') }}</th>
                        <th style="width: 4em;"></th>
                    </tr>
                </thead>
                <tbody id="dnstapUnblockedKv"></tbody>
            </table>
            <button type="button" class="btn btn-xs btn-primary" id="dnstapUnblockedAdd">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add domain') }}
            </button>
        </section>
    </div>
</div>
