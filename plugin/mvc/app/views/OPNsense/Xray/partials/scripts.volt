<script>
    $(document).ready(function () {
        // ── Helpers ───────────────────────────────────────────────
        function escAttr(s) {
            return String(s).replace(/[&"<>]/g, function (c) {
                return {'&':'&amp;','"':'&quot;','<':'&lt;','>':'&gt;'}[c];
            });
        }

        function xrayHelpIsOn() {
            return !!(window.sessionStorage && sessionStorage.getItem('all_help_preset') === '1');
        }

        function xrayHelpClasses() {
            return xrayHelpIsOn() ? 'show' : 'hidden';
        }

        function xraySyncHelp() {
            var on = xrayHelpIsOn();
            $('[data-for*="help_for"]').toggleClass('show', on).toggleClass('hidden', !on);
            $('.xray-full-help-toggle')
                .toggleClass('fa-toggle-on', on).toggleClass('fa-toggle-off', !on)
                .toggleClass('text-success', on).toggleClass('text-danger', !on);
            $('[id*="show_all_help"]')
                .toggleClass('fa-toggle-on', on).toggleClass('fa-toggle-off', !on)
                .toggleClass('text-success', on).toggleClass('text-danger', !on);
        }

        $(document).on('click', '.xray-full-help', function (e) {
            e.preventDefault();
            if (window.sessionStorage) {
                sessionStorage.setItem('all_help_preset', xrayHelpIsOn() ? '0' : '1');
            }
            xraySyncHelp();
        });
        $(document).on('click', 'a.xray-showhelp', function (e) {
            e.preventDefault();
            $("*[data-for='" + $(this).attr('id') + "']").toggleClass('hidden show');
        });
        $(document).on('click', '[id*="show_all_help"]', function () {
            setTimeout(xraySyncHelp, 0);
        });
        setTimeout(xraySyncHelp, 0);

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

        function fmtLatencySec(t) {
            var n = Number(t);
            if (!isFinite(n) || n < 0) {
                n = 0;
            }
            return n.toFixed(3) + 's';
        }

        /**
         * Active TUN latency cell (like Status labels):
         *  green  — this instance is the active TUN (show RTT)
         *  red    — no probe response (show 0)
         *  yellow — has RTT but not active: time less than active TUN, or otherwise not selected
         */
        function activeTunBadge(lat) {
            if (!lat) {
                return '<span class="label label-default" style="font-size:11px;">--</span>';
            }
            if (!lat.ok) {
                return '<span class="label label-danger" style="font-size:11px;">0</span>';
            }
            var time = Number(lat.time);
            if (!isFinite(time) || time < 0) {
                time = 0;
            }
            var text = fmtLatencySec(time);
            if (lat.active) {
                return '<span class="label label-success" style="font-size:11px;">' + escAttr(text) + '</span>';
            }
            // Not active: yellow when RTT is lower than active's (weight) or any non-winner with a reply
            return '<span class="label label-warning" style="font-size:11px;">' + escAttr(text) + '</span>';
        }

        function applyStatusToGrid() {
            $('#grid-instances .xray-status-cell').each(function () {
                var uuid = $(this).data('uuid');
                $(this).html(statusBadge(instanceStatusCache[uuid]));
            });
            $('#grid-instances .xray-activetun-v4-cell').each(function () {
                var uuid = $(this).data('uuid');
                var info = instanceStatusCache[uuid];
                $(this).html(activeTunBadge(info && info.active_tun_v4));
            });
            $('#grid-instances .xray-activetun-v6-cell').each(function () {
                var uuid = $(this).data('uuid');
                var info = instanceStatusCache[uuid];
                $(this).html(activeTunBadge(info && info.active_tun_v6));
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
                    instanceActiveTunV4: function (column, row) {
                        var info = instanceStatusCache[row.uuid];
                        return '<span class="xray-activetun-v4-cell" data-uuid="' + escAttr(row.uuid) + '">'
                            + activeTunBadge(info && info.active_tun_v4) + '</span>';
                    },
                    instanceActiveTunV6: function (column, row) {
                        var info = instanceStatusCache[row.uuid];
                        return '<span class="xray-activetun-v6-cell" data-uuid="' + escAttr(row.uuid) + '">'
                            + activeTunBadge(info && info.active_tun_v6) + '</span>';
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

        function peerStatusBadge(info) {
            if (!info) {
                return '<span class="label label-default" style="font-size:11px;">--</span>';
            }
            var state = String(info.state || '—');
            var ok = state === 'up' || String(info.info || '').toLowerCase() === 'established';
            var cls = state === 'disabled' ? 'label-default'
                    : (ok ? 'label-success' : 'label-danger');
            return '<span class="label ' + cls + '" style="font-size:11px;">' + escAttr(state) + '</span> '
                + '<span style="font-size:11px;">' + escAttr(info.info || '—') + '</span>';
        }

        function peerFamilyEnabled(row, family) {
            if (!row) {
                return true;
            }
            var v = row[family];
            return !(v === '0' || v === 0 || v === false);
        }

        function peerPrefixBadge(info, family, familyOn) {
            var n = 0;
            if (info) {
                n = family === 'ipv6' ? info.imported6 : info.imported4;
                if (n == null) {
                    n = 0;
                }
            }
            var liveOn = !!(info && (family === 'ipv6' ? info.ipv6 : info.ipv4));
            if (!familyOn && !liveOn && !(Number(n) > 0)) {
                return '<span style="font-size:11px;color:#999;">—</span>';
            }
            if (!info) {
                return '<span class="label label-default" style="font-size:11px;">--</span>';
            }
            return '<span class="label label-info" style="font-size:11px;" title="{{ lang._("Imported prefixes") }}">'
                + escAttr(String(n)) + '</span>';
        }

        function applyPeerStatusToGrid() {
            $('#grid-bgppeers .xray-peer-status-cell').each(function () {
                var uuid = $(this).attr('data-uuid');
                $(this).html(peerStatusBadge(peerStatusCache[uuid]));
            });
            $('#grid-bgppeers .xray-peer-v4-cell').each(function () {
                var uuid = $(this).attr('data-uuid');
                var on = String($(this).attr('data-family-on')) !== '0';
                $(this).html(peerPrefixBadge(peerStatusCache[uuid], 'ipv4', on));
            });
            $('#grid-bgppeers .xray-peer-v6-cell').each(function () {
                var uuid = $(this).attr('data-uuid');
                var on = String($(this).attr('data-family-on')) !== '0';
                $(this).html(peerPrefixBadge(peerStatusCache[uuid], 'ipv6', on));
            });
        }

        function updateBirdToolbar() {
            $('.xray-badge-bird')
                .removeClass('label-success label-danger label-default')
                .addClass(birdRunning ? 'label-success' : 'label-danger')
                .text('bird: ' + (birdRunning ? 'running' : 'stopped'));
            $('.xray-btn-bird-testall').prop('disabled', !birdRunning);
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
                    peerPrefixes4: function (column, row) {
                        var on = peerFamilyEnabled(row, 'ipv4');
                        return '<span class="xray-peer-v4-cell" data-uuid="' + escAttr(row.uuid)
                            + '" data-family-on="' + (on ? '1' : '0') + '">'
                            + peerPrefixBadge(peerStatusCache[row.uuid], 'ipv4', on) + '</span>';
                    },
                    peerPrefixes6: function (column, row) {
                        var on = peerFamilyEnabled(row, 'ipv6');
                        return '<span class="xray-peer-v6-cell" data-uuid="' + escAttr(row.uuid)
                            + '" data-family-on="' + (on ? '1' : '0') + '">'
                            + peerPrefixBadge(peerStatusCache[row.uuid], 'ipv6', on) + '</span>';
                    },
                    peerStatus: function (column, row) {
                        return '<span class="xray-peer-status-cell" data-uuid="' + escAttr(row.uuid) + '">'
                            + peerStatusBadge(peerStatusCache[row.uuid]) + '</span>';
                    }
                }
            }
        });

        function reloadBgpPeersGrid() {
            var $grid = $('#grid-bgppeers');
            if ($grid.length && $grid.data('bootgrid')) {
                $grid.bootgrid('reload');
            }
        }

        $('#grid-bgppeers').on('loaded.rs.jquery.bootgrid', function () {
            var $tbody = $(this).find('tbody');
            $tbody.find('tr').each(function () {
                var $tr = $(this);
                var isDnstap = $tr.children('td').filter(function () {
                    return $.trim($(this).text()) === 'dnstap';
                }).length > 0;
                if (isDnstap) {
                    $tbody.prepend($tr);
                    return false;
                }
            });
            applyPeerStatusToGrid();
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

        var xrayFilterBlockSeq = 0;

        function xrayFilterDlg() {
            return $('#DialogBgpFilter');
        }

        function xrayFilterField($dlg, id) {
            return $dlg.find('[id="' + id + '"]');
        }

        function xrayFilterRow($el) {
            return $el.closest('tr');
        }

        function xrayFilterDefaultTun() {
            var fam = String(xrayFilterField(xrayFilterDlg(), 'filter.family').val() || 'ipv4');
            return fam === 'ipv6' ? 'ACTIVE_TUN6_IF' : 'ACTIVE_TUN4_IF';
        }

        function xrayFilterReadBlocks() {
            var $dlg = xrayFilterDlg();
            var blocks = [];
            $dlg.find('[data-xray-block-field="community"]').each(function () {
                var $comm = $(this);
                var $tun = $comm.closest('tr').nextAll('tr').find('[data-xray-block-field="tun_if"]').first();
                if (!$tun.length) {
                    $tun = $comm.closest('.xray-filter-block').find('[data-xray-block-field="tun_if"]');
                }
                blocks.push({
                    community: String($comm.val() || ''),
                    tun_if: String($tun.val() || '')
                });
            });
            return blocks;
        }

        function xrayFilterWriteBlocks() {
            var $dlg = xrayFilterDlg();
            var blocks = xrayFilterReadBlocks();
            if (!blocks.length) {
                blocks = [{
                    community: String(xrayFilterField($dlg, 'filter.community').val() || ''),
                    tun_if: String(xrayFilterField($dlg, 'filter.tun_if').val() || xrayFilterDefaultTun())
                }];
            }
            var $hid = xrayFilterField($dlg, 'filter.blocks');
            $hid.val(JSON.stringify(blocks));
            if (blocks[0]) {
                xrayFilterField($dlg, 'filter.community').val(blocks[0].community);
                xrayFilterField($dlg, 'filter.tun_if').val(blocks[0].tun_if);
            }
        }

        function xrayFilterParseStored() {
            var $dlg = xrayFilterDlg();
            var raw = String(xrayFilterField($dlg, 'filter.blocks').val() || '').trim();
            var blocks = [];
            if (raw !== '') {
                try {
                    var j = JSON.parse(raw);
                    if ($.isArray(j)) {
                        j.forEach(function (b) {
                            if (!b || typeof b !== 'object') {
                                return;
                            }
                            blocks.push({
                                community: String(b.community || ''),
                                tun_if: String(b.tun_if || '')
                            });
                        });
                    }
                } catch (e) {
                    blocks = [];
                }
            }
            if (!blocks.length) {
                blocks.push({
                    community: String(xrayFilterField($dlg, 'filter.community').val() || ''),
                    tun_if: String(xrayFilterField($dlg, 'filter.tun_if').val() || xrayFilterDefaultTun())
                });
            }
            return blocks;
        }

        function xrayFilterStripPicker($sel) {
            if ($sel.parent().hasClass('bootstrap-select')) {
                $sel.insertBefore($sel.parent());
                $sel.prevAll('.bootstrap-select').add($sel.nextAll('.bootstrap-select')).remove();
            }
            $sel.removeClass('selectpicker').show();
            return $sel;
        }

        function xrayFilterInitPicker($sel) {
            $sel.addClass('selectpicker');
            if ($.fn.selectpicker) {
                try {
                    $sel.selectpicker('destroy');
                } catch (e) { /* not initialized */ }
                $sel.selectpicker({size: 8});
            }
        }

        function xrayFilterExtraBlock(community, tunIf) {
            var $dlg = xrayFilterDlg();
            var n = ++xrayFilterBlockSeq;
            var $srcC = xrayFilterField($dlg, 'filter.community');
            var $srcT = xrayFilterField($dlg, 'filter.tun_if');
            var $rowC = xrayFilterRow($srcC).clone();
            var $rowT = xrayFilterRow($srcT).clone();
            $rowC.addClass('xray-filter-extra xray-filter-block-row xray-filter-block-start');
            $rowT.addClass('xray-filter-extra xray-filter-block-row xray-filter-block-end');
            $rowC.find('.hidden, .show').filter('[data-for]').remove();
            $rowT.find('.hidden, .show').filter('[data-for]').remove();
            $rowC.find('a.xray-showhelp').remove();
            $rowT.find('a.xray-showhelp').remove();
            $rowC.add($rowT).find('.bootstrap-select').each(function () {
                var $wrap = $(this);
                var $sel = $wrap.find('select').first();
                $sel.insertAfter($wrap);
                $wrap.remove();
            });

            var $newC = $rowC.find('select').first();
            var $newT = $rowT.find('select').first();
            xrayFilterStripPicker($newC);
            xrayFilterStripPicker($newT);
            $newC.attr('id', 'xray_filter_comm_' + n).attr('name', '').attr('data-xray-block-field', 'community');
            $newT.attr('id', 'xray_filter_tun_' + n).attr('name', '').attr('data-xray-block-field', 'tun_if');
            $newC.find('option').prop('selected', false);
            $newT.find('option').prop('selected', false);
            if (community) {
                $newC.val(community);
            }
            $newT.val(tunIf || xrayFilterDefaultTun());
            $dlg.find('.xray-filter-block-actions').before($rowC, $rowT);
            xrayFilterInitPicker($newC);
            xrayFilterInitPicker($newT);
        }

        function xrayFilterDialogSetup() {
            var $dlg = xrayFilterDlg();
            var $comm = xrayFilterField($dlg, 'filter.community');
            var $tun = xrayFilterField($dlg, 'filter.tun_if');
            var $fam = xrayFilterField($dlg, 'filter.family');
            var $blocks = xrayFilterField($dlg, 'filter.blocks');
            if (!$comm.length || !$tun.length) {
                return;
            }
            var $commRow = xrayFilterRow($comm);
            var $tunRow = xrayFilterRow($tun);
            var $famRow = xrayFilterRow($fam);
            var $blocksRow = xrayFilterRow($blocks);
            $blocksRow.hide();
            if ($famRow.length && $commRow.length) {
                $famRow.insertBefore($commRow);
            }
            $dlg.find('.xray-filter-extra').remove();
            if (!$dlg.find('.xray-filter-block-actions').length) {
                var $act = $('<tr class="xray-filter-block-actions"/>');
                $act.append($('<td colspan="3"/>').append(
                    $('<button type="button" class="btn btn-xs btn-primary xray-filter-block-add" title="{{ lang._("Add") }}"/>')
                        .append($('<span class="fa fa-fw fa-plus"/>')),
                    ' ',
                    $('<button type="button" class="btn btn-xs btn-default xray-filter-block-del" title="{{ lang._("Remove") }}"/>')
                        .append($('<span class="fa fa-fw fa-minus"/>'))
                ));
                $tunRow.after($act);
            }
            $comm.attr('data-xray-block-field', 'community');
            $tun.attr('data-xray-block-field', 'tun_if');
            $commRow.add($tunRow).addClass('xray-filter-block-row');
            $commRow.addClass('xray-filter-block-start');
            $tunRow.addClass('xray-filter-block-end');
            var stored = xrayFilterParseStored();
            $comm.val(stored[0].community);
            $tun.val(stored[0].tun_if || xrayFilterDefaultTun());
            for (var i = 1; i < stored.length; i++) {
                xrayFilterExtraBlock(stored[i].community, stored[i].tun_if);
            }
            $dlg.find('.selectpicker').selectpicker('refresh');
            xrayFilterWriteBlocks();
        }

        $('#DialogBgpFilter').on('shown.bs.modal', function () {
            xrayFilterDialogSetup();
        });
        $(document).on('click', '#DialogBgpFilter .xray-filter-block-add', function (e) {
            e.preventDefault();
            xrayFilterExtraBlock('', xrayFilterDefaultTun());
            xrayFilterWriteBlocks();
        });
        $(document).on('click', '#DialogBgpFilter .xray-filter-block-del', function (e) {
            e.preventDefault();
            var $dlg = xrayFilterDlg();
            var $extras = $dlg.find('tr.xray-filter-extra');
            if ($extras.length >= 2) {
                $extras.slice(-2).remove();
            }
            xrayFilterWriteBlocks();
        });
        $(document).on('change', '#DialogBgpFilter [data-xray-block-field]', function () {
            xrayFilterWriteBlocks();
        });
        $('#DialogBgpFilter').on('click', '.modal-footer .btn-primary', function () {
            xrayFilterWriteBlocks();
        });

        $(document).ajaxSuccess(function (e, xhr, settings) {
            var url = settings.url || '';
            if (/\/api\/xray\/bgppeer\/(addItem|setItem|delItem|toggleItem)\b/.test(url)) {
                openRoutingPeersStatus();
            }
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

        function isBgpRoutingTab() {
            return $('#routing-peers, #routing-filters, #routing-communities').filter('.active').length > 0;
        }

        function isStaticTab() {
            return $('#routing-static').filter('.active').length > 0;
        }

        var staticProxyUrlsCache = [];
        var staticDirectUrlsCache = [];
        var staticBlockUrlsCache = [];
        var staticGeodatUrlsCache = [];
        var staticGeodatActiveUrl = '';

        function staticUrlEnabledOn(enabled, hasUrl) {
            // Missing flag: legacy / new empty row — checked only when URL present and server omitted flag
            if (enabled === undefined || enabled === null || enabled === '') {
                return !!hasUrl;
            }
            if (enabled === true || enabled === 1 || enabled === '1' || enabled === 'true' || enabled === 'on' || enabled === 'yes') {
                return true;
            }
            return false;
        }

        function staticUrlRow(key, value, enabled) {
            var val = value == null ? '' : String(value);
            var on = staticUrlEnabledOn(enabled, val.trim() !== '');
            var $tr = $('<tr/>');
            var $inp = $('<input type="text" class="form-control"/>')
                .attr('data-key', key)
                .attr('placeholder', 'https://')
                .val(val);
            var $fetch = $('<button type="button" class="btn btn-xs btn-default static-url-fetch"/>')
                .attr('title', '{{ lang._("Download and save this URL") }}')
                .text('✔');
            var $en = $('<label class="static-url-enable"/>')
                .append($('<input type="checkbox" class="static-url-enabled"/>').prop('checked', on))
                .append(document.createTextNode(' {{ lang._("Enable") }}'));
            $tr.append($('<td/>').append(
                $('<div class="static-row-edit"/>').append($inp, $fetch, $en)
            ));
            return $tr;
        }

        function staticListKind($tbody) {
            var id = String(($tbody && $tbody.attr('id')) || '');
            if (id.indexOf('Proxy') >= 0) {
                return 'proxy';
            }
            if (id.indexOf('Direct') >= 0) {
                return 'direct';
            }
            if (id.indexOf('Block') >= 0) {
                return 'block';
            }
            if (id.indexOf('Geodat') >= 0) {
                return 'geodat';
            }
            return 'proxy';
        }

        function staticCollectKv($tbody) {
            var rows = [];
            $tbody.find('tr').each(function () {
                var $inp = $(this).find('input[type="text"]').first();
                if (!$inp.length) {
                    return;
                }
                rows.push({
                    key: String($inp.attr('data-key') || 'url'),
                    value: String($inp.val() || ''),
                    enabled: $(this).find('.static-url-enabled').is(':checked') ? '1' : '0'
                });
            });
            return rows;
        }

        function staticFillOrEmpty($tbody, rows, key) {
            $tbody.empty();
            (rows || []).forEach(function (row) {
                var val = row.value || row.url || '';
                $tbody.append(staticUrlRow(row.key || key, val, row.enabled));
            });
            if (!$tbody.find('tr').length) {
                $tbody.append(staticUrlRow(key, '', false));
            }
        }

        function staticEnsureUrlLists() {
            ['#staticProxyUrlsKv', '#staticDirectUrlsKv', '#staticBlockUrlsKv', '#staticGeodatUrlsKv'].forEach(function (sel) {
                var $tbody = $(sel);
                if ($tbody.length && !$tbody.find('tr').length) {
                    $tbody.append(staticUrlRow(String($tbody.attr('data-row-key') || 'url'), '', false));
                }
            });
        }

        function staticWritePayload() {
            var proxyUrls = staticCollectKv($('#staticProxyUrlsKv'));
            if (!$('#staticProxyUrlsKv input').length && staticProxyUrlsCache.length) {
                proxyUrls = staticProxyUrlsCache;
            }
            var directUrls = staticCollectKv($('#staticDirectUrlsKv'));
            if (!$('#staticDirectUrlsKv input').length && staticDirectUrlsCache.length) {
                directUrls = staticDirectUrlsCache;
            }
            var blockUrls = staticCollectKv($('#staticBlockUrlsKv'));
            if (!$('#staticBlockUrlsKv input').length && staticBlockUrlsCache.length) {
                blockUrls = staticBlockUrlsCache;
            }
            var geodatUrls = staticCollectKv($('#staticGeodatUrlsKv'));
            if (!$('#staticGeodatUrlsKv input').length && staticGeodatUrlsCache.length) {
                geodatUrls = staticGeodatUrlsCache;
            }
            return {
                enabled: $('#staticEnabled').is(':checked') ? '1' : '0',
                proxy_urls: JSON.stringify(proxyUrls),
                direct_urls: JSON.stringify(directUrls),
                block_urls: JSON.stringify(blockUrls),
                geodat_urls: JSON.stringify(geodatUrls)
            };
        }

        function staticSetCounts(counts) {
            counts = counts || {};
            function setLabel(id, n4, n6) {
                var $el = $(id);
                if (!$el.length) {
                    return;
                }
                n4 = parseInt(n4, 10) || 0;
                n6 = parseInt(n6, 10) || 0;
                if (n4 + n6 > 0) {
                    $el.text('v4:' + n4 + ' v6:' + n6).show();
                } else {
                    $el.hide().text('');
                }
            }
            setLabel('#staticProxyCount', counts.proxy4, counts.proxy6);
            setLabel('#staticDirectCount', counts.direct4, counts.direct6);
            setLabel('#staticBlockCount', counts.block4, counts.block6);
        }

        function loadStaticConf() {
            ajaxGet('/api/xray/service/staticconf', {}, function (data) {
                if (!data || data.result === 'failed') {
                    staticEnsureUrlLists();
                    return;
                }
                $('#staticEnabled').prop('checked', String(data.enabled || '0') === '1');
                staticFillOrEmpty($('#staticProxyUrlsKv'), data.proxy_urls, 'url');
                staticFillOrEmpty($('#staticDirectUrlsKv'), data.direct_urls, 'url');
                staticFillOrEmpty($('#staticBlockUrlsKv'), data.block_urls, 'url');
                staticFillOrEmpty($('#staticGeodatUrlsKv'), data.geodat_urls, 'url');
                staticProxyUrlsCache = staticCollectKv($('#staticProxyUrlsKv'));
                staticDirectUrlsCache = staticCollectKv($('#staticDirectUrlsKv'));
                staticBlockUrlsCache = staticCollectKv($('#staticBlockUrlsKv'));
                staticGeodatUrlsCache = staticCollectKv($('#staticGeodatUrlsKv'));
                staticSetCounts(data.counts);
            });
        }

        function staticCollectGeodatUrls() {
            return staticCollectKv($('#staticGeodatUrlsKv')).filter(function (r) {
                return String(r.value || '').trim() !== '';
            });
        }

        function staticFillGeodatUrlPick(selected) {
            var $pick = $('#staticGeodatUrlPick').empty();
            staticCollectGeodatUrls().forEach(function (row) {
                var u = String(row.value || '').trim();
                if (u) {
                    $pick.append($('<option/>').attr('value', u).text(u));
                }
            });
            if (!$pick.find('option').length) {
                $pick.append($('<option/>').attr('value', '').text('—'));
            }
            if (selected) {
                $pick.val(selected);
            }
        }

        function staticGeodatFillModal(categories) {
            var $tb = $('#staticGeodatCats').empty();
            (categories || []).forEach(function (cat) {
                var name = String(cat.name || cat.key || '');
                if (!name) {
                    return;
                }
                var action = String(cat.action || cat.value || '');
                var $sel = $('<select class="form-control input-sm static-geodat-action"/>')
                    .attr('data-cat', name);
                [
                    {v: '', t: '—'},
                    {v: 'proxy', t: '{{ lang._("PROXY") }}'},
                    {v: 'direct', t: '{{ lang._("DIRECT") }}'},
                    {v: 'block', t: '{{ lang._("BLOCK") }}'}
                ].forEach(function (opt) {
                    $sel.append($('<option/>').attr('value', opt.v).text(opt.t));
                });
                $sel.val(action === 'proxy' || action === 'direct' || action === 'block' ? action : '');
                var $tr = $('<tr/>');
                $tr.append($('<td/>').text(name));
                $tr.append($('<td/>').text(String(cat.count != null ? cat.count : '')));
                $tr.append($('<td/>').append($sel));
                $tb.append($tr);
            });
            staticGeodatApplyFilter();
        }

        function staticGeodatApplyFilter() {
            var q = String($('#staticGeodatFilter').val() || '').toLowerCase();
            $('#staticGeodatCats tr').each(function () {
                var name = $(this).children('td').first().text().toLowerCase();
                $(this).toggle(!q || name.indexOf(q) !== -1);
            });
        }

        function staticGeodatCollectCats() {
            var rows = [];
            $('#staticGeodatCats select').each(function () {
                var name = String($(this).attr('data-cat') || '');
                var action = String($(this).val() || '');
                if (name && (action === 'proxy' || action === 'direct' || action === 'block')) {
                    rows.push({key: name, value: action});
                }
            });
            return rows;
        }

        function isDnstapTab() {
            return $('#dnstap').filter('.active').length > 0;
        }

        function isDomainsTab() {
            return $('#domains').filter('.active').length > 0;
        }

        var dnstapExtraProxy = [];
        var dnstapExtraDirect = [];
        var dnstapExtraBlock = [];
        var dnstapExtrasDirty = false;
        var dnstapConfCache = [];
        var dnstapProxyUrlsCache = [];
        var dnstapDirectUrlsCache = [];
        var dnstapBlockUrlsCache = [];
        var dnstapGeodatUrlsCache = [];
        var dnstapGeodatActiveUrl = '';
        var domainsListKind = 'proxy';

        function dnstapNormalizeDomain(raw) {
            var v = String(raw || '').replace(/^\uFEFF/, '').split('#')[0].trim().toLowerCase();
            v = v.replace(/^https?:\/\//, '').replace(/\/.*$/, '').replace(/\.+$/, '');
            if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(v)) {
                return '';
            }
            return v;
        }

        function dnstapRowsToDomains(rows) {
            var out = [];
            var seen = {};
            (rows || []).forEach(function (row) {
                var d = dnstapNormalizeDomain(row && row.value != null ? row.value : row);
                if (d && !seen[d]) {
                    seen[d] = true;
                    out.push(d);
                }
            });
            return out;
        }

        function dnstapDomainsToRows(list) {
            return (list || []).map(function (d) {
                return { key: 'domain', value: d };
            });
        }

        function dnstapWritePayload() {
            var conf = dnstapCollectKv($('#dnstapConfKv'));
            if (!conf.length && dnstapConfCache.length) {
                conf = dnstapConfCache;
            }
            var proxyUrls = dnstapCollectUrlKv($('#dnstapProxyUrlsKv'));
            if (!$('#dnstapProxyUrlsKv input[type="text"]').length && dnstapProxyUrlsCache.length) {
                proxyUrls = dnstapProxyUrlsCache;
            }
            var directUrls = dnstapCollectUrlKv($('#dnstapDirectUrlsKv'));
            if (!$('#dnstapDirectUrlsKv input[type="text"]').length && dnstapDirectUrlsCache.length) {
                directUrls = dnstapDirectUrlsCache;
            }
            var blockUrls = dnstapCollectUrlKv($('#dnstapBlockUrlsKv'));
            if (!$('#dnstapBlockUrlsKv input[type="text"]').length && dnstapBlockUrlsCache.length) {
                blockUrls = dnstapBlockUrlsCache;
            }
            var geodatUrls = dnstapCollectUrlKv($('#dnstapGeodatUrlsKv'));
            if (!$('#dnstapGeodatUrlsKv input[type="text"]').length && dnstapGeodatUrlsCache.length) {
                geodatUrls = dnstapGeodatUrlsCache;
            }
            return {
                conf: JSON.stringify(conf),
                proxy: JSON.stringify(dnstapDomainsToRows(dnstapExtraProxy)),
                proxy_urls: JSON.stringify(proxyUrls),
                direct: JSON.stringify(dnstapDomainsToRows(dnstapExtraDirect)),
                direct_urls: JSON.stringify(directUrls),
                block: JSON.stringify(dnstapDomainsToRows(dnstapExtraBlock)),
                block_urls: JSON.stringify(blockUrls),
                geodat_urls: JSON.stringify(geodatUrls)
            };
        }

        function dnstapCollectGeodatUrls() {
            var urls = dnstapCollectUrlKv($('#dnstapGeodatUrlsKv'));
            if (!$('#dnstapGeodatUrlsKv input[type="text"]').length && dnstapGeodatUrlsCache.length) {
                urls = dnstapGeodatUrlsCache;
            }
            return urls.filter(function (row) {
                return /^https?:\/\//i.test(String(row.value || '').trim());
            });
        }

        function updateDnstapBadge(running) {
            $('.xray-badge-dnstap')
                .removeClass('label-success label-danger label-default')
                .addClass(running ? 'label-success' : 'label-danger')
                .text('dnstap_bgp: ' + (running ? 'running' : 'stopped'));
        }

        function dnstapConfLabel(key) {
            var map = {
                ttl: '{{ lang._("Routing prefix TTL") }}',
                ipv6: '{{ lang._("Enable IPv6") }}',
                'bgp.peers': '{{ lang._("Bird IP") }}',
                'bgp.sourceIP': '{{ lang._("DNStap IP") }}',
                'bgp.proxy_communities': '{{ lang._("PROXY communities") }}',
                'bgp.direct_communities': '{{ lang._("DIRECT communities") }}',
                'bgp.block_communities': '{{ lang._("BLOCK communities") }}'
            };
            return map[key] || key;
        }

        function dnstapConfHelp(key) {
            var map = {
                ttl: '{{ lang._("How long advertised BGP prefixes stay in the dnstap-bgp cache (Go duration, e.g. 24h).") }}',
                ipv6: '{{ lang._("Enable IPv6 AFI in dnstap-bgp and the ipv6 channel on the BIRD dnstap peer.") }}',
                'bgp.peers': '{{ lang._("BIRD neighbor address (host side of the dnstap iBGP session).") }}',
                'bgp.sourceIP': '{{ lang._("dnstap-bgp source address (jail / DNStap side of the iBGP session).") }}',
                'bgp.proxy_communities': '{{ lang._("Fixed BGP community on PROXY prefixes (local AS:777). Not editable.") }}',
                'bgp.direct_communities': '{{ lang._("Fixed BGP community on DIRECT prefixes (local AS:555). Not editable.") }}',
                'bgp.block_communities': '{{ lang._("Fixed BGP community on BLOCK prefixes (local AS:888). Not editable.") }}'
            };
            return map[key] || '';
        }

        function dnstapHelpId(key) {
            return 'help_for_dnstap_' + String(key).replace(/[^A-Za-z0-9_]/g, '_');
        }

        function dnstapHelpBlock(hid, text) {
            if (!text) {
                return $();
            }
            return $('<div/>').addClass(xrayHelpClasses()).attr('data-for', hid)
                .append($('<small/>').text(text));
        }

        function dnstapConfRow(key, value) {
            var hid = dnstapHelpId(key);
            var help = dnstapConfHelp(key);
            var $tr = $('<tr/>');
            var $lab = $('<td class="dnstap-k"/>');
            if (help) {
                $lab.append($('<a href="#" class="xray-showhelp"/>').attr('id', hid)
                    .append($('<i class="fa fa-info-circle"/>')));
                $lab.append(document.createTextNode(' '));
            }
            $lab.append(document.createTextNode(dnstapConfLabel(key)));
            $tr.append($lab);
            var $val = $('<td/>');
            if (key === 'ipv6') {
                var on = value === true || value === 1 || String(value).toLowerCase() === 'true'
                    || String(value) === '1';
                var $cb = $('<input type="checkbox"/>')
                    .attr('data-key', key)
                    .prop('checked', on);
                $val.append($cb);
            } else {
                var $inp = $('<input type="text" class="form-control"/>')
                    .attr('data-key', key)
                    .val(value == null ? '' : String(value));
                if (key === 'bgp.proxy_communities' || key === 'bgp.direct_communities' || key === 'bgp.block_communities') {
                    $inp.prop('readonly', true).attr('tabindex', '-1')
                        .css({'cursor': 'default'});
                }
                $val.append($inp);
            }
            $val.append(dnstapHelpBlock(hid, help));
            $tr.append($val);
            return $tr;
        }

        function dnstapKvRow(key, value) {
            var $tr = $('<tr/>');
            var $inp = $('<input type="text" class="form-control"/>')
                .attr('data-key', key)
                .val(value == null ? '' : String(value));
            $tr.append($('<td/>').append($('<div class="dnstap-row-edit"/>').append($inp)));
            return $tr;
        }

        function dnstapUrlEnabledOn(enabled, hasUrl) {
            if (enabled === undefined || enabled === null || enabled === '') {
                return !!hasUrl;
            }
            if (enabled === true || enabled === 1 || enabled === '1' || enabled === 'true' || enabled === 'on' || enabled === 'yes') {
                return true;
            }
            return false;
        }

        function dnstapUrlRow(key, value, enabled) {
            var val = value == null ? '' : String(value);
            var on = dnstapUrlEnabledOn(enabled, val.trim() !== '');
            var $tr = $('<tr/>');
            var $inp = $('<input type="text" class="form-control"/>')
                .attr('data-key', key)
                .attr('placeholder', 'https://')
                .val(val);
            var $fetch = $('<button type="button" class="btn btn-xs btn-default dnstap-url-fetch"/>')
                .attr('title', '{{ lang._("Download and save this URL") }}')
                .text('✔');
            var $en = $('<label class="dnstap-url-enable"/>')
                .append($('<input type="checkbox" class="dnstap-url-enabled"/>').prop('checked', on))
                .append(document.createTextNode(' {{ lang._("Enable") }}'));
            $tr.append($('<td/>').append(
                $('<div class="dnstap-row-edit"/>').append($inp, $fetch, $en)
            ));
            return $tr;
        }

        function dnstapListKind($tbody) {
            var id = String(($tbody && $tbody.attr('id')) || '');
            if (id.indexOf('Proxy') >= 0) {
                return 'proxy';
            }
            if (id.indexOf('Direct') >= 0) {
                return 'direct';
            }
            if (id.indexOf('Block') >= 0) {
                return 'block';
            }
            if (id.indexOf('Geodat') >= 0) {
                return 'geodat';
            }
            return 'proxy';
        }

        function dnstapFillKv($tbody, rows) {
            $tbody.empty();
            (rows || []).forEach(function (row) {
                $tbody.append(dnstapKvRow(row.key || '', row.value || ''));
            });
        }

        function dnstapCollectKv($tbody) {
            var rows = [];
            $tbody.find('input').each(function () {
                var $el = $(this);
                rows.push({
                    key: String($el.attr('data-key') || ''),
                    value: $el.is(':checkbox') ? ($el.prop('checked') ? 'true' : 'false') : ($el.val() || '')
                });
            });
            return rows;
        }

        function dnstapCollectUrlKv($tbody) {
            var rows = [];
            $tbody.find('tr').each(function () {
                var $inp = $(this).find('input[type="text"]').first();
                if (!$inp.length) {
                    return;
                }
                rows.push({
                    key: String($inp.attr('data-key') || 'url'),
                    value: String($inp.val() || ''),
                    enabled: $(this).find('.dnstap-url-enabled').is(':checked') ? '1' : '0'
                });
            });
            return rows;
        }

        function dnstapFillOrEmpty($tbody, rows, key) {
            $tbody.empty();
            (rows || []).forEach(function (row) {
                var val = row.value || row.url || '';
                $tbody.append(dnstapUrlRow(row.key || key, val, row.enabled));
            });
            if (!$tbody.find('tr').length) {
                $tbody.append(dnstapUrlRow(key, '', false));
            }
        }

        function dnstapSetCount($el, n) {
            n = parseInt(n, 10);
            if (n > 0) {
                $el.text(String(n)).attr('title', '{{ lang._("Unique domains in the summarized file") }}').show();
            } else {
                $el.text('').hide();
            }
        }

        function loadDnstapConf() {
            ajaxGet('/api/xray/service/dnstapconf', {}, function (data) {
                if (!data || data.result === 'failed') {
                    updateDnstapBadge(false);
                    return;
                }
                updateDnstapBadge(!!data.running);
                dnstapSetCount($('#dnstapProxyCount'), data.proxy_count || data.blocked_count || data.domains_count);
                dnstapSetCount($('#dnstapDirectCount'), data.direct_count || data.unblocked_count);
                dnstapSetCount($('#dnstapBlockCount'), data.block_count);
                (function () {
                    var $tbody = $('#dnstapConfKv');
                    $tbody.empty();
                    (data.conf || []).forEach(function (row) {
                        $tbody.append(dnstapConfRow(row.key || '', row.value));
                    });
                })();
                dnstapFillOrEmpty($('#dnstapProxyUrlsKv'), data.proxy_urls || data.blocked_urls || data.urls, 'url');
                dnstapFillOrEmpty($('#dnstapDirectUrlsKv'), data.direct_urls || data.unblocked_urls, 'url');
                dnstapFillOrEmpty($('#dnstapBlockUrlsKv'), data.block_urls, 'url');
                dnstapFillOrEmpty($('#dnstapGeodatUrlsKv'), data.geodat_urls, 'url');
                dnstapConfCache = dnstapCollectKv($('#dnstapConfKv'));
                dnstapProxyUrlsCache = dnstapCollectUrlKv($('#dnstapProxyUrlsKv'));
                dnstapDirectUrlsCache = dnstapCollectUrlKv($('#dnstapDirectUrlsKv'));
                dnstapBlockUrlsCache = dnstapCollectUrlKv($('#dnstapBlockUrlsKv'));
                dnstapGeodatUrlsCache = dnstapCollectUrlKv($('#dnstapGeodatUrlsKv'));
                if (!dnstapExtrasDirty) {
                    dnstapExtraProxy = dnstapRowsToDomains(data.proxy || data.blocked_extra || data.blocked || data.domains);
                    dnstapExtraDirect = dnstapRowsToDomains(data.direct || data.unblocked_extra || data.unblocked);
                    dnstapExtraBlock = dnstapRowsToDomains(data.block);
                }
            });
        }

        function setApplyEndpoint() {
            var endpoint = '/api/xray/service/reconfigure';
            if (isBgpRoutingTab()) {
                endpoint = '/api/xray/service/bgpwrite';
            } else if (isStaticTab()) {
                endpoint = '/api/xray/service/staticwrite';
            } else if (isDnstapTab() || isDomainsTab()) {
                endpoint = '/api/xray/service/dnstapwrite';
            }
            $('#reconfigureAct').data('endpoint', endpoint).attr('data-endpoint', endpoint);
        }

        $('a[data-toggle="tab"]').on('shown.bs.tab', function () {
            setApplyEndpoint();
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

        $('a[data-toggle="tab"][href="#dnstap"]').on('shown.bs.tab', function () {
            loadDnstapConf();
        });
        $('a[data-toggle="tab"][href="#domains"]').on('shown.bs.tab', function () {
            loadDnstapConf();
        });
        $('a[data-toggle="tab"][href="#routing-static"]').on('shown.bs.tab', function () {
            loadStaticConf();
        });
        $(document).on('input', '#staticGeodatFilter', staticGeodatApplyFilter);
        $(document).on('change', '#staticGeodatUrlPick', function () {
            var url = String($(this).val() || '');
            if (!url) {
                return;
            }
            staticGeodatActiveUrl = url;
            $('#staticGeodatModalMsg').text("{{ lang._('Loading categories…') }}");
            $('#staticGeodatCats').empty();
            $.ajax({
                url: '/api/xray/service/staticgeodat',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {
                    geodat_urls: JSON.stringify(staticCollectGeodatUrls()),
                    geodat_url: url
                },
                success: function (data) {
                    if (!data || data.result === 'failed') {
                        $('#staticGeodatModalMsg').text((data && data.message) || 'failed');
                        return;
                    }
                    $('#staticGeodatModalMsg').text(data.message || "{{ lang._('Categories loaded.') }}");
                    staticGeodatFillModal(data.categories || []);
                },
                error: function (xhr) {
                    $('#staticGeodatModalMsg').text("{{ lang._('HTTP error:') }} " + xhr.status);
                }
            });
        });

        $(document).on('click', '.dnstap-url-add', function () {
            var $tbody = $('#' + $(this).attr('data-list'));
            if (!$tbody.length) {
                return;
            }
            var key = String($tbody.attr('data-row-key') || 'url');
            $tbody.append(dnstapUrlRow(key, '', false));
        });
        $(document).on('click', '.dnstap-url-remove', function () {
            var $tbody = $('#' + $(this).attr('data-list'));
            if (!$tbody.length) {
                return;
            }
            if ($tbody.find('tr').length <= 1) {
                $tbody.find('input[type="text"]').val('');
                $tbody.find('.dnstap-url-enabled').prop('checked', false);
                return;
            }
            $tbody.find('tr').last().remove();
        });
        $(document).on('click', '.dnstap-url-fetch', function () {
            var $tr = $(this).closest('tr');
            var $tbody = $tr.closest('tbody');
            var url = String($tr.find('input[type="text"]').val() || '').trim();
            var kind = dnstapListKind($tbody);
            var enabled = $tr.find('.dnstap-url-enabled').is(':checked') ? '1' : '0';
            if (!url || !/^https?:\/\//i.test(url)) {
                BootstrapDialog.show({
                    type: BootstrapDialog.TYPE_WARNING,
                    title: "{{ lang._('DNStap') }}",
                    message: "{{ lang._('Enter a valid HTTP(S) URL first.') }}"
                });
                return;
            }
            var $btn = $(this).prop('disabled', true);
            $.ajax({
                url: '/api/xray/service/dnstapfetchone',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {kind: kind, url: url, enabled: enabled},
                success: function (data) {
                    $btn.prop('disabled', false);
                    if (!data || data.result === 'failed') {
                        alert(data && data.message ? data.message : '{{ lang._("Download failed") }}');
                        return;
                    }
                    loadDnstapConf();
                },
                error: function (xhr) {
                    $btn.prop('disabled', false);
                    alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                }
            });
        });
        $(document).on('click', '.static-url-add', function () {
            var $tbody = $('#' + $(this).attr('data-list'));
            if (!$tbody.length) {
                return;
            }
            var key = String($tbody.attr('data-row-key') || 'url');
            $tbody.append(staticUrlRow(key, '', false));
        });
        $(document).on('click', '.static-url-remove', function () {
            var $tbody = $('#' + $(this).attr('data-list'));
            if (!$tbody.length) {
                return;
            }
            if ($tbody.find('tr').length <= 1) {
                $tbody.find('input[type="text"]').val('');
                $tbody.find('.static-url-enabled').prop('checked', false);
                return;
            }
            $tbody.find('tr').last().remove();
        });
        $(document).on('click', '.static-url-fetch', function () {
            var $tr = $(this).closest('tr');
            var $tbody = $tr.closest('tbody');
            var url = String($tr.find('input[type="text"]').val() || '').trim();
            var kind = staticListKind($tbody);
            var enabled = $tr.find('.static-url-enabled').is(':checked') ? '1' : '0';
            if (!url || !/^https?:\/\//i.test(url)) {
                BootstrapDialog.show({
                    type: BootstrapDialog.TYPE_WARNING,
                    title: "{{ lang._('Static') }}",
                    message: "{{ lang._('Enter a valid HTTP(S) URL first.') }}"
                });
                return;
            }
            var $btn = $(this).prop('disabled', true);
            $.ajax({
                url: '/api/xray/service/staticfetchone',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {kind: kind, url: url, enabled: enabled},
                success: function (data) {
                    $btn.prop('disabled', false);
                    // Always reload so persisted URL stays visible in the list
                    loadStaticConf();
                    if (!data || data.result === 'failed') {
                        alert(data && data.message ? data.message : '{{ lang._("Download failed") }}');
                        return;
                    }
                    if (data.download_ok === false) {
                        alert(data.message || '{{ lang._("URL saved, but download failed") }}');
                    }
                },
                error: function (xhr) {
                    $btn.prop('disabled', false);
                    loadStaticConf();
                    alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                }
            });
        });
        $('#staticGeodatCategory').on('click', function () {
            var urls = staticCollectGeodatUrls();
            if (!urls.length) {
                BootstrapDialog.show({
                    type: BootstrapDialog.TYPE_WARNING,
                    title: "{{ lang._('Geodat') }}",
                    message: "{{ lang._('Add at least one Geodat URL first.') }}"
                });
                return;
            }
            staticFillGeodatUrlPick(staticGeodatActiveUrl || urls[0].value);
            $('#staticGeodatCats').empty();
            $('#staticGeodatModalMsg').text("{{ lang._('Loading categories…') }}");
            $('#staticGeodatModal').modal('show');
            $('#staticGeodatUrlPick').trigger('change');
        });
        $('#staticGeodatModal').on('click', '.static-geodat-save', function () {
            var url = String($('#staticGeodatUrlPick').val() || '');
            if (!url) {
                return;
            }
            var cats = staticGeodatCollectCats();
            var $saveBtn = $(this).prop('disabled', true);
            $('#staticGeodatModalMsg').text("{{ lang._('Saving…') }}");
            $.ajax({
                url: '/api/xray/service/staticgeodat',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {
                    geodat_urls: JSON.stringify(staticCollectGeodatUrls()),
                    geodat_url: url,
                    geodat_categories: JSON.stringify(cats)
                },
                success: function (data) {
                    $saveBtn.prop('disabled', false);
                    if (!data || data.result === 'failed') {
                        $('#staticGeodatModalMsg').text((data && data.message) || 'failed');
                        return;
                    }
                    staticGeodatActiveUrl = url;
                    var msg = data.message || "{{ lang._('Saved.') }}";
                    if (data.saved) {
                        msg = "{{ lang._('Saved.') }}" + (data.message ? (' — ' + data.message) : '');
                    }
                    $('#staticGeodatModalMsg').text(msg);
                    if (data.categories && data.categories.length) {
                        staticGeodatFillModal(data.categories);
                    }
                    // Keep modal open; selections stay after refill from saved assignments
                },
                error: function (xhr) {
                    $saveBtn.prop('disabled', false);
                    $('#staticGeodatModalMsg').text("{{ lang._('HTTP error:') }} " + xhr.status
                        + "{{ lang._(' — assignments may still have been written; reopen Category to verify.') }}");
                }
            });
        });
        function dnstapGeodatFillModal(categories) {
            var $tb = $('#dnstapGeodatCats').empty();
            (categories || []).forEach(function (cat) {
                var name = String(cat.name || cat.key || '');
                if (!name) {
                    return;
                }
                var action = String(cat.action || cat.value || '');
                var $sel = $('<select class="form-control input-sm dnstap-geodat-action"/>')
                    .attr('data-cat', name);
                [
                    {v: '', t: '—'},
                    {v: 'proxy', t: '{{ lang._("PROXY") }}'},
                    {v: 'direct', t: '{{ lang._("DIRECT") }}'},
                    {v: 'block', t: '{{ lang._("BLOCK") }}'}
                ].forEach(function (opt) {
                    $sel.append($('<option/>').attr('value', opt.v).text(opt.t));
                });
                if (action === 'blocked') {
                    action = 'proxy';
                } else if (action === 'unblocked') {
                    action = 'direct';
                }
                $sel.val(action === 'proxy' || action === 'direct' || action === 'block' ? action : '');
                var $tr = $('<tr/>');
                $tr.append($('<td/>').text(name));
                $tr.append($('<td/>').text(String(cat.count != null ? cat.count : '')));
                $tr.append($('<td/>').append($sel));
                $tb.append($tr);
            });
            dnstapGeodatApplyFilter();
        }

        function dnstapGeodatApplyFilter() {
            var q = String($('#dnstapGeodatFilter').val() || '').toLowerCase();
            $('#dnstapGeodatCats tr').each(function () {
                var name = $(this).children('td').first().text().toLowerCase();
                $(this).toggle(!q || name.indexOf(q) !== -1);
            });
        }

        function dnstapGeodatCollectCats() {
            var rows = [];
            $('#dnstapGeodatCats select').each(function () {
                var name = String($(this).attr('data-cat') || '');
                var action = String($(this).val() || '');
                if (name && (action === 'proxy' || action === 'direct' || action === 'block')) {
                    rows.push({key: name, value: action});
                }
            });
            return rows;
        }

        $(document).on('input', '#dnstapGeodatFilter', dnstapGeodatApplyFilter);

        function dnstapGeodatFillUrlPick(selected) {
            var $pick = $('#dnstapGeodatUrlPick').empty();
            dnstapCollectGeodatUrls().forEach(function (row) {
                var u = String(row.value || '').trim();
                $pick.append($('<option/>').attr('value', u).text(u));
            });
            if (selected) {
                $pick.val(selected);
            }
            dnstapGeodatActiveUrl = String($pick.val() || '');
        }

        function dnstapGeodatLoad(url) {
            var urls = dnstapCollectGeodatUrls();
            if (!url) {
                return;
            }
            dnstapGeodatActiveUrl = url;
            $('#dnstapGeodatStatus').text('{{ lang._("Downloading geosite.dat…") }}');
            $('#dnstapGeodatCats').empty();
            $.ajax({
                url: '/api/xray/service/dnstapgeodat',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {
                    geodat_urls: JSON.stringify(urls),
                    geodat_url: url
                },
                success: function (data) {
                    if (!data || data.result === 'failed') {
                        $('#dnstapGeodatStatus').text(data && data.message
                            ? data.message
                            : '{{ lang._("Failed to parse geosite.dat") }}');
                        return;
                    }
                    var n = (data.categories || []).length;
                    $('#dnstapGeodatStatus').text(
                        '{{ lang._("Categories in file:") }} ' + n
                    );
                    dnstapGeodatFillModal(data.categories || []);
                },
                error: function (xhr) {
                    $('#dnstapGeodatStatus').text('{{ lang._("HTTP error:") }} ' + xhr.status);
                }
            });
        }

        $(document).on('change', '#dnstapGeodatUrlPick', function () {
            dnstapGeodatLoad(String($(this).val() || ''));
        });

        $(document).on('click', '.dnstap-geodat-category', function () {
            var urls = dnstapCollectGeodatUrls().filter(function (row) {
                return String(row.value || '').trim() !== '';
            });
            if (!urls.length) {
                alert('{{ lang._("Add a geosite.dat URL first.") }}');
                return;
            }
            $('#dnstapGeodatModal').modal('show');
            dnstapGeodatFillUrlPick(urls[0].value);
            dnstapGeodatLoad(dnstapGeodatActiveUrl);
        });

        $(document).on('click', '#dnstapGeodatSave', function () {
            var urls = dnstapCollectGeodatUrls();
            var url = dnstapGeodatActiveUrl || String($('#dnstapGeodatUrlPick').val() || '');
            var cats = dnstapGeodatCollectCats();
            var $btn = $(this).prop('disabled', true);
            $('#dnstapGeodatStatus').text('{{ lang._("Saving categories…") }}');
            $.ajax({
                url: '/api/xray/service/dnstapgeodat',
                type: 'POST',
                dataType: 'json',
                timeout: 180000,
                data: {
                    geodat_urls: JSON.stringify(urls),
                    geodat_url: url,
                    geodat_categories: JSON.stringify(cats)
                },
                success: function (data) {
                    $btn.prop('disabled', false);
                    if (!data || data.result === 'failed') {
                        $('#dnstapGeodatStatus').text(data && data.message
                            ? data.message
                            : '{{ lang._("Failed to save categories") }}');
                        return;
                    }
                    dnstapGeodatUrlsCache = urls;
                    $('#dnstapGeodatModal').modal('hide');
                    loadDnstapConf();
                },
                error: function (xhr) {
                    $btn.prop('disabled', false);
                    $('#dnstapGeodatStatus').text('{{ lang._("HTTP error:") }} ' + xhr.status);
                }
            });
        });

        $(document).on('click', '#dnstapStart', function () {
            var $btn = $(this).prop('disabled', true);
            ajaxCall('/api/xray/service/dnstapstart', {}, function (data) {
                $btn.prop('disabled', false);
                loadDnstapConf();
                if (!data || data.result === 'failed') {
                    alert(data && data.message ? data.message : '{{ lang._("Failed to start dnstap-bgp") }}');
                }
            });
        });
        function dnstapExtraInput(kind) {
            if (kind === 'direct') {
                return $('#domainsDirectInput');
            }
            if (kind === 'block') {
                return $('#domainsBlockInput');
            }
            return $('#domainsProxyInput');
        }

        function dnstapExtraList(kind) {
            if (kind === 'direct') {
                return dnstapExtraDirect;
            }
            if (kind === 'block') {
                return dnstapExtraBlock;
            }
            return dnstapExtraProxy;
        }

        function dnstapExtraSet(kind, list) {
            if (kind === 'direct') {
                dnstapExtraDirect = list;
            } else if (kind === 'block') {
                dnstapExtraBlock = list;
            } else {
                dnstapExtraProxy = list;
            }
        }

        function dnstapExtraAdd(kind) {
            var $inp = dnstapExtraInput(kind);
            var d = dnstapNormalizeDomain($inp.val());
            if (d === '') {
                alert('{{ lang._("Enter a valid domain name.") }}');
                return;
            }
            var list = dnstapExtraList(kind);
            if (list.indexOf(d) === -1) {
                list.push(d);
            }
            dnstapExtraSet(kind, list);
            dnstapExtrasDirty = true;
            $inp.val(d);
        }

        function dnstapExtraRemove(kind, domain) {
            var $inp = dnstapExtraInput(kind);
            var d = domain ? dnstapNormalizeDomain(domain) : dnstapNormalizeDomain($inp.val());
            dnstapExtraSet(kind, dnstapExtraList(kind).filter(function (x) { return x !== d; }));
            dnstapExtrasDirty = true;
            if ($inp.val() && dnstapNormalizeDomain($inp.val()) === d) {
                $inp.val('');
            }
        }

        function dnstapRenderDomainList(filter) {
            var list = dnstapExtraList(domainsListKind);
            var q = String(filter || '').toLowerCase();
            var shown = 0;
            var $tb = $('#domainsListRows').empty();
            list.slice().sort().forEach(function (d) {
                if (q && d.indexOf(q) === -1) {
                    return;
                }
                shown++;
                var $tr = $('<tr/>').css('cursor', 'pointer');
                $tr.append($('<td/>').text(d));
                var $rm = $('<button type="button" class="btn btn-xs btn-default"/>')
                    .attr('title', '{{ lang._("Remove") }}')
                    .append($('<span class="fa fa-fw fa-minus"/>'));
                $rm.on('click', function (e) {
                    e.preventDefault();
                    e.stopPropagation();
                    dnstapExtraRemove(domainsListKind, d);
                    dnstapRenderDomainList($('#domainsListFilter').val());
                });
                $tr.append($('<td/>').css({'width': '2.5em', 'text-align': 'right', 'white-space': 'nowrap'}).append($rm));
                $tr.on('click', function () {
                    dnstapExtraInput(domainsListKind).val(d);
                    $('#domainsListModal').modal('hide');
                });
                $tb.append($tr);
            });
            $('#domainsListCount').text(shown + ' / ' + list.length);
        }

        function dnstapOpenDomainList(kind) {
            domainsListKind = kind;
            var title = '{{ lang._("Extra PROXY domains") }}';
            if (kind === 'direct') {
                title = '{{ lang._("Extra DIRECT domains") }}';
            } else if (kind === 'block') {
                title = '{{ lang._("Extra BLOCK domains") }}';
            }
            $('#domainsListModalTitle').text(title);
            $('#domainsListFilter').val('');
            dnstapRenderDomainList('');
            $('#domainsListModal').modal('show');
        }

        function domainsRenderRouteRows(rows) {
            var $tb = $('#domainsCheckRows').empty();
            (rows || []).forEach(function (r) {
                $tb.append(
                    '<tr><td>' + escAttr(r.domain || '') + '</td>'
                    + '<td>' + escAttr(r.ip || '') + '</td>'
                    + '<td>' + escAttr(r.peer || 'N/A') + '</td>'
                    + '<td>' + escAttr(r.instance || 'N/A') + '</td>'
                    + '<td>' + escAttr(r.dev || 'WAN4') + '</td>'
                    + '<td>' + (r.active ? '{{ lang._("yes") }}' : '{{ lang._("no") }}') + '</td></tr>'
                );
            });
        }

        function domainsCheckRoute() {
            var d = $.trim($('#domainsCheckInput').val() || '');
            var $btn = $('#domainsCheckBtn');
            var $msg = $('#domainsCheckMsg');
            var $tbl = $('#domainsCheckTable');
            if (!d) {
                $tbl.hide();
                $msg.text('{{ lang._("Enter a domain") }}').show();
                return;
            }
            $btn.prop('disabled', true);
            $msg.text('{{ lang._("Checking…") }}').show();
            ajaxCall('/api/xray/service/domainroute', { domain: d }, function (data) {
                $btn.prop('disabled', false);
                var rows = data && data.rows ? data.rows : [];
                domainsRenderRouteRows(rows);
                if (rows.length) {
                    $tbl.show();
                    $msg.hide();
                } else {
                    $tbl.hide();
                    $msg.text((data && data.message) ? data.message : '{{ lang._("No routes") }}').show();
                }
            });
        }

        $(document).on('click', '#domainsCheckBtn', function () { domainsCheckRoute(); });
        $('#domainsCheckInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                domainsCheckRoute();
            }
        });

        $(document).on('click', '#domainsProxyAdd', function () { dnstapExtraAdd('proxy'); });
        $(document).on('click', '#domainsDirectAdd', function () { dnstapExtraAdd('direct'); });
        $(document).on('click', '#domainsBlockAdd', function () { dnstapExtraAdd('block'); });
        $(document).on('click', '#domainsProxyRemove', function () { dnstapExtraRemove('proxy'); });
        $(document).on('click', '#domainsDirectRemove', function () { dnstapExtraRemove('direct'); });
        $(document).on('click', '#domainsBlockRemove', function () { dnstapExtraRemove('block'); });
        $(document).on('click', '#domainsProxySearch', function () { dnstapOpenDomainList('proxy'); });
        $(document).on('click', '#domainsDirectSearch', function () { dnstapOpenDomainList('direct'); });
        $(document).on('click', '#domainsBlockSearch', function () { dnstapOpenDomainList('block'); });
        $(document).on('input', '#domainsListFilter', function () {
            dnstapRenderDomainList($(this).val());
        });
        $('#domainsProxyInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                dnstapExtraAdd('proxy');
            }
        });
        $('#domainsDirectInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                dnstapExtraAdd('direct');
            }
        });
        $('#domainsBlockInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                dnstapExtraAdd('block');
            }
        });

        $(document).on('click', '#dnstapStop', function () {
            var $btn = $(this).prop('disabled', true);
            ajaxCall('/api/xray/service/dnstapstop', {}, function (data) {
                $btn.prop('disabled', false);
                loadDnstapConf();
                if (!data || data.result === 'failed') {
                    alert(data && data.message ? data.message : '{{ lang._("Failed to stop dnstap-bgp") }}');
                }
            });
        });

        // ── General settings form ───────────────────────────────────
        mapDataToFormUI({'frm_general_settings': "/api/xray/general/get"}).done(function () {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
        });

        // ── Apply: routing → bgpwrite; DNStap → files; otherwise general + reconfigure ──
        setApplyEndpoint();
        $("#reconfigureAct").SimpleActionButton({
            onPreAction: function () {
                var dfObj = new $.Deferred();
                if (isBgpRoutingTab()) {
                    dfObj.resolve();
                    return dfObj;
                }
                if (isStaticTab()) {
                    $.ajax({
                        url: '/api/xray/service/staticwrite',
                        type: 'POST',
                        dataType: 'json',
                        data: staticWritePayload(),
                        success: function (data) {
                            if (data && data.result === 'failed') {
                                alert('{{ lang._("Failed to write Static IP lists:") }} '
                                    + (data.message || 'unknown error'));
                                dfObj.reject();
                                return;
                            }
                            loadStaticConf();
                            dfObj.resolve();
                        },
                        error: function (xhr) {
                            alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                            dfObj.reject();
                        }
                    });
                    return dfObj;
                }
                if (isDnstapTab() || isDomainsTab()) {
                    $.ajax({
                        url: '/api/xray/service/dnstapwrite',
                        type: 'POST',
                        dataType: 'json',
                        data: dnstapWritePayload(),
                        success: function (data) {
                            if (data && data.result === 'failed') {
                                alert('{{ lang._("Failed to write dnstap-bgp config:") }} '
                                    + (data.message || 'unknown error'));
                                dfObj.reject();
                                return;
                            }
                            dnstapExtrasDirty = false;
                            loadDnstapConf();
                            dfObj.resolve();
                        },
                        error: function (xhr) {
                            alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                            dfObj.reject();
                        }
                    });
                    return dfObj;
                }
                saveFormToEndpoint("/api/xray/general/set", 'frm_general_settings', function () {
                    dfObj.resolve();
                });
                return dfObj;
            },
            onAction: function () {
                // Clear pending-change banners (incl. after fast OK from background reconfigure)
                $('#InstanceChangeMessage, #BgpPeerChangeMessage, #BgpFilterChangeMessage, #BgpCommunityChangeMessage')
                    .hide();
                $('.alert[id$="ChangeMessage"]').hide();
                reloadBgpPeersGrid();
                if (isBgpRoutingTab()) {
                    openRoutingPeersStatus();
                }
                if (isStaticTab()) {
                    loadStaticConf();
                }
                if (isDnstapTab() || isDomainsTab()) {
                    loadDnstapConf();
                }
                setTimeout(function () { refreshInstancesStatus(); }, 2000);
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
        loadDnstapConf();

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
                timeout:  180000,
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
                    // 504: gateway timed out while start may still have succeeded
                    if (xhr.status === 504 || xhr.status === 502) {
                        setTimeout(function () { refreshInstancesStatus(); }, 1500);
                        alert('{{ lang._("Request timed out — check instance status; services may still have started.") }}');
                        return;
                    }
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

        // ── Test all IF (SOCKS) / Test auto route (separate) ─────────
        function xrayEnabledRunningUuids() {
            var uuids = [];
            $.each(instanceStatusCache, function (uuid, info) {
                if (info.enabled === false || info.enabled === 0 || info.enabled === '0') {
                    return;
                }
                if (info.xray_core === 'running') {
                    uuids.push(uuid);
                }
            });
            return uuids;
        }

        $('#btnTestConnect').click(function () {
            var $btn = $(this).prop('disabled', true);
            var $res = $('#testConnectResult');
            var uuids = xrayEnabledRunningUuids();

            if (!uuids.length) {
                $res.removeClass('text-success').addClass('text-danger')
                    .text("{{ lang._('No enabled running instances.') }}");
                $btn.prop('disabled', false);
                return;
            }

            $res.removeClass('text-success text-danger').text("{{ lang._('Testing IF...') }}");
            var pending = uuids.length;
            var anyFail = false;

            $.each(uuids, function (_, uuid) {
                $.ajax({
                    url: '/api/xray/service/testconnect/' + encodeURIComponent(uuid),
                    type: 'POST', dataType: 'json',
                    timeout: 60000,
                    success: function (data) {
                        instanceTestCache[uuid] = data;
                        applyTestResultToGrid();
                        if (!(data && data.result === 'ok')) {
                            anyFail = true;
                        }
                    },
                    error: function () {
                        anyFail = true;
                    },
                    complete: function () {
                        pending--;
                        if (pending === 0) {
                            $btn.prop('disabled', false);
                            if (anyFail) {
                                $res.removeClass('text-success').addClass('text-danger')
                                    .text("{{ lang._('IF test finished with errors — see Test column.') }}");
                            } else {
                                $res.removeClass('text-danger').addClass('text-success')
                                    .text("{{ lang._('IF test OK.') }}");
                            }
                        }
                    }
                });
            });
        });

        $('#btnTestAutoRoute').click(function () {
            var $btn = $(this).prop('disabled', true);
            var $res = $('#testConnectResult');
            $res.removeClass('text-success text-danger')
                .text("{{ lang._('Auto route...') }}");
            $.ajax({
                url: '/api/xray/service/birdactivetun',
                type: 'POST',
                dataType: 'json',
                timeout: 30000,
                success: function (data) {
                    var msg = (data && data.message) ? String(data.message) : '';
                    var lines = msg.split('\n').map(function (l) { return l.trim(); }).filter(Boolean);
                    var short = lines.slice(0, 2).join(' ')
                        .replace(/\s*RESULT:(OK|ERROR)\s*/g, '').trim();
                    if (data && data.result === 'ok') {
                        $res.removeClass('text-danger').addClass('text-success')
                            .text(short !== '' ? short : "{{ lang._('Auto route started.') }}");
                        setTimeout(function () { reloadBgpPeersGrid(); }, 3000);
                        // Latency columns fill after background probes finish
                        setTimeout(refreshInstancesStatus, 4000);
                        setTimeout(refreshInstancesStatus, 10000);
                    } else {
                        $res.removeClass('text-success').addClass('text-danger')
                            .text(short !== '' ? short : "{{ lang._('Auto route failed.') }}");
                    }
                },
                error: function (xhr) {
                    $res.removeClass('text-success').addClass('text-danger')
                        .text("{{ lang._('Auto route failed.') }} HTTP " + (xhr.status || '?'));
                },
                complete: function () {
                    $btn.prop('disabled', false);
                }
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
            loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn', true);
        });

        // ── Logs ────────────────────────────────────────────────────
        function loadLog(apiEndpoint, preId, btnId, withUuid) {
            var uuid = withUuid ? $('#logInstanceSelect').val() : '';
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
                loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn', false);
            } else if (href === '#logCore') {
                loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn', true);
            } else if (href === '#logBird') {
                loadBirdLogLevel();
                loadLog("/api/xray/service/birdlog", 'logBirdContent', 'logBirdRefreshBtn', false);
            } else if (href === '#logDnstap') {
                loadLog("/api/xray/service/dnstaplog", 'logDnstapContent', 'logDnstapRefreshBtn', false);
            }
        });

        $('#logSubTabs a').on('shown.bs.tab', function (e) {
            var href = $(e.target).attr('href');
            if (href === '#logBoot') {
                loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn', false);
            } else if (href === '#logCore') {
                loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn', true);
            } else if (href === '#logBird') {
                loadBirdLogLevel();
                loadLog("/api/xray/service/birdlog", 'logBirdContent', 'logBirdRefreshBtn', false);
            } else if (href === '#logDnstap') {
                loadLog("/api/xray/service/dnstaplog", 'logDnstapContent', 'logDnstapRefreshBtn', false);
            }
        });

        $("#logBootRefreshBtn").click(function () {
            loadLog("/api/xray/service/log", 'logBootContent', 'logBootRefreshBtn', false);
        });
        $("#logCoreRefreshBtn").click(function () {
            loadLog("/api/xray/service/xraylog", 'logCoreContent', 'logCoreRefreshBtn', true);
        });
        $("#logBirdRefreshBtn").click(function () {
            loadLog("/api/xray/service/birdlog", 'logBirdContent', 'logBirdRefreshBtn', false);
        });
        $("#logDnstapRefreshBtn").click(function () {
            loadLog("/api/xray/service/dnstaplog", 'logDnstapContent', 'logDnstapRefreshBtn', false);
        });

        function loadBirdLogLevel() {
            ajaxGet('/api/xray/service/birdloglevel', {}, function (data) {
                var level = (data && data.level) ? data.level : 'warning';
                $('#logBirdLevelSelect').val(level);
            });
        }

        $('#logBirdLevelSelect').on('change', function () {
            var level = $(this).val();
            var $sel = $(this).prop('disabled', true);
            $.ajax({
                url: '/api/xray/service/birdloglevel',
                type: 'POST',
                dataType: 'json',
                data: { level: level },
                success: function (data) {
                    if (data && data.result === 'failed') {
                        alert('{{ lang._("Failed to set BIRD log class:") }} ' + (data.message || 'unknown error'));
                        loadBirdLogLevel();
                        return;
                    }
                    loadLog("/api/xray/service/birdlog", 'logBirdContent', 'logBirdRefreshBtn', false);
                },
                error: function (xhr) {
                    alert('{{ lang._("HTTP error:") }} ' + xhr.status);
                    loadBirdLogLevel();
                },
                complete: function () {
                    $sel.prop('disabled', false);
                }
            });
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
                    + "--- Boot Log (last 300 lines) ---\n"
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

        // ── Tab selection ──
        // Left menu uses /ui/xray/page/show/<tab> (path stays in REQUEST_URI so
        // OPNsense keeps VPN→Xray expanded). Legacy ?tab= / #hash still work.
        var xrayInitialTab = '{{ xrayInitialTab|default("instances") }}';

        function xrayTabFromHref(href) {
            href = String(href || '');
            var m = href.match(/\/ui\/xray\/page\/show\/([^\/?#]+)/);
            if (m) {
                return decodeURIComponent(m[1]);
            }
            m = href.match(/[?&]tab=([^&#]+)/);
            if (m) {
                return decodeURIComponent(m[1]);
            }
            m = href.match(/#([^?]+)/);
            if (m) {
                return m[1];
            }
            return '';
        }

        function xrayTabFromLocation() {
            var tab = xrayTabFromHref(window.location.pathname + window.location.search + window.location.hash);
            if (tab) {
                if (tab === 'routing') {
                    return 'routing-peers';
                }
                return tab;
            }
            if (xrayInitialTab) {
                return String(xrayInitialTab);
            }
            return 'instances';
        }

        function xrayEnsureLeftMenuOpen() {
            $('#mainmenu a.list-group-item[href*="/ui/xray"]').each(function () {
                $(this).parents('.collapse').addClass('in').css({height: 'auto'});
                $(this).parents('li').children('a.active-menu-title, a.list-group-item').first()
                    .addClass('active-menu-title');
            });
        }

        function xraySyncLeftMenu(tab) {
            tab = String(tab || '').replace(/^#/, '');
            $('#mainmenu a.list-group-item[href*="/ui/xray"]').each(function () {
                var item = xrayTabFromHref($(this).attr('href'));
                $(this).toggleClass('active', item !== '' && item === tab);
            });
            xrayEnsureLeftMenuOpen();
        }

        function xrayActivateTab(tab) {
            tab = String(tab || '').replace(/^#/, '');
            if (!tab) {
                return;
            }
            var $tab = $('#maintabs a[data-toggle="tab"][href="#' + tab + '"]');
            if ($tab.length) {
                $tab.tab('show');
            }
            xraySyncLeftMenu(tab);
        }

        function xrayReplaceTabUrl(tab) {
            tab = String(tab || '').replace(/^#/, '');
            if (!tab || !window.history || !window.history.replaceState) {
                return;
            }
            history.replaceState(null, null, '/ui/xray/page/show/' + encodeURIComponent(tab));
        }

        // Switch tabs via left menu without full reload (avoids sidebar collapse flash)
        $(document).on('click', '#mainmenu a.list-group-item[href*="/ui/xray"]', function (e) {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.which === 2) {
                return;
            }
            var tab = xrayTabFromHref($(this).attr('href'));
            if (!tab || !$('#maintabs a[data-toggle="tab"][href="#' + tab + '"]').length) {
                return;
            }
            e.preventDefault();
            xrayActivateTab(tab);
            xrayReplaceTabUrl(tab);
        });

        xrayActivateTab(xrayTabFromLocation());
        $(window).on('hashchange', function () {
            xrayActivateTab(xrayTabFromLocation());
        });
        $(window).on('popstate', function () {
            xrayActivateTab(xrayTabFromLocation());
        });
        $('.nav-tabs a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
            var tab = String(e.target.hash || '').replace(/^#/, '');
            if (tab) {
                xrayReplaceTabUrl(tab);
                xraySyncLeftMenu(tab);
            }
        });
    });
</script>
