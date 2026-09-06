<div class="row xray-bird-toolbar">
    <section class="col-xs-12">
        <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                    display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
            <div>
                <span class="xray-badge-bird label label-default">bird: ...</span>
            </div>
            <div style="width: 1px; height: 22px; background: #ddd;"></div>
            <div style="display: flex; gap: 4px;">
                <button type="button" class="btn btn-xs btn-success xray-btn-bird-start"
                        title="{{ lang._('Start BIRD') }}">
                    <i class="fa fa-play fa-fw"></i> {{ lang._('Start') }}
                </button>
                <button type="button" class="btn btn-xs btn-danger xray-btn-bird-stop"
                        title="{{ lang._('Stop BIRD') }}">
                    <i class="fa fa-stop fa-fw"></i> {{ lang._('Stop') }}
                </button>
                <button type="button" class="btn btn-xs btn-warning xray-btn-bird-restart"
                        title="{{ lang._('Restart BIRD') }}">
                    <i class="fa fa-refresh fa-fw"></i> {{ lang._('Restart') }}
                </button>
            </div>
            <div style="width: 1px; height: 22px; background: #ddd;"></div>
            <button type="button" class="btn btn-xs btn-default xray-btn-bird-testall"
                    title="{{ lang._('Refresh peer status via birdc show protocols all') }}">
                <i class="fa fa-plug fa-fw"></i> {{ lang._('Test All') }}
            </button>
            <span class="xray-bird-test-result" style="font-size: 12px;"></span>
        </div>
    </section>
</div>
