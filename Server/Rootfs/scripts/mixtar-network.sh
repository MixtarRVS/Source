#!/System/Tools/Current/bin/sh
set -u

PROFILE=${MIXTAR_NETWORK_PROFILE:-/System/Config/Network/current.network}
IP=${MIXTAR_IP:-/sbin/ip}
IWCTL=${MIXTAR_IWCTL:-/usr/bin/iwctl}
MIXTAR_SERVICE=${MIXTAR_SERVICE:-/System/SystemTools/mixtar-service}
RESOLV_CONF=${MIXTAR_RESOLV_CONF:-/etc/resolv.conf}

usage() {
	cat >&2 <<EOF
usage: mixtar-network <command>

commands:
  contract
  check
  status
  profile
  interfaces
  routes
  dns
  wifi
  backend
EOF
}

field() {
	key=$1
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROFILE"
}

primary_interface() {
	field interface
}

contract() {
	cat <<EOF
MixtarRVS network profile contract:
  profile: $PROFILE
  interface status: $IP addr
  route status: $IP route
  DNS status: $RESOLV_CONF
  service status: $MIXTAR_SERVICE status network|wifi|sshd

Current backend policy:
  dhcp backend: dhcpcd
  wifi backend: iwd
  wifi cli: iwctl
  remote access: sshd

Implemented:
  check
  status
  profile
  interfaces
  routes
  dns
  wifi
  backend

Not implemented yet:
  applying network profiles
  changing Wi-Fi credentials
  replacing dhcpcd
  replacing iwd
  native network daemon
EOF
}

show_profile() {
	cat "$PROFILE"
}

show_interfaces() {
	"$IP" addr
}

show_routes() {
	"$IP" route
}

show_dns() {
	cat "$RESOLV_CONF"
}

show_backend() {
	awk -F= '
		$1 == "interface" { print "interface=" $2 }
		$1 == "addressing" { print "addressing=" $2 }
		$1 == "dhcp_backend" { print "dhcp_backend=" $2 }
		$1 == "wifi_backend" { print "wifi_backend=" $2 }
		$1 == "wifi_cli" { print "wifi_cli=" $2 }
		$1 == "dns_source" { print "dns_source=" $2 }
		$1 == "route_source" { print "route_source=" $2 }
		$1 == "remote_access" { print "remote_access=" $2 }
	' "$PROFILE"
	if [ -x /sbin/dhcpcd ]; then
		echo 'dhcpcd=/sbin/dhcpcd'
	else
		echo 'dhcpcd=missing'
	fi
	if [ -x /usr/bin/iwctl ]; then
		echo 'iwctl=/usr/bin/iwctl'
	else
		echo 'iwctl=missing'
	fi
	if [ -x /usr/sbin/sshd ]; then
		echo 'sshd=/usr/sbin/sshd'
	else
		echo 'sshd=missing'
	fi
}

show_wifi() {
	iface=$(primary_interface)
	printf 'interface=%s\n' "$iface"
	if [ -x "$IWCTL" ]; then
		"$IWCTL" device list 2>/dev/null || true
		"$IWCTL" station "$iface" show 2>/dev/null || true
	else
		printf 'iwctl=missing\n'
	fi
}

service_line() {
	name=$1
	label=$2
	if [ -x "$MIXTAR_SERVICE" ]; then
		"$MIXTAR_SERVICE" status "$name" 2>/dev/null | awk -v label="$label" 'NR == 1 { print label "=" $0; found = 1 } END { if (!found) print label "=missing" }'
	else
		printf '%s=service backend missing\n' "$label"
	fi
}

status() {
	iface=$(primary_interface)
	printf 'profile=%s\n' "$PROFILE"
	awk -F= '$1 == "interface" { print "interface=" $2; found = 1; exit } END { if (!found) print "interface=missing" }' "$PROFILE"
	"$IP" addr show "$iface" 2>/dev/null | awk '/ inet / { print "ipv4=" $2; found = 1; exit } END { if (!found) print "ipv4=missing" }'
	"$IP" route 2>/dev/null | awk '/^default / { print "default_route=" $0; found = 1; exit } END { if (!found) print "default_route=missing" }'
	awk '/^nameserver / { print "dns=" $2; found = 1; exit } END { if (!found) print "dns=missing" }' "$RESOLV_CONF" 2>/dev/null
	service_line network network_service
	service_line wifi wifi_service
	service_line sshd remote_service
}

check() {
	rc=0
	if [ ! -f "$PROFILE" ]; then
		printf 'missing profile: %s\n' "$PROFILE" >&2
		return 1
	fi
	if [ ! -x "$IP" ]; then
		printf 'missing ip tool: %s\n' "$IP" >&2
		rc=1
	fi
	if [ ! -x "$MIXTAR_SERVICE" ]; then
		printf 'missing mixtar-service: %s\n' "$MIXTAR_SERVICE" >&2
		rc=1
	fi
	iface=$(primary_interface)
	if [ -z "$iface" ]; then
		printf 'profile missing interface\n' >&2
		rc=1
	else
		if ! "$IP" link show "$iface" >/dev/null 2>&1; then
			printf 'missing interface: %s\n' "$iface" >&2
			rc=1
		fi
		if ! "$IP" addr show "$iface" 2>/dev/null | grep -q ' inet '; then
			printf 'missing IPv4 address on %s\n' "$iface" >&2
			rc=1
		fi
	fi
	if ! "$IP" route 2>/dev/null | grep -q '^default '; then
		printf 'missing default route\n' >&2
		rc=1
	fi
	if ! grep -q '^nameserver ' "$RESOLV_CONF" 2>/dev/null; then
		printf 'missing DNS nameserver\n' >&2
		rc=1
	fi
	if [ -x "$MIXTAR_SERVICE" ]; then
		for svc in network wifi sshd; do
			if ! "$MIXTAR_SERVICE" status "$svc" >/dev/null 2>&1; then
				printf 'service not healthy: %s\n' "$svc" >&2
				rc=1
			fi
		done
	fi
	if [ "$rc" -eq 0 ]; then
		printf 'ok profile=current interface=%s backend=dhcpcd+iwd remote=sshd\n' "$iface"
	fi
	return "$rc"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	check)
		check
		;;
	status)
		status
		;;
	profile)
		show_profile
		;;
	interfaces)
		show_interfaces
		;;
	routes)
		show_routes
		;;
	dns)
		show_dns
		;;
	wifi)
		show_wifi
		;;
	backend)
		show_backend
		;;
	*)
		usage
		exit 2
		;;
esac
