<script>
    $(document).ready(function () {
        // ── Helpers ───────────────────────────────────────────────
        function escAttr(s) {
            return String(s).replace(/[&"<>]/g, function (c) {
                return {'&':'&amp;','"':'&quot;','<':'&lt;','>':'&gt;'}[c];
            });
        }

        // ── Per-instance status overlay ───────────────────────────
        var instanceStatusCache = {};
        var instanceTestCache   = {};

        function statusBadge(info) {
            if (!info) return '<span class="label label-default" style="font-size:11px;">--</span>';
            var xOk = info.xray_core === 'running';
            var tOk = info.tun2socks === 'running';
            return '<span class="label ' + (xOk ? 'label-success' : 'label-danger') + '" style="font-size:11px;">' +
                'xray: ' + (xOk ? 'up' : 'down') +
                '</span> ' +
                '<span class="label ' + (tOk ? 'label-success' : 'label-danger') + '" style="font-size:11px;">' +
                'tun: ' + (tOk ? 'up' : 'down') +
                '</span>';
        }

        function applyStatusToGrid() {
            $('#grid-instances .xray-status-cell').each(function () {
                var uuid = $(this).data('uuid');
                $(this).html(statusBadge(instanceStatusCache[uuid]));
            });
        }

        function testResultBadge(info) {
            if (!info) return '<span style="font-size:11px;color:#999;">--</span>';
            var ok = info.result === 'ok';
            return '<span class="label ' + (ok ? 'label-success' : 'label-danger') + '" style="font-size:11px;">'
                + escAttr(info.message) + '</span>';
        }

        function applyTestResultToGrid() {
            $('#grid-instances .xray-test-cell').each(function () {
                var uuid = $(this).data('uuid');
                $(this).html(testResultBadge(instanceTestCache[uuid]));
            });
        }

        // ── Instances CRUD table (UIBootgrid) ───────────────────────
        $('#grid-instances').UIBootgrid({
            search: '/api/xray/instance/searchItem',
            get:    '/api/xray/instance/getItem/',
            set:    '/api/xray/instance/setItem/',
            add:    '/api/xray/instance/addItem',
            del:    '/api/xray/instance/delItem/',
            toggle: '/api/xray/instance/toggleItem/',
            options: {
                formatters: {
                    instanceStatus: function (column, row) {
                        // TODO: show "disabled" label instead of status badges when row.enabled === '0'
                        return '<span class="xray-status-cell" data-uuid="' + escAttr(row.uuid) + '">' +
                            statusBadge(instanceStatusCache[row.uuid]) + '</span>';
                    },
                    instanceTestResult: function (column, row) {
                        return '<span class="xray-test-cell" data-uuid="' + escAttr(row.uuid) + '">'
                            + testResultBadge(instanceTestCache[row.uuid]) + '</span>';
                    },
                    commands: function (column, row) {
                        // TODO: disable/hide cmd-inst-start and cmd-inst-stop when row.enabled === '0'
                        var uuid = escAttr(row.uuid);
                        return '<button type="button" class="btn btn-xs btn-success cmd-inst-start bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Start this instance") }}">'
                             +   '<span class="fa fa-play fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-danger cmd-inst-stop bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Stop this instance") }}">'
                             +   '<span class="fa fa-stop fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-default cmd-inst-test bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Test") }}">'
                             +   '<span class="fa fa-plug fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-default command-edit bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Edit") }}">'
                             +   '<span class="fa fa-pencil fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-default command-delete bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Delete") }}">'
                             +   '<span class="fa fa-trash-o fa-fw"></span></button>';
                    }
                }
            }
        });

        // After grid loads/reloads data, fetch and overlay status
        $('#grid-instances').on('loaded.rs.jquery.bootgrid', function () {
            refreshInstancesStatus();
            populateInstanceSelects();
        });

        // Per-instance start / stop / test (row button handlers)
        $(document).on('click', '#grid-instances .cmd-inst-start', function () {
            instanceServiceAction('start', $(this).data('row-id'));
        });
        $(document).on('click', '#grid-instances .cmd-inst-stop', function () {
            instanceServiceAction('stop', $(this).data('row-id'));
        });
        $(document).on('click', '#grid-instances .cmd-inst-test', function () {
            var uuid = $(this).data('row-id');
            var $btn = $(this).prop('disabled', true);
            $.ajax({
                url: '/api/xray/service/testconnect/' + encodeURIComponent(uuid),
                type: 'POST', dataType: 'json',
                success: function (data) {
                    instanceTestCache[uuid] = data;
                    applyTestResultToGrid();
                },
                complete: function () { $btn.prop('disabled', false); }
            });
        });

        function instanceServiceAction(action, uuid) {
            var url = '/api/xray/service/' + action + (uuid ? '/' + encodeURIComponent(uuid) : '');
            $.ajax({
                url: url, type: 'POST', dataType: 'json',
                success: function () { setTimeout(refreshInstancesStatus, 1500); }
            });
        }

        // ── BGP peers / filters / communities CRUD ──────────────────
        var peerStatusCache = {};
        var birdRunning = false;
        var peerConfigDirty = false;

        function peerStatusBadge(info) {
            if (!info) {
                return '<span class="label label-default" style="font-size:11px;">--</span>';
            }
            var state = String(info.state || '—');
            var ok = state === 'up' || String(info.info || '').toLowerCase() === 'established';
            var cls = state === 'disabled' ? 'label-default'
                    : (ok ? 'label-success' : 'label-danger');
            return '<span class="label ' + cls + '" style="font-size:11px;">' + escAttr(state) + '</span> '
                + '<span style="font-size:11px;">' + escAttr(info.info || '—') + '</span> '
                + '<span class="label label-info" style="font-size:11px;" title="{{ lang._("Imported prefixes") }}">'
                + escAttr(String(info.imported != null ? info.imported : 0)) + '</span>';
        }

        function applyPeerStatusToGrid() {
            $('#grid-bgppeers .xray-peer-status-cell').each(function () {
                var uuid = $(this).data('uuid');
                $(this).html(peerStatusBadge(peerStatusCache[uuid]));
            });
        }

        function updateBirdToolbar() {
            $('.xray-badge-bird')
                .removeClass('label-success label-danger label-default')
                .addClass(birdRunning ? 'label-success' : 'label-danger')
                .text('bird: ' + (birdRunning ? 'running' : 'stopped'));
            $('.xray-btn-bird-start').prop('disabled', birdRunning);
            $('.xray-btn-bird-stop').prop('disabled', !birdRunning);
            $('.xray-btn-bird-restart').prop('disabled', !birdRunning);
            $('.xray-btn-bird-testall').prop('disabled', !birdRunning);
            if (birdRunning && peerConfigDirty) {
                $('#bgpPeerApplyBox').show();
            } else {
                $('#bgpPeerApplyBox').hide();
            }
        }

        function markPeerConfigDirty() {
            peerConfigDirty = true;
            updateBirdToolbar();
        }

        function applyPeerStatusPayload(data) {
            if (!data || data.error) {
                return false;
            }
            birdRunning = !!data.running;
            peerStatusCache = birdRunning ? (data.peers || {}) : {};
            applyPeerStatusToGrid();
            updateBirdToolbar();
            return true;
        }

        function openRoutingPeersStatus() {
            ajaxGet("/api/xray/bgppeer/statusAll", {}, function (data) {
                if (!data || data.error) {
                    birdRunning = false;
                    peerStatusCache = {};
                    applyPeerStatusToGrid();
                    updateBirdToolbar();
                    return;
                }
                birdRunning = !!data.running;
                peerStatusCache = birdRunning ? (data.peers || {}) : {};
                applyPeerStatusToGrid();
                updateBirdToolbar();
            });
        }

        $('#grid-bgppeers').UIBootgrid({
            search: '/api/xray/bgppeer/searchItem',
            get:    '/api/xray/bgppeer/getItem/',
            set:    '/api/xray/bgppeer/setItem/',
            add:    '/api/xray/bgppeer/addItem',
            del:    '/api/xray/bgppeer/delItem/',
            toggle: '/api/xray/bgppeer/toggleItem/',
            options: {
                formatters: {
                    peerStatus: function (column, row) {
                        return '<span class="xray-peer-status-cell" data-uuid="' + escAttr(row.uuid) + '">'
                            + peerStatusBadge(peerStatusCache[row.uuid]) + '</span>';
                    },
                    commands: function (column, row) {
                        var uuid = escAttr(row.uuid);
                        return '<button type="button" class="btn btn-xs btn-success cmd-peer-start bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Start this peer") }}">'
                             +   '<span class="fa fa-play fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-danger cmd-peer-stop bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Stop this peer") }}">'
                             +   '<span class="fa fa-stop fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-default command-edit bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Edit") }}">'
                             +   '<span class="fa fa-pencil fa-fw"></span></button> '
                             + '<button type="button" class="btn btn-xs btn-default command-delete bootgrid-tooltip"'
                             +   ' data-row-id="' + uuid + '" title="{{ lang._("Delete") }}">'
                             +   '<span class="fa fa-trash-o fa-fw"></span></button>';
                    }
                }
            }
        });

        $('#grid-bgppeers').on('loaded.rs.jquery.bootgrid', function () {
            applyPeerStatusToGrid();
        });

        function peerServiceAction(action, uuid) {
            var $btns = $('#grid-bgppeers .cmd-peer-start, #grid-bgppeers .cmd-peer-stop').prop('disabled', true);
            $.ajax({
                url: '/api/xray/bgppeer/' + action + '/' + encodeURIComponent(uuid),
                type: 'POST',
                dataType: 'json',
                complete: function () {
                    $btns.prop('disabled', false);
                    $('#grid-bgppeers').bootgrid('reload');
                    markPeerConfigDirty();
                }
            });
        }

        $(document).on('click', '#grid-bgppeers .cmd-peer-start', function () {
            peerServiceAction('startItem', $(this).data('row-id'));
        });
        $(document).on('click', '#grid-bgppeers .cmd-peer-stop', function () {
            peerServiceAction('stopItem', $(this).data('row-id'));
        });
        $('#grid-bgpfilters').UIBootgrid({
            search: '/api/xray/bgpfilter/searchItem',
            get:    '/api/xray/bgpfilter/getItem/',
            set:    '/api/xray/bgpfilter/setItem/',
            add:    '/api/xray/bgpfilter/addItem',
            del:    '/api/xray/bgpfilter/delItem/',
            toggle: '/api/xray/bgpfilter/toggleItem/'
        });
        $('#grid-bgpcommunities').UIBootgrid({
            search: '/api/xray/bgpcommunity/searchItem',
            get:    '/api/xray/bgpcommunity/getItem/',
            set:    '/api/xray/bgpcommunity/setItem/',
            add:    '/api/xray/bgpcommunity/addItem',
            del:    '/api/xray/bgpcommunity/delItem/',
            toggle: '/api/xray/bgpcommunity/toggleItem/'
        });

        $('#DialogBgpPeer').on('shown.bs.modal', function () {
            $(this).find('.selectpicker').selectpicker('refresh');
        });

        function filterTunIfFromFamily($dlg) {
            var fam = $dlg.find('[id="filter.family"]').val();
            var tun = (fam === 'ipv6') ? 'ACTIVE_TUN6_IF' : 'ACTIVE_TUN4_IF';
            $dlg.find('[id="filter.tun_if"]').val(tun).prop('readonly', true);
        }

        $('#DialogBgpFilter').on('shown.bs.modal', function () {
            var $dlg = $(this);
            $dlg.find('.selectpicker').selectpicker('refresh');
            filterTunIfFromFamily($dlg);
        });
        $(document).on('changed.bs.select change', '#DialogBgpFilter [id="filter.family"]', function () {
            filterTunIfFromFamily($('#DialogBgpFilter'));
        });

        $(document).ajaxSuccess(function (e, xhr, settings) {
            var url = settings.url || '';
            if (/\/api\/xray\/bgppeer\/(addItem|setItem|delItem|toggleItem)\b/.test(url)) {
                markPeerConfigDirty();
            }
        });

        function birdServiceAction(action, $btn, onOk) {
            var origHtml = $btn.html();
            $btn.prop('disabled', true).html('<i class="fa fa-spinner fa-spin"></i>');
            $.ajax({
                url: '/api/xray/bgppeer/' + action,
                type: 'POST',
                dataType: 'json',
                success: function (data) {
                    $btn.html(origHtml);
                    if (data.result !== 'ok') {
                        alert('{{ lang._("Action failed:") }} ' + (data.message || 'unknown error'));
                    } else if (onOk) {
                        onOk();
                    }
                },
                error: function (xhr) {
                    $btn.html(origHtml);
                    alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                },
                complete: function () {
                    $btn.prop('disabled', false);
                    updateBirdToolbar();
                }
            });
        }

        $(document).on('click', '.xray-btn-bird-start', function () {
            birdServiceAction('startBird', $(this), function () {
                birdRunning = true;
                peerConfigDirty = false;
                updateBirdToolbar();
                openRoutingPeersStatus();
            });
        });
        $(document).on('click', '.xray-btn-bird-stop', function () {
            birdServiceAction('stopBird', $(this), function () {
                birdRunning = false;
                peerStatusCache = {};
                applyPeerStatusToGrid();
                updateBirdToolbar();
            });
        });
        $(document).on('click', '.xray-btn-bird-restart', function () {
            birdServiceAction('restartBird', $(this), function () {
                birdRunning = true;
                updateBirdToolbar();
                openRoutingPeersStatus();
            });
        });
        $(document).on('click', '.xray-btn-bird-testall', function () {
            if (!birdRunning) {
                $('.xray-bird-test-result').removeClass('text-success').addClass('text-danger')
                    .text("{{ lang._('BIRD is not running.') }}");
                return;
            }
            var $btn = $(this).prop('disabled', true);
            var $res = $('.xray-bird-test-result');
            $res.removeClass('text-success text-danger').text("{{ lang._('Testing...') }}");
            ajaxGet("/api/xray/bgppeer/statusAll", {}, function (data) {
                $btn.prop('disabled', false);
                updateBirdToolbar();
                if (!applyPeerStatusPayload(data) || !birdRunning) {
                    $res.removeClass('text-success').addClass('text-danger')
                        .text("{{ lang._('BIRD is not running.') }}");
                    return;
                }
                $res.removeClass('text-danger').addClass('text-success')
                    .text("{{ lang._('Peer status updated.') }}");
            });
        });
        $('#btnBgpApply').click(function () {
            birdServiceAction('apply', $(this), function () {
                peerConfigDirty = false;
                updateBirdToolbar();
                openRoutingPeersStatus();
            });
        });

        $('a[data-toggle="tab"][href^="#routing-"]').on('shown.bs.tab', function (e) {
            $(e.target).closest('li.dropdown').addClass('active');
            var href = $(e.target).attr('href');
            var $grid = $(href).find('table[id^="grid-"]');
            if ($grid.length) {
                $grid.bootgrid('reload');
            }
            if (href.indexOf('#routing-') === 0) {
                openRoutingPeersStatus();
            }
        });

        // ── General settings form ───────────────────────────────────
        mapDataToFormUI({'frm_general_settings': "/api/xray/general/get"}).done(function () {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        // ── Apply (save general, then reconfigure) ──────────────────
        $("#reconfigureAct").SimpleActionButton({
            onPreAction: function () {
                var dfObj = new $.Deferred();
                saveFormToEndpoint("/api/xray/general/set", 'frm_general_settings', function () {
                    dfObj.resolve();
                });
                return dfObj;
            }
        });

        // ── Status badges + per-instance status ───────────────────
        function refreshInstancesStatus() {
            ajaxGet("/api/xray/service/statusall", {}, function (data) {
                if (data.error) return;
                instanceStatusCache = data;

                // Aggregate: any instance running = global running
                var anyXray = false, anyTun = false;
                $.each(data, function (uuid, info) {
                    if (info.xray_core === 'running') anyXray = true;
                    if (info.tun2socks === 'running') anyTun = true;
                });
                var xok = anyXray, tok = anyTun;
                $('#badge_xray')
                    .removeClass('label-success label-danger label-default')
                    .addClass(xok ? 'label-success' : 'label-danger')
                    .text('xray-core: ' + (xok ? 'running' : 'stopped'));
                $('#badge_tun')
                    .removeClass('label-success label-danger label-default')
                    .addClass(tok ? 'label-success' : 'label-danger')
                    .text('tun2socks: ' + (tok ? 'running' : 'stopped'));

                // Update per-instance status in grid
                applyStatusToGrid();

                var running = xok || tok;
                $('#btnStartAll').prop('disabled', running);
                $('#btnStopAll').prop('disabled', !running);
                $('#btnRestartAll').prop('disabled', !running);
            });
        }
        refreshInstancesStatus();
        setInterval(refreshInstancesStatus, 5000);

        // ── Start / Stop / Restart ──────────────────────────────────
        function serviceAction(action, confirmMsg, callback) {
            if (confirmMsg && !confirm(confirmMsg)) {
                return;
            }
            // TODO: clean up — pass $btn as argument instead of deriving it from action string
            var $btns = $('#btnStartAll, #btnStopAll, #btnRestartAll').prop('disabled', true);
            var $btn = action === 'start'   ? $('#btnStartAll')
                     : action === 'stop'    ? $('#btnStopAll')
                     :                        $('#btnRestartAll');
            var origHtml = $btn.html();
            $btn.html('<i class="fa fa-spinner fa-spin"></i>');

            $.ajax({
                url:      '/api/xray/service/' + action,
                type:     'POST',
                dataType: 'json',
                success: function (data) {
                    $btn.html(origHtml);
                    if (data.result !== 'ok') {
                        alert('{{ lang._("Action failed:") }} ' + (data.message || 'unknown error'));
                    }
                    setTimeout(function () {
                        refreshInstancesStatus();
                        $btns.prop('disabled', false);
                        if (callback) callback();
                    }, 1500);
                },
                error: function (xhr) {
                    $btn.html(origHtml);
                    $btns.prop('disabled', false);
                    alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                }
            });
        }

        $('#btnStartAll').click(function () {
            serviceAction('start', null, null);
        });
        $('#btnStopAll').click(function () {
            var confirmStop = '{{ lang._("Stop Xray VPN? Active connections will be terminated.") }}';
            serviceAction('stop', confirmStop, null);
        });
        $('#btnRestartAll').click(function () {
            serviceAction('restart', null, null);
        });

        // ── Test Connection ─────────────────────────────────────────
        $('#btnTestConnect').click(function () {
            var $btn = $(this).prop('disabled', true);
            var $res = $('#testConnectResult');

            var uuids = [];
            $.each(instanceStatusCache, function (uuid, info) {
                // TODO: check on enabled status
                if (info.xray_core === 'running') { uuids.push(uuid); }
            });

            if (!uuids.length) {
                $res.removeClass('text-success').addClass('text-danger')
                    .text("{{ lang._('No running instances.') }}");
                $btn.prop('disabled', false);
                return;
            }

            $res.removeClass('text-success text-danger').text("{{ lang._('Testing...') }}");
            var pending = uuids.length;

            $.each(uuids, function (_, uuid) {
                $.ajax({
                    url: '/api/xray/service/testconnect/' + encodeURIComponent(uuid),
                    type: 'POST', dataType: 'json',
                    success: function (data) {
                        instanceTestCache[uuid] = data;
                        applyTestResultToGrid();
                    },
                    complete: function () {
                        pending--;
                        if (pending === 0) {
                            $btn.prop('disabled', false);
                            $res.removeClass('text-success text-danger').text('');
                        }
                    }
                });
            });
        });

        // ── Import VLESS (inside DialogInstance) ──────────────────
        function applyImportToDialog(data) {
            var $dlg = $('#DialogInstance');
            if (data.name) {
                $dlg.find('[id="instance.name"]').val(data.name);
            }
            $dlg.find('[id="instance.outbound_config"]').val(data.outbound_config || '');
        }

        // Inject Import panel + Validate button into DialogInstance on first open
        var dialogInjected = false;
        $('#DialogInstance').on('show.bs.modal', function () {
            if (dialogInjected) {
                // Reset state on each open
                $('#dlgImportLink').val('');
                $('#dlgImportResult').text('').removeClass('text-success text-danger');
                $('#dlgImportPanel').collapse('hide');
                $('#dlgValidateResult').text('').removeClass('text-success text-danger');
                return;
            }
            dialogInjected = true;

            // Import panel — collapsible, injected before the form table
            var importHtml =
                '<div style="margin: 0 0 10px;">' +
                    '<a data-toggle="collapse" href="#dlgImportPanel" class="btn btn-sm btn-default" style="margin-bottom: 6px;">' +
                        '<i class="fa fa-upload"></i> {{ lang._("Import VLESS link") }}' +
                    '</a>' +
                    '<div id="dlgImportPanel" class="collapse">' +
                        '<div class="well well-sm" style="margin-bottom: 0;">' +
                            '<div class="input-group">' +
                                '<input type="text" id="dlgImportLink" class="form-control input-sm"' +
                                '  style="font-family: monospace; font-size: 12px;"' +
                                '  placeholder="vless://UUID@host:443?security=reality&pbk=...#Name" />' +
                                '<span class="input-group-btn">' +
                                    '<button type="button" id="dlgImportParseBtn" class="btn btn-sm btn-primary">' +
                                        '<i class="fa fa-magic"></i> {{ lang._("Parse & Fill") }}' +
                                    '</button>' +
                                '</span>' +
                            '</div>' +
                            '<span id="dlgImportResult" style="font-size: 12px; display: inline-block; margin-top: 4px;"></span>' +
                        '</div>' +
                    '</div>' +
                '</div>';
            var $body = $(this).find('.modal-body');
            $body.prepend(importHtml);

            // Validate button — in footer, before Save
            var validateHtml =
                '<button type="button" id="dlgValidateBtn" class="btn btn-info pull-left">' +
                    '<i class="fa fa-check-circle"></i> {{ lang._("Validate Config") }}' +
                '</button>' +
                '<span id="dlgValidateResult" class="pull-left" style="font-size: 12px; line-height: 34px; margin-left: 8px;"></span>';
            var $footer = $(this).find('.modal-footer');
            $footer.prepend(validateHtml);
        });

        // Import parse handler (inside dialog)
        $(document).on('click', '#dlgImportParseBtn', function () {
            var link = $.trim($('#dlgImportLink').val());
            var $res = $('#dlgImportResult');
            if (!link) {
                $res.removeClass('text-success').addClass('text-danger')
                    .text("{{ lang._('Paste a VLESS link first.') }}");
                return;
            }

            var $btn = $(this).prop('disabled', true);
            $res.removeClass('text-success text-danger').text("{{ lang._('Parsing...') }}");
            var b64 = btoa(unescape(encodeURIComponent(link)));

            $.ajax({
                url:         '/api/xray/import/parse',
                type:        'POST',
                contentType: 'application/json; charset=utf-8',
                data:        JSON.stringify({link_b64: b64}),
                dataType:    'json',
                success: function (data) {
                    $btn.prop('disabled', false);
                    if (data.status !== 'ok') {
                        $res.removeClass('text-success').addClass('text-danger')
                            .text("{{ lang._('Parse error:') }} " + (data.message || 'unknown'));
                        return;
                    }
                    applyImportToDialog(data);
                    $res.removeClass('text-danger').addClass('text-success')
                        .text("{{ lang._('Imported! Fields filled from link.') }}");
                    // Collapse import panel after success
                    setTimeout(function () { $('#dlgImportPanel').collapse('hide'); }, 1500);
                },
                error: function (xhr) {
                    $btn.prop('disabled', false);
                    $res.removeClass('text-success').addClass('text-danger')
                        .text("{{ lang._('HTTP error:') }} " + xhr.status);
                }
            });
        });

        // Enter key in import field triggers parse
        $(document).on('keypress', '#dlgImportLink', function (e) {
            if (e.which === 13) {
                e.preventDefault();
                $('#dlgImportParseBtn').click();
            }
        });

        // ── Validate Config (inside DialogInstance footer) ────────
        $(document).on('click', '#dlgValidateBtn', function () {
            var $btn = $(this).prop('disabled', true);
            var $res = $('#dlgValidateResult');
            $res.removeClass('text-success text-danger').text("{{ lang._('Validating...') }}");

            $.ajax({
                url:      '/api/xray/service/validate',
                type:     'POST',
                dataType: 'json',
                success: function (data) {
                    $btn.prop('disabled', false);
                    if (data.result === 'ok') {
                        $res.removeClass('text-danger').addClass('text-success')
                            .text(data.message || "{{ lang._('Config is valid') }}");
                    } else {
                        $res.removeClass('text-success').addClass('text-danger')
                            .text(data.message || "{{ lang._('Validation failed') }}");
                    }
                },
                error: function (xhr) {
                    $btn.prop('disabled', false);
                    $res.addClass('text-danger').text("{{ lang._('HTTP error:') }} " + xhr.status);
                }
            });
        });

        // ── Diagnostics ─────────────────────────────────────────────
        function populateInstanceSelects() {
            $.ajax({
                url: '/api/xray/instance/searchItem',
                type: 'POST',
                dataType: 'json',
                data: {rowCount: -1, current: 1, searchPhrase: ''},
                success: function (data) {
                    var rows = (data && data.rows) ? data.rows : [];
                    var $diagSel = $('#diagInstanceSelect');
                    var $logSel = $('#logInstanceSelect');
                    var savedDiag = $diagSel.val();
                    var savedLog = $logSel.val();
                    $diagSel.empty();
                    $logSel.empty();
                    $.each(rows, function (_, row) {
                        $diagSel.append($('<option></option>').val(row.uuid).text(row.name || row.uuid));
                        $logSel.append($('<option></option>').val(row.uuid).text(row.name || row.uuid));
                    });
                    if (savedDiag && $diagSel.find('option[value="' + savedDiag + '"]').length) {
                        $diagSel.val(savedDiag);
                    }
                    if (savedLog && $logSel.find('option[value="' + savedLog + '"]').length) {
                        $logSel.val(savedLog);
                    }
                }
            });
        }

        function loadDiagnostics() {
            var uuid = $('#diagInstanceSelect').val();
            var url = '/api/xray/service/diagnostics' + (uuid ? '/' + encodeURIComponent(uuid) : '');
            $('#btnDiagRefresh').prop('disabled', true);
            $('#diagError').hide();
            ajaxGet(url, {}, function (data) {
                $('#btnDiagRefresh').prop('disabled', false);
                if (data.error) {
                    $('#diagError').text(data.error).show();
                    return;
                }
                var running = data.tun_status === 'running';
                var statusHtml = running
                    ? '<span class="label label-success">running</span>'
                    : '<span class="label label-danger">' + escAttr(data.tun_status || 'down') + '</span>';

                $('#diag_tun_iface').text(data.tun_interface  || '\u2014');
                $('#diag_tun_status').html(statusHtml);
                $('#diag_tun_ip').text(data.tun_ip           || '\u2014');
                $('#diag_tun_ip6').text(data.tun_ip6         || '\u2014');
                $('#diag_ip_stack').text(data.ip_stack       || '\u2014');
                $('#diag_dns_servers').text(data.dns_servers || '\u2014');
                $('#diag_mtu').text(data.mtu > 0 ? data.mtu + ' bytes' : '\u2014');
                $('#diag_bytes_in').text(data.bytes_in_hr    || '\u2014');
                $('#diag_bytes_out').text(data.bytes_out_hr  || '\u2014');
                $('#diag_pkts_in').text(data.pkts_in != null ? data.pkts_in.toLocaleString() : '\u2014');
                $('#diag_pkts_out').text(data.pkts_out != null ? data.pkts_out.toLocaleString() : '\u2014');
                $('#diag_xray_uptime').text(data.xray_uptime || '\u2014');
                $('#diag_t2s_uptime').text(data.tun2socks_uptime || '\u2014');
                $('#diag_ping_rtt').text(data.ping_rtt || 'N/A');
            });
        }

        var diagAutoRefresh = null;
        $('a[href="#diagnostics"]').on('shown.bs.tab', function () {
            loadDiagnostics();
            if (!diagAutoRefresh) {
                diagAutoRefresh = setInterval(function () {
                    if ($('#diagnostics').hasClass('active')) {
                        loadDiagnostics();
                    }
                }, 30000);
            }
        });
        $('#btnDiagRefresh').click(function () {
            loadDiagnostics();
        });
        $('#diagInstanceSelect').on('change', function () {
            loadDiagnostics();
        });
        $('#logInstanceSelect').on('change', function () {
            loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn');
        });

        // ── Logs ────────────────────────────────────────────────────
        function loadLog(apiEndpoint, preId, btnId) {
            var uuid = $('#logInstanceSelect').val();
            var apiEndpointWithUuid = apiEndpoint + (uuid ? '/' + encodeURIComponent(uuid) : '');
            $('#' + btnId).prop('disabled', true);
            $('#' + preId).text("{{ lang._('Loading...') }}");
            $.post(apiEndpointWithUuid, null, function (data) {
                var text = (data && data.log) || "{{ lang._('Log is empty.') }}";
                $('#' + preId).text(text);
                $('#' + btnId).prop('disabled', false);
                var pre = document.getElementById(preId);
                if (pre) { pre.scrollTop = pre.scrollHeight; }
            }, 'json').fail(function (xhr) {
                $('#' + preId).text("{{ lang._('Error loading log:') }} " + xhr.status);
                $('#' + btnId).prop('disabled', false);
            });
        }

        $('a[href="#logs"]').on('shown.bs.tab', function () {
            var $active = $('#logSubTabs .active a');
            var href = $active.attr('href');
            if (href === '#logBoot') {
                loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn');
            } else if (href === '#logCore') {
                loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn');
            }
        });

        $('#logSubTabs a').on('shown.bs.tab', function (e) {
            var href = $(e.target).attr('href');
            if (href === '#logBoot') {
                loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn');
            } else if (href === '#logCore') {
                loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn');
            }
        });

        $("#logBootRefreshBtn").click(function () {
            loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn');
        });
        $("#logCoreRefreshBtn").click(function () {
            loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn');
        });

        // ── Copy Debug Info ─────────────────────────────────────────
        $('#btnCopyDebug').click(function () {
            var $btn = $(this).prop('disabled', true);
            var $res = $('#copyDebugResult');
            $res.removeClass('text-success text-danger').text("{{ lang._('Collecting...') }}");

            var diagData = {}, bootLog = '', coreLog = '';
            var diagDone = $.Deferred(), bootDone = $.Deferred(), coreDone = $.Deferred();

            ajaxGet('/api/xray/service/diagnostics', {}, function (data) {
                diagData = data;
                diagDone.resolve();
            });
            $.post('/api/xray/service/log', null, function (data) {
                bootLog = (data && data.log) || '';
                bootDone.resolve();
            }, 'json').fail(function () { bootDone.resolve(); });
            $.post('/api/xray/service/xraylog', null, function (data) {
                coreLog = (data && data.log) || '';
                coreDone.resolve();
            }, 'json').fail(function () { coreDone.resolve(); });

            $.when(diagDone, bootDone, coreDone).done(function () {
                var info = "=== os-xray Debug Info ===\n"
                    + "Date: " + new Date().toISOString() + "\n\n"
                    + "--- Diagnostics ---\n"
                    + JSON.stringify(diagData, null, 2) + "\n\n"
                    + "--- Boot Log (last 150 lines) ---\n"
                    + bootLog + "\n\n"
                    + "--- Core Log (last 200 lines) ---\n"
                    + coreLog + "\n";

                $('#debugInfoContent').val(info);
                $('#debugInfoModal').modal('show');
                $('#debugInfoModal').one('shown.bs.modal', function () {
                    var ta = document.getElementById('debugInfoContent');
                    ta.focus();
                    ta.select();
                });
                $res.addClass('text-success').text("{{ lang._('Use Ctrl+C / Cmd+C to copy') }}");
                $btn.prop('disabled', false);
            });
        });

        // ── Tab hash ────────────────────────────────────────────────
        if (window.location.hash === '#routing') {
            window.location.hash = '#routing-peers';
        }
        if (window.location.hash !== "") {
            $('a[href="' + window.location.hash + '"]').click();
        }
        $('.nav-tabs a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            history.pushState(null, null, e.target.hash);
        });
    });
</script>
