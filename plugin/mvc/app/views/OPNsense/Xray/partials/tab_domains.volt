<div id="domains" class="tab-pane fade">
    <style>
        #domains table.table {
            border: 1px solid;
            margin-bottom: 0;
            background-color: transparent;
        }
        #domains table.table > thead > tr > th,
        #domains table.table > tbody > tr > th,
        #domains table.table > tbody > tr > td {
            border: 1px solid;
            vertical-align: middle;
            background-color: inherit;
            color: inherit;
        }
        #domains table.table > thead > tr > th {
            font-weight: 600;
        }
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
        #domains .dnstap-section-wrap {
            margin-top: 16px;
        }
        #domains .dnstap-section-wrap:first-child {
            margin-top: 0;
        }
    </style>
    <div class="row">
        <section class="col-xs-12">
            <div style="padding: 8px 15px; border-bottom: 1px solid #ddd;
                        display: flex; flex-wrap: wrap; align-items: center; gap: 8px;">
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
                                <a href="#" class="xray-showhelp" id="help_for_domains_blocked">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Extra blocked domains') }}
                                <div class="hidden" data-for="help_for_domains_blocked">
                                    <small>{{ lang._('Add a domain to the extra blocked list. Remove deletes the domain in the field. The magnifying glass shows all extra blocked names.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>
                                <div class="dnstap-row-edit">
                                    <input type="text" class="form-control" id="domainsBlockedInput"
                                           placeholder="{{ lang._('example.com') }}"/>
                                    <button type="button" class="btn btn-xs btn-primary" id="domainsBlockedAdd">
                                        <span class="fa fa-fw fa-plus"></span> {{ lang._('Add') }}
                                    </button>
                                    <button type="button" class="btn btn-xs btn-default" id="domainsBlockedRemove">
                                        <span class="fa fa-fw fa-minus"></span> {{ lang._('Remove') }}
                                    </button>
                                    <button type="button" class="btn btn-xs btn-default" id="domainsBlockedSearch"
                                            title="{{ lang._('Show blocked domains') }}">
                                        <span class="fa fa-fw fa-search"></span>
                                    </button>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
            <div class="dnstap-section-wrap">
                <table class="table table-condensed table-hover table-striped">
                    <thead>
                        <tr>
                            <th>
                                <a href="#" class="xray-showhelp" id="help_for_domains_unblocked">
                                    <i class="fa fa-info-circle"></i>
                                </a>
                                {{ lang._('Extra unblocked domains') }}
                                <div class="hidden" data-for="help_for_domains_unblocked">
                                    <small>{{ lang._('Add a domain to the extra unblocked list. Names also present in blocked are dropped on Apply.') }}</small>
                                </div>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>
                                <div class="dnstap-row-edit">
                                    <input type="text" class="form-control" id="domainsUnblockedInput"
                                           placeholder="{{ lang._('example.com') }}"/>
                                    <button type="button" class="btn btn-xs btn-primary" id="domainsUnblockedAdd">
                                        <span class="fa fa-fw fa-plus"></span> {{ lang._('Add') }}
                                    </button>
                                    <button type="button" class="btn btn-xs btn-default" id="domainsUnblockedRemove">
                                        <span class="fa fa-fw fa-minus"></span> {{ lang._('Remove') }}
                                    </button>
                                    <button type="button" class="btn btn-xs btn-default" id="domainsUnblockedSearch"
                                            title="{{ lang._('Show unblocked domains') }}">
                                        <span class="fa fa-fw fa-search"></span>
                                    </button>
                                </div>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>

<div class="modal fade" id="domainsListModal" tabindex="-1" role="dialog">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal"><span>&times;</span></button>
                <h4 class="modal-title" id="domainsListModalTitle">{{ lang._('Domains') }}</h4>
            </div>
            <div class="modal-body">
                <input type="text" class="form-control input-sm" id="domainsListFilter"
                       placeholder="{{ lang._('Filter') }}" style="margin-bottom: 8px;"/>
                <div id="domainsListBody"
                     style="max-height: 55vh; overflow-y: auto; border: 1px solid #ddd;">
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
