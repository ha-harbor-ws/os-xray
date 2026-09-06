{{ partial('OPNsense/Xray/partials/scripts') }}

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li class="active"><a data-toggle="tab" href="#instances">{{ lang._('Instances') }}</a></li>
    <li class="dropdown">
        <a href="#" class="dropdown-toggle" data-toggle="dropdown" role="button" aria-haspopup="true" aria-expanded="false">
            {{ lang._('Routing') }} <span class="caret"></span>
        </a>
        <ul class="dropdown-menu">
            <li><a data-toggle="tab" href="#routing-peers">{{ lang._('BGP peers') }}</a></li>
            <li><a data-toggle="tab" href="#routing-filters">{{ lang._('BGP filter') }}</a></li>
            <li><a data-toggle="tab" href="#routing-communities">{{ lang._('BGP community') }}</a></li>
        </ul>
    </li>
    <li><a data-toggle="tab" href="#general">{{ lang._('General') }}</a></li>
    <li><a data-toggle="tab" href="#logs">{{ lang._('Log') }}</a></li>
</ul>

<div class="tab-content content-box">
    {{ partial('OPNsense/Xray/partials/tab_instances') }}
    {{ partial('OPNsense/Xray/partials/tab_routing') }}

    <div id="general" class="tab-pane fade in">
        {{ partial("layout_partials/base_form", {'fields': generalForm, 'id': 'frm_general_settings'}) }}
    </div>

    {{ partial('OPNsense/Xray/partials/tab_diagnostics') }}
    {{ partial('OPNsense/Xray/partials/tab_logs') }}
</div>

{{ partial('layout_partials/base_apply_button', {'data_endpoint': '/api/xray/service/reconfigure'}) }}

{{ partial("layout_partials/base_dialog", ['fields': instanceForm, 'id': 'DialogInstance', 'label': lang._('Edit Instance')]) }}
{{ partial("layout_partials/base_dialog", ['fields': bgppeerForm, 'id': 'DialogBgpPeer', 'label': lang._('Edit BGP Peer')]) }}
{{ partial("layout_partials/base_dialog", ['fields': bgpfilterForm, 'id': 'DialogBgpFilter', 'label': lang._('Edit BGP Filter')]) }}
{{ partial("layout_partials/base_dialog", ['fields': bgpcommunityForm, 'id': 'DialogBgpCommunity', 'label': lang._('Edit BGP Community')]) }}

{{ partial('OPNsense/Xray/partials/modal_debug') }}
