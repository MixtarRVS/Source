#!/System/Tools/Current/bin/sh
set -u

SERVICE_DIR=${MIXTAR_SERVICE_DIR:-/System/Config/Services}
RC_SERVICE=${MIXTAR_RC_SERVICE:-/sbin/rc-service}
RC_STATUS=${MIXTAR_RC_STATUS:-/bin/rc-status}

usage() {
	cat >&2 <<EOF
usage: mixtar-service <command> [service]

commands:
  contract
  check
  list
  status <service>
  start <service>
  stop <service>
EOF
}

field() {
	file=$1
	key=$2
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

manifest_for() {
	name=$1
	if [ -f "$SERVICE_DIR/$name.service" ]; then
		printf '%s/%s.service\n' "$SERVICE_DIR" "$name"
		return 0
	fi
	for base in $(ls "$SERVICE_DIR" 2>/dev/null); do
		case "$base" in
			*.service) ;;
			*) continue ;;
		esac
		file="$SERVICE_DIR/$base"
		[ -f "$file" ] || continue
		value=$(field "$file" name)
		if [ "$value" = "$name" ]; then
			printf '%s\n' "$file"
			return 0
		fi
	done
	return 1
}

backend_name_for() {
	file=$1
	name=$(field "$file" backend_name)
	if [ -z "$name" ]; then
		name=$(field "$file" name)
	fi
	printf '%s\n' "$name"
}

ensure_openrc_backend() {
	file=$1
	backend=$(field "$file" backend)
	if [ "$backend" != "openrc" ]; then
		printf 'unsupported backend for %s: %s\n' "$(field "$file" name)" "$backend" >&2
		return 1
	fi
	if [ ! -x "$RC_SERVICE" ]; then
		printf 'missing rc-service backend: %s\n' "$RC_SERVICE" >&2
		return 1
	fi
	return 0
}

contract() {
	cat <<EOF
MixtarRVS service runner contract:
  manifests: $SERVICE_DIR/*.service
  current backend: OpenRC
  backend tools: $RC_SERVICE, $RC_STATUS

Implemented:
  list
  status <service>
  start <service>
  stop <service>
  check

Not native yet:
  PID 1 ownership
  ordered dependency solver
  restart policy
  log capture
  shutdown hooks
  native service supervision

Policy:
  MixtarRVS owns the service interface.
  OpenRC remains an explicit compatibility backend until replaced.
EOF
}

check_manifest() {
	file=$1
	rc=0
	for key in name role backend backend_name runlevel enabled; do
		value=$(field "$file" "$key")
		if [ -z "$value" ]; then
			printf 'manifest missing %s: %s\n' "$key" "$file" >&2
			rc=1
		fi
	done
	backend=$(field "$file" backend)
	if [ -n "$backend" ] && [ "$backend" != "openrc" ]; then
		printf 'manifest unsupported backend %s: %s\n' "$backend" "$file" >&2
		rc=1
	fi
	return "$rc"
}

check_all() {
	rc=0
	if [ ! -d "$SERVICE_DIR" ]; then
		printf 'missing service directory: %s\n' "$SERVICE_DIR" >&2
		return 1
	fi
	if [ ! -x "$RC_SERVICE" ]; then
		printf 'missing rc-service backend: %s\n' "$RC_SERVICE" >&2
		rc=1
	fi
	if [ ! -x "$RC_STATUS" ]; then
		printf 'missing rc-status backend: %s\n' "$RC_STATUS" >&2
		rc=1
	fi
	count=0
	for base in $(ls "$SERVICE_DIR" 2>/dev/null); do
		case "$base" in
			*.service) ;;
			*) continue ;;
		esac
		file="$SERVICE_DIR/$base"
		[ -f "$file" ] || continue
		count=$((count + 1))
		check_manifest "$file" || rc=1
	done
	if [ "$count" -eq 0 ]; then
		printf 'no service manifests in %s\n' "$SERVICE_DIR" >&2
		rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		printf 'ok service-manifests=%s backend=openrc\n' "$count"
	fi
	return "$rc"
}

list_services() {
	printf 'name\tbackend\tbackend_name\trunlevel\tenabled\trole\n'
	for base in $(ls "$SERVICE_DIR" 2>/dev/null); do
		case "$base" in
			*.service) ;;
			*) continue ;;
		esac
		file="$SERVICE_DIR/$base"
		[ -f "$file" ] || continue
		awk -F= '
			$1 == "name" { name = $2 }
			$1 == "backend" { backend = $2 }
			$1 == "backend_name" { backend_name = $2 }
			$1 == "runlevel" { runlevel = $2 }
			$1 == "enabled" { enabled = $2 }
			$1 == "role" { role = $2 }
			END {
				if (backend_name == "") {
					backend_name = name
				}
				printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, backend, backend_name, runlevel, enabled, role
			}
		' "$file"
	done
}

status_openrc() {
	service=$1
	file=$(manifest_for "$service") || {
		printf 'unknown service: %s\n' "$service" >&2
		return 1
	}
	ensure_openrc_backend "$file" || return 1
	backend_name=$(backend_name_for "$file")
	status_line=$("$RC_STATUS" -a 2>/dev/null | awk -v service="$backend_name" '$1 == service { print; found = 1 } END { exit found ? 0 : 1 }') || {
		printf '%s not found in OpenRC status\n' "$backend_name" >&2
		return 1
	}
	printf '%s\n' "$status_line"
	case "$status_line" in
		*started*) return 0 ;;
		*) return 3 ;;
	esac
}

mutate_openrc() {
	action=$1
	service=$2
	file=$(manifest_for "$service") || {
		printf 'unknown service: %s\n' "$service" >&2
		return 1
	}
	ensure_openrc_backend "$file" || return 1
	backend_name=$(backend_name_for "$file")
	exec "$RC_SERVICE" "$backend_name" "$action"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	check)
		check_all
		;;
	list)
		list_services
		;;
	status)
		service=${2:-}
		if [ -z "$service" ]; then
			usage
			exit 2
		fi
		status_openrc "$service"
		;;
	start|stop)
		service=${2:-}
		if [ -z "$service" ]; then
			usage
			exit 2
		fi
		mutate_openrc "$command" "$service"
		;;
	*)
		usage
		exit 2
		;;
esac
