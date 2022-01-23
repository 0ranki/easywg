#!/bin/bash

## TODO: flags instead of config file
## TODO: deleting clients

if [[ "$UID" -ne 0 ]]; then
    echo "This script needs root permissions to run."
    exit 1
fi

MISSED_REQS=()
for command in bc wg curl qrencode; do
    if ! command -v $command > /dev/null; then
        MISSED_REQS+=("$command")
    fi
done
if [[ ${#MISSED_REQS[@]} -ne 0 ]]; then
    echo "This script requires you to install the"
    echo "following dependencies:"
    echo "${MISSED_REQS[@]}"
    exit 1
fi

## Read user overrides
[ -f "/etc/easywg.conf" ] && . /etc/easywg.conf
[ -f "./easywg.conf" ] && . ./easywg.conf

umask 077

function usage() {
    printf "Usage: $0 split|full interface\n"
    printf "No support for subnets larger than /24\n"
    printf "(254 usable addresses) yet\n"
    exit
}

## Detect values
[ -z "$CLIENT_CONF_DIR" ] && CLIENT_CONF_DIR=/etc/wireguard/clients
[ ! -d "$CLIENT_CONF_DIR" ] && mkdir -p "$CLIENT_CONF_DIR"

INTERFACE=$2
[ -z "$SERVER_IP" ] && SERVER_IP=$(curl -4 -s http://ifconfig.co)
[ -z "$PORT" ] && PORT=$(wg show $INTERFACE | grep 'listening port:' | sed 's/^.*: //')
IP4="$(ip -4 a show $INTERFACE | grep inet | sed 's/^ *//' | awk '{print $2}')" #IPv4 CIDR for server
IP6="$(ip -6 a show $INTERFACE | grep inet | sed 's/^ *//' | awk '{print $2}' | head -1)" #IPv6 CIDR for server
SERVER_ADDR4=${IP4%/*}  #remove CIDR subnet size, 10.0.0.0
SERVER_ADDR6=${IP6%/*}
PREFIX4=${IP4%.*}       #prefix, 10.0.0
PREFIX6=${IP6%:*}       #prefix, fd00:
SUBNET4=${IP4##*/}      #subnet CIDR size, 24
SUBNET6=${IP6##*/}      #subner CIDR size, 112
SERVER_KEY=$(wg show $INTERFACE | grep public | sed 's/.*: //') #Get server public key
PRIVKEY=$(wg genkey) #Generate client keys
PUBKEY=$(echo $PRIVKEY | wg pubkey)
SERVER_N=${SERVER_ADDR4##*.} #Last part of IPv4 address
N_ADDRESSES=$(echo "2^(32-$SUBNET4)" | bc) #Number of addresses in subnet (IPv4)
[ ! -z $DNS ] && DNSSTR="\nDNS = ${DNS}" #Get DNS from user conf
[ ! -z $MTU ] && MTUSTR="\nMTU = ${MTU}" #Get MTU from user conf
[ ! -z $KEEPALIVE ] && KEEPALIVESTR="\nPersistentKeepAlive = ${KEEPALIVE}" #Get PersistentKeepAlive from user conf

## Calculate the first address in the subnet, not necessarily the server address
SUBNET_FIRST=0
while [ $(( $SUBNET_FIRST + $N_ADDRESSES - $SERVER_N )) -lt 0 ]; do
    SUBNET_FIRST=$(( $SUBNET_FIRST + $N_ADDRESSES ))
done
SUBNET_LAST=$(( $SUBNET_FIRST + $N_ADDRESSES - 1 ))

## Last usable client address, calculated or from user conf
if [ -z $LAST_CLIENT_ADDR ]; then
    MAX_CLIENT_N=$(( ${SUBNET_LAST} - 1 ))
else
    MAX_CLIENT_N=${LAST_CLIENT_ADDR##*.}
    [[ "$MAX_CLIENT_N" -ge "$SUBNET_LAST" ]] && MAX_CLIENT_N=$(( $SUBNET_LAST - 1 ))
fi

## Check correct CLI arguments, no support for subnets larger than /24 yet
## TODO: Support for larger subnets
[ "$#" -ne 2 ] && usage
[ "$SUBNET4" -lt 24 ] && usage

## Generate allowed IPs
if [[ "$1" == "split" ]]; then
	ALLOWED_IPS=${PREFIX4}.${SUBNET_FIRST}/${SUBNET4},${PREFIX6}:0/${SUBNET6}
    if [[ ! -z "$ADDN_ALLOWED_IPS" ]]; then
        ALLOWED_IPS=${ALLOWED_IPS},${ADDN_ALLOWED_IPS}
    fi
elif [[ "$1" == "full" ]]; then
	ALLOWED_IPS=0.0.0.0/0,::/0
else
    usage
fi

shopt -s nullglob

## If using sequential IP addresses, get the next free IP address
if [[ "$SEQUENTIAL_IPS" == "true" ]]; then
    for (( ip = $SUBNET_FIRST + 1 ; ip < $SUBNET_LAST ; ip++ )); do
        echo $PREFIX4.$ip
        if [[ "$ip" -ne "$SERVER_N" ]]; then
            if ! wg show $INTERFACE | grep -q "${PREFIX4}.${ip}"; then
                N_CLIENT4=$ip
                break
            fi
        fi
    done
    echo $PREFIX4.$ip
    exit
## Get a random available address
elif [ -z "$CLIENT_IP4" ]; then
    while [[ ! "$DONE" ]]; do
        N_CLIENT4=$(( $SERVER_N + $RANDOM % (( $MAX_CLIENT_N - $SERVER_N )) ))
        # Check that a peer with the same address does not exist
        if ! wg show $INTERFACE | grep -q "${PREFIX4}.${N_CLIENT4}"; then
            # The address can't be the first or the last in the subnet,
            # or the server's WG address
            [[ "$N_CLIENT4" -ne "$SUBNET_FIRST" ]] && [[ "$N_CLIENT4" -ne "$SUBNET_LAST" ]] \
                && [[ "$N_CLIENT4" -ne "$SERVER_N" ]]  && DONE=true
        fi
    done
else ## Or read client addresses from conf file
    N_CLIENT4=${CLIENT_IP4##*.}
    if [[ "$N_CLIENT4" -eq "$N_SERVER" ]]; then
        echo "The client cannot have the same address as the server."
        exit 1
    fi
fi

## If client IPv6 not set in conf file, use the same suffix as for IPv4
## (simple solution)
## TODO: better IPv6 handling

if [ -z "$CLIENT_IP6" ]; then
    N_CLIENT6=$N_CLIENT4
else
    N_CLIENT6=${CLIENT_IP6##*:}
fi

## If run with DEBUG=1 ./easywg.sh, print debug output
if [ ! -z "$DEBUG" ]; then
    echo server ip: $SERVER_IP
    echo port: $PORT
    echo IP4: $IP4
    echo IP6: $IP6
    echo SERVER_ADDR4: $SERVER_ADDR4
    echo SERVER_ADDR6: $SERVER_ADDR6
    echo SUBNET4: $SUBNET4
    echo SUBNET6: $SUBNET6
    echo PREFIX4: $PREFIX4
    echo PREFIX6: $PREFIX6
    echo INTERFACE: $INTERFACE
    echo SERVER_N: $SERVER_N
    echo N_ADDRESSES: $N_ADDRESSES
    echo N_CLIENT4: $N_CLIENT4
    echo N_CLIENT6: $N_CLIENT6
    echo SUBNET_FIRST: $SUBNET_FIRST
    echo SUBNET_LAST: $SUBNET_LAST
    echo MAX_CLIENT_N: $MAX_CLIENT_N
    echo CLIENT_CONF_DIR: $CLIENT_CONF_DIR
    echo DNSSTR: $DNSSTR
    echo MTUSTR: $MTUSTR
    echo ALLOWED_IPS: $ALLOWED_IPS
    echo KEEPALIVESTR: $KEEPALIVESTR
    read -p 'q to quit'
    [ "$REPLY" == "q" ] && exit 1
fi
unset $REPLY

printf "\nGenerating client ${PREFIX4}.${N_CLIENT4}/$SUBNET4, ${PREFIX6}:${N_CLIENT6}/$SUBNET6\n\n"

## Create the actual WG client configuration
printf "[Interface]
PrivateKey = ${PRIVKEY}
Address = ${PREFIX4}.${N_CLIENT4}/${SUBNET4}
Address = ${PREFIX6}:${N_CLIENT6}/${SUBNET6}${MTUSTR}${DNSSTR}

[Peer]
PublicKey = ${SERVER_KEY}
Endpoint = ${SERVER_IP}:${PORT}
AllowedIPs = ${ALLOWED_IPS}${KEEPALIVESTR}
" > ${CLIENT_CONF_DIR}/client_${N_CLIENT4}.conf

## Show a QR code to scan for mobile devices
qrencode -t ansiutf8 < ${CLIENT_CONF_DIR}/client_${N_CLIENT4}.conf

read -p "Show config (y/n)? " -n1
printf "\n"
[[ "$REPLY" == "y" ]] && cat ${CLIENT_CONF_DIR}/client_${N_CLIENT4}.conf
unset $REPLY

## Add peer keys to the WG network and IPv4 route for the newly generated client
read -p "Add peer now (y/n)? " -n1
printf "\n"
if [[ "$REPLY" == "y" ]]; then
	wg set ${INTERFACE} peer ${PUBKEY} allowed-ips ${PREFIX4}.${N_CLIENT4}/32,${PREFIX6}:${N_CLIENT4}/128
	ip -4 r add ${PREFIX4}.${N_CLIENT4} dev ${INTERFACE} scope link
fi
unset $REPLY

printf "For security reasons it is best not to store the client configs with private keys.\n"
printf "If you answer anything other than 'yes', the file will be deleted."
read -p "Keep configuration file (answer 'yes' to keep)? "
printf "\n"
if [[ "$REPLY" != "yes" ]]; then
    rm -f ${CLIENT_CONF_DIR}/client_${N_CLIENT4}.conf
fi
unset $REPLY

printf "\n"
