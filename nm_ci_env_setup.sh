#!/bin/bash

VETH_COUNT=9
INTERNAL_BR="inbr"
DHCP_SRV_NIC="masq"
DHCP_SRV_EP_NIC="masqp"
DHCP_IP_BLOCK="192.0.2"
DHCP_SRV_IP="${DHCP_IP_BLOCK}.1"
NETNS="vethsetup"
DNSMASQ_PID_FILE="/tmp/dhcp_inbr.pid"

function clean_up() {
    for X in $(seq 1 $VETH_COUNT); do
        ip link del eth${X}
    done
    ip netns exec $NETNS ip link del $INTERNAL_BR
    ip netns exec $NETNS ip link del $DHCP_SRV_NIC
    ip netns exec $NETNS kill `cat $DNSMASQ_PID_FILE`
    ip netns del $NETNS
}

function create_netns {
    ip netns add $NETNS
}

function start_dhcp_server() {
    ip netns exec $NETNS ip link add $DHCP_SRV_NIC \
        type veth peer name $DHCP_SRV_EP_NIC
    ip netns exec $NETNS ip link set $DHCP_SRV_EP_NIC master $INTERNAL_BR
    ip netns exec $NETNS ip link set $DHCP_SRV_EP_NIC \
        type bridge_slave priority 0
    ip netns exec $NETNS ip link set $DHCP_SRV_EP_NIC up
    ip netns exec $NETNS ip link set $DHCP_SRV_NIC up
    ip netns exec $NETNS ip addr add ${DHCP_SRV_IP}/24 dev $DHCP_SRV_NIC
    ip netns exec $NETNS dnsmasq \
        --pid-file=$DNSMASQ_PID_FILE \
        --dhcp-leasefile=/tmp/dhcp_inbr.lease \
        --listen-address=$DHCP_SRV_IP \
        --dhcp-range=${DHCP_IP_BLOCK}.10,${DHCP_IP_BLOCK}.254,240 \
        --interface=$DHCP_SRV_NIC \
        --bind-interfaces
}

function create_internal_bridge() {
    ip netns exec $NETNS ip link add name $INTERNAL_BR \
        type bridge forward_delay 0 stp_state 1

    # Set best prirority to this bridge
    ip netns exec $NETNS ip link set $INTERNAL_BR type bridge priority 0
    ip netns exec $NETNS ip link set $INTERNAL_BR up
}

function create_veth_and_attach_bridge() {
    for X in $(seq 1 $VETH_COUNT); do
        ip link add eth${X} type veth peer name eth${X}p
        ip link set eth${X}p netns $NETNS
        ip netns exec $NETNS ip link set eth${X}p master $INTERNAL_BR
        # 'worse' priority to ports coming to simulated ethernet devices
        ip netns exec $NETNS ip link set eth${X}p type bridge_slave priority 5
        ip netns exec $NETNS ip link set eth${X}p up
        ip link set eth${X} up
        nmcli device set eth${X} managed yes
    done
}


if [ "CHK$1" == "CHK1" ];then
    clean_up
else
    create_netns
    create_internal_bridge
    create_veth_and_attach_bridge
    start_dhcp_server
fi
