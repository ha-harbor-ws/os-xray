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

        function isDnstapTab() {
            return $('#dnstap').filter('.active').length > 0;
        }

        function isDomainsTab() {
            return $('#domains').filter('.active').length > 0;
        }

        var dnstapExtraBlocked = [];
        var dnstapExtraUnblocked = [];
        var dnstapExtrasDirty = false;
        var dnstapConfCache = [];
        var dnstapBlockedUrlsCache = [];
        var dnstapUnblockedUrlsCache = [];
        var domainsListKind = 'blocked';

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
            var blockedUrls = dnstapCollectKv($('#dnstapBlockedUrlsKv'));
            if (!$('#dnstapBlockedUrlsKv input').length && dnstapBlockedUrlsCache.length) {
                blockedUrls = dnstapBlockedUrlsCache;
            }
            var unblockedUrls = dnstapCollectKv($('#dnstapUnblockedUrlsKv'));
            if (!$('#dnstapUnblockedUrlsKv input').length && dnstapUnblockedUrlsCache.length) {
                unblockedUrls = dnstapUnblockedUrlsCache;
            }
            return {
                conf: JSON.stringify(conf),
                blocked: JSON.stringify(dnstapDomainsToRows(dnstapExtraBlocked)),
                blocked_urls: JSON.stringify(blockedUrls),
                unblocked: JSON.stringify(dnstapDomainsToRows(dnstapExtraUnblocked)),
                unblocked_urls: JSON.stringify(unblockedUrls)
            };
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
                'bgp.blocked_communities': '{{ lang._("Blocked communities") }}',
                'bgp.unblocked_communities': '{{ lang._("Unblocked communities") }}'
            };
            return map[key] || key;
        }

        function dnstapConfHelp(key) {
            var map = {
                ttl: '{{ lang._("How long advertised BGP prefixes stay in the dnstap-bgp cache (Go duration, e.g. 24h).") }}',
                ipv6: '{{ lang._("Enable IPv6 AFI in dnstap-bgp and the ipv6 channel on the BIRD dnstap peer.") }}',
                'bgp.peers': '{{ lang._("BIRD neighbor address (host side of the dnstap iBGP session).") }}',
                'bgp.sourceIP': '{{ lang._("dnstap-bgp source address (jail / DNStap side of the iBGP session).") }}',
                'bgp.blocked_communities': '{{ lang._("Fixed BGP community on blocked prefixes (local AS:777). Not editable.") }}',
                'bgp.unblocked_communities': '{{ lang._("Fixed BGP community on unblocked prefixes (local AS:555). Not editable.") }}'
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
                if (key === 'bgp.blocked_communities' || key === 'bgp.unblocked_communities') {
                    $inp.prop('readonly', true).attr('tabindex', '-1')
                        .css({'cursor': 'default'});
                }
                $val.append($inp);
            }
            $val.append(dnstapHelpBlock(hid, help));
            $tr.append($val);
            return $tr;
        }

        function dnstapKvRow(key, value, removable, delClass) {
            var $tr = $('<tr/>');
            var $inp = $('<input type="text" class="form-control"/>')
                .attr('data-key', key)
                .val(value == null ? '' : String(value));
            var $edit = $('<div class="dnstap-row-edit"/>').append($inp);
            var $add = $('<button type="button" class="btn btn-xs btn-primary dnstap-list-add"/>')
                .html('<span class="fa fa-fw fa-plus"></span> {{ lang._("Add") }}');
            $edit.append($add);
            if (removable) {
                var $del = $('<button type="button" class="btn btn-xs btn-default ' + (delClass || 'dnstap-domain-del') + '"/>')
                    .html('<span class="fa fa-fw fa-minus"></span> {{ lang._("Remove") }}');
                $edit.append($del);
            }
            $tr.append($('<td/>').append($edit));
            return $tr;
        }

        function dnstapFillKv($tbody, rows, removable, delClass) {
            $tbody.empty();
            (rows || []).forEach(function (row) {
                $tbody.append(dnstapKvRow(row.key || '', row.value || '', !!removable, delClass));
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

        function dnstapFillOrEmpty($tbody, rows, key, delClass) {
            dnstapFillKv($tbody, rows || [], true, delClass);
            if ($tbody.find('tr').length === 0) {
                $tbody.append(dnstapKvRow(key, '', true, delClass));
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
                dnstapSetCount($('#dnstapBlockedCount'), data.blocked_count || data.domains_count);
                dnstapSetCount($('#dnstapUnblockedCount'), data.unblocked_count);
                (function () {
                    var $tbody = $('#dnstapConfKv');
                    $tbody.empty();
                    (data.conf || []).forEach(function (row) {
                        $tbody.append(dnstapConfRow(row.key || '', row.value));
                    });
                })();
                dnstapFillOrEmpty($('#dnstapBlockedUrlsKv'), data.blocked_urls || data.urls, 'url', 'dnstap-blocked-url-del');
                dnstapFillOrEmpty($('#dnstapUnblockedUrlsKv'), data.unblocked_urls, 'url', 'dnstap-unblocked-url-del');
                dnstapConfCache = dnstapCollectKv($('#dnstapConfKv'));
                dnstapBlockedUrlsCache = dnstapCollectKv($('#dnstapBlockedUrlsKv'));
                dnstapUnblockedUrlsCache = dnstapCollectKv($('#dnstapUnblockedUrlsKv'));
                if (!dnstapExtrasDirty) {
                    dnstapExtraBlocked = dnstapRowsToDomains(data.blocked_extra || data.blocked || data.domains);
                    dnstapExtraUnblocked = dnstapRowsToDomains(data.unblocked_extra || data.unblocked);
                }
            });
        }

        function setApplyEndpoint() {
            var endpoint = '/api/xray/service/reconfigure';
            if (isBgpRoutingTab()) {
                endpoint = '/api/xray/service/bgpwrite';
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

        $(document).on('click', '.dnstap-list-add', function () {
            var $tbody = $(this).closest('tbody');
            var key = String($tbody.attr('data-row-key') || 'url');
            var delClass = String($tbody.attr('data-del-class') || 'dnstap-domain-del');
            $(this).closest('tr').after(dnstapKvRow(key, '', true, delClass));
        });
        $(document).on('click', '#dnstap .dnstap-blocked-url-del, #dnstap .dnstap-blocked-del, #dnstap .dnstap-unblocked-url-del, #dnstap .dnstap-unblocked-del', function () {
            var $tbody = $(this).closest('tbody');
            var key = String($tbody.attr('data-row-key') || 'url');
            var delClass = String($tbody.attr('data-del-class') || 'dnstap-domain-del');
            $(this).closest('tr').remove();
            if ($tbody.find('tr').length === 0) {
                $tbody.append(dnstapKvRow(key, '', true, delClass));
            }
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
        function dnstapExtraAdd(kind) {
            var $inp = kind === 'unblocked' ? $('#domainsUnblockedInput') : $('#domainsBlockedInput');
            var d = dnstapNormalizeDomain($inp.val());
            if (d === '') {
                alert('{{ lang._("Enter a valid domain name.") }}');
                return;
            }
            var list = kind === 'unblocked' ? dnstapExtraUnblocked : dnstapExtraBlocked;
            if (list.indexOf(d) === -1) {
                list.push(d);
            }
            dnstapExtrasDirty = true;
            $inp.val(d);
        }

        function dnstapExtraRemove(kind) {
            var $inp = kind === 'unblocked' ? $('#domainsUnblockedInput') : $('#domainsBlockedInput');
            var d = dnstapNormalizeDomain($inp.val());
            if (kind === 'unblocked') {
                dnstapExtraUnblocked = dnstapExtraUnblocked.filter(function (x) { return x !== d; });
            } else {
                dnstapExtraBlocked = dnstapExtraBlocked.filter(function (x) { return x !== d; });
            }
            dnstapExtrasDirty = true;
            $inp.val('');
        }

        function dnstapRenderDomainList(filter) {
            var list = domainsListKind === 'unblocked' ? dnstapExtraUnblocked : dnstapExtraBlocked;
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
                $tr.on('click', function () {
                    var $inp = domainsListKind === 'unblocked' ? $('#domainsUnblockedInput') : $('#domainsBlockedInput');
                    $inp.val(d);
                    $('#domainsListModal').modal('hide');
                });
                $tb.append($tr);
            });
            $('#domainsListCount').text(shown + ' / ' + list.length);
        }

        function dnstapOpenDomainList(kind) {
            domainsListKind = kind;
            $('#domainsListModalTitle').text(kind === 'unblocked'
                ? '{{ lang._("Unblocked domains") }}'
                : '{{ lang._("Blocked domains") }}');
            $('#domainsListFilter').val('');
            dnstapRenderDomainList('');
            $('#domainsListModal').modal('show');
        }

        $(document).on('click', '#domainsBlockedAdd', function () { dnstapExtraAdd('blocked'); });
        $(document).on('click', '#domainsUnblockedAdd', function () { dnstapExtraAdd('unblocked'); });
        $(document).on('click', '#domainsBlockedRemove', function () { dnstapExtraRemove('blocked'); });
        $(document).on('click', '#domainsUnblockedRemove', function () { dnstapExtraRemove('unblocked'); });
        $(document).on('click', '#domainsBlockedSearch', function () { dnstapOpenDomainList('blocked'); });
        $(document).on('click', '#domainsUnblockedSearch', function () { dnstapOpenDomainList('unblocked'); });
        $(document).on('input', '#domainsListFilter', function () {
            dnstapRenderDomainList($(this).val());
        });
        $('#domainsBlockedInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                dnstapExtraAdd('blocked');
            }
        });
        $('#domainsUnblockedInput').on('keydown', function (e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                dnstapExtraAdd('unblocked');
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
                if (isBgpRoutingTab()) {
                    openRoutingPeersStatus();
                }
                if (isDnstapTab() || isDomainsTab()) {
                    loadDnstapConf();
                }
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
