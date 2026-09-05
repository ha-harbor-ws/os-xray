filter accept_antifilter_network_v6 {
    if bgp_community ~ ANTIFILTER_NETWORK then {
       if net = ::/0 then reject;
       ifname = ACTIVE_TUN6_IF;
       accept;
    }
    reject;
}
