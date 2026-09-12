<div id="dnstap" class="tab-pane fade">
    <div class="row">
        <section class="col-xs-12">
            <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                        display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
                <span class="xray-badge-dnstap label label-default">dnstap_bgp: ...</span>
                <span class="text-muted" style="font-size: 12px;">
                    {{ lang._('Apply writes all three files. If the service is running, it is restarted.') }}
                </span>
            </div>
        </section>
    </div>
    <div class="row">
        <section class="col-xs-12" style="padding: 15px;">
            <h4 style="margin-top: 0;">{{ lang._('Config') }}</h4>
            <p class="text-muted" id="dnstapConfPath" style="margin-top: 0;"></p>
            <textarea id="dnstapConfEditor" class="form-control" spellcheck="false"
                      style="min-height: 280px; font-family: monospace; font-size: 12px;"></textarea>

            <h4>{{ lang._('Domains') }}</h4>
            <p class="text-muted" id="dnstapDomainsPath" style="margin-top: 0;"></p>
            <textarea id="dnstapDomainsEditor" class="form-control" spellcheck="false"
                      style="min-height: 200px; font-family: monospace; font-size: 12px;"></textarea>

            <h4>{{ lang._('rc.conf') }}</h4>
            <p class="text-muted" id="dnstapRcPath" style="margin-top: 0;"></p>
            <textarea id="dnstapRcEditor" class="form-control" spellcheck="false"
                      style="min-height: 180px; font-family: monospace; font-size: 12px;"></textarea>
        </section>
    </div>
</div>
