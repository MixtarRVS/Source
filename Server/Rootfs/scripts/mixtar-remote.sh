#!/System/Tools/Current/bin/sh
set -u

PROFILE=${MIXTAR_REMOTE_PROFILE:-/System/Config/RemoteAccess/current.remote}
MIXTAR_SERVICE=${MIXTAR_SERVICE:-/System/SystemTools/mixtar-service}
MIXTAR_NETWORK=${MIXTAR_NETWORK:-/System/SystemTools/mixtar-network}
SSHD=${MIXTAR_SSHD:-/usr/sbin/sshd}
SSH_KEYGEN=${MIXTAR_SSH_KEYGEN:-/usr/bin/ssh-keygen}
NETSTAT=${MIXTAR_NETSTAT:-/bin/netstat}

usage() {
	cat >&2 <<EOF
usage: mixtar-remote <command>

commands:
  contract
  check
  status
  profile
  config
  keys
  listeners
  backend
EOF
}

field() {
	key=$1
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROFILE"
}

profile_path() {
	field "$1"
}

configured_port() {
	config=$(profile_path sshd_config)
	awk '
		$1 ~ /^#/ { next }
		tolower($1) == "port" { print $2; found = 1; exit }
		END { if (!found) print "22" }
	' "$config" 2>/dev/null
}

authorized_keys_file() {
	profile_path authorized_keys
}

contract() {
	cat <<EOF
MixtarRVS remote access policy contract:
  profile: $PROFILE
  transport: ssh
  backend: OpenSSH sshd
  service status: $MIXTAR_SERVICE status sshd
  network status: $MIXTAR_NETWORK check
  config: /etc/ssh/sshd_config
  keys: authorized_keys fingerprints only

Implemented:
  check
  status
  profile
  config
  keys
  listeners
  backend

Not implemented yet:
  adding/removing keys
  rewriting sshd_config
  restarting sshd
  replacing OpenSSH
  native Mixtar remote agent
EOF
}

show_profile() {
	cat "$PROFILE"
}

show_config() {
	config=$(profile_path sshd_config)
	echo "config=$config"
	if [ ! -f "$config" ]; then
		echo "config_status=missing"
		return 1
	fi
	awk '
		$1 ~ /^#/ { next }
		tolower($1) == "port" { print "Port=" $2; found_port = 1 }
		tolower($1) == "listenaddress" { print "ListenAddress=" $2 }
		tolower($1) == "passwordauthentication" { print "PasswordAuthentication=" $2 }
		tolower($1) == "pubkeyauthentication" { print "PubkeyAuthentication=" $2 }
		tolower($1) == "permitrootlogin" { print "PermitRootLogin=" $2 }
		tolower($1) == "authorizedkeysfile" {
			for (i = 2; i <= NF; i++) {
				printf "%s%s", i == 2 ? "AuthorizedKeysFile=" : " ", $i
			}
			printf "\n"
		}
		END {
			if (!found_port) {
				print "Port=22"
			}
		}
	' "$config"
}

show_keys() {
	auth=$(authorized_keys_file)
	echo "authorized_keys=$auth"
	if [ ! -f "$auth" ]; then
		echo "authorized_keys_status=missing"
		return 1
	fi
	awk 'END { print "authorized_keys_count=" NR + 0 }' "$auth"
	if [ -x "$SSH_KEYGEN" ]; then
		"$SSH_KEYGEN" -lf "$auth" 2>/dev/null | awk '{ print "authorized_key_fingerprint=" $0 }'
	else
		echo "ssh-keygen=missing"
	fi
}

show_listeners() {
	port=$(configured_port)
	echo "port=$port"
	awk -v port="$port" '
		BEGIN { hex = sprintf("%04X", port + 0) }
		NR > 1 {
			split($2, addr, ":")
			if (toupper(addr[2]) == hex && $4 == "0A") {
				print "listener=" FILENAME " local=" $2 " state=LISTEN"
				found = 1
			}
		}
		END {
			if (!found) {
				print "listener=missing"
			}
		}
	' /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

show_backend() {
	awk -F= '
		$1 == "transport" { print "transport=" $2 }
		$1 == "backend" { print "backend=" $2 }
		$1 == "service" { print "service=" $2 }
		$1 == "network_profile" { print "network_profile=" $2 }
		$1 == "host" { print "host=" $2 }
		$1 == "port" { print "profile_port=" $2 }
		$1 == "user" { print "user=" $2 }
		$1 == "auth_mode" { print "auth_mode=" $2 }
	' "$PROFILE"
	if [ -x "$SSHD" ]; then
		echo "sshd=$SSHD"
	else
		echo "sshd=missing"
	fi
	if [ -x "$SSH_KEYGEN" ]; then
		echo "ssh-keygen=$SSH_KEYGEN"
	else
		echo "ssh-keygen=missing"
	fi
}

status() {
	echo "profile=$PROFILE"
	awk -F= '
		$1 == "host" { print "host=" $2 }
		$1 == "port" { print "profile_port=" $2 }
		$1 == "user" { print "user=" $2 }
		$1 == "auth_mode" { print "auth_mode=" $2 }
		$1 == "service" { print "service=" $2 }
		$1 == "network_profile" { print "network_profile=" $2 }
	' "$PROFILE"
	echo "configured_port=$(configured_port)"
	if [ -x "$MIXTAR_SERVICE" ]; then
		"$MIXTAR_SERVICE" status sshd 2>/dev/null | awk 'NR == 1 { print "service_status=" $0; found = 1 } END { if (!found) print "service_status=missing" }'
	else
		echo "service_status=mixtar-service missing"
	fi
	if [ -x "$MIXTAR_NETWORK" ]; then
		"$MIXTAR_NETWORK" check 2>/dev/null | awk 'NR == 1 { print "network_status=" $0; found = 1 } END { if (!found) print "network_status=missing" }'
	else
		echo "network_status=mixtar-network missing"
	fi
	show_keys
}

check() {
	rc=0
	if [ ! -f "$PROFILE" ]; then
		echo "missing profile: $PROFILE" >&2
		return 1
	fi
	for tool in "$SSHD" "$SSH_KEYGEN" "$MIXTAR_SERVICE" "$MIXTAR_NETWORK"; do
		if [ ! -x "$tool" ]; then
			echo "missing tool: $tool" >&2
			rc=1
		fi
	done
	auth=$(authorized_keys_file)
	if [ ! -s "$auth" ]; then
		echo "missing authorized_keys or no keys: $auth" >&2
		rc=1
	fi
	if [ -x "$MIXTAR_SERVICE" ]; then
		if ! "$MIXTAR_SERVICE" status sshd >/dev/null 2>&1; then
			echo "sshd service is not healthy" >&2
			rc=1
		fi
	fi
	if [ -x "$MIXTAR_NETWORK" ]; then
		if ! "$MIXTAR_NETWORK" check >/dev/null 2>&1; then
			echo "network profile is not healthy" >&2
			rc=1
		fi
	fi
	port=$(configured_port)
	if ! awk -v port="$port" '
		BEGIN { hex = sprintf("%04X", port + 0) }
		NR > 1 {
			split($2, addr, ":")
			if (toupper(addr[2]) == hex && $4 == "0A") {
				found = 1
			}
		}
		END { exit found ? 0 : 1 }
	' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
		echo "ssh listener not observed" >&2
		rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		user=$(field user)
		host=$(field host)
		port=$(configured_port)
		echo "ok remote=ssh user=$user host=$host port=$port backend=openssh"
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
	config)
		show_config
		;;
	keys)
		show_keys
		;;
	listeners)
		show_listeners
		;;
	backend)
		show_backend
		;;
	*)
		usage
		exit 2
		;;
esac
