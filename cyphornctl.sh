#!/usr/bin/env bash
set -euo pipefail

# Cyphorn unified manager (covers all known CLI options for server & client)
# Requires: bash, iproute2
#
# Examples:
#   sudo ./cyphornctl.sh start  --role server --dev cytun0 --port 60000 --tun-ptp 10.10.0.1,10.10.0.2 --assign-tun-ip --debug
#   sudo ./cyphornctl.sh start  --role client --dev cytun0 --server-ip 1.2.3.4 --port 60000 \
#        --peer-pubkey 0123...cafe --tun-ptp 10.10.0.2,10.10.0.1 --probe --offer-chacha
#   sudo ./cyphornctl.sh restart --role client --dev cytun0 --no-auto-reconnect --idle 90 --reconnect-min 3 --reconnect-max 30
#   sudo ./cyphornctl.sh status  --role server --dev cytun0
#   sudo ./cyphornctl.sh logs
#
# Notes:
# - Before start/restart it ALWAYS kills the old process (pidfile + pattern) and deletes the TUN iface.
# - Defaults to daemon mode with a predictable pidfile unless you pass --no-daemon.
# - Reads /etc/default/cyphorn if present (env overrides).

BIN="./cyphorn"         # change to ./build/cyphorn or pass --use-local-bin
LOG="/var/log/cyphorntun.log"

MTU=""

# Defaults / common
ROLE=""                          # server|client (required)
IFACE="cytun0"
PORT="55555"
DAEMON=1
PIDFILE=""                       # if empty we will set /var/run/cyphorn-<role>-<iface>.pid
KEEP_DEV=0
DEBUG=0

# Server-specific
ASSIGN_TUN_IP=0                  # --assign-tun-ip (aka --preup)
TUN=""                           # --tun CIDR
TUN_PTP=""                       # --tun-ptp local,peer

# Client-specific
SERVER_IP=""
PEER_PUBKEY=""
PROBE=0
UDPTEST=0
NO_AUTO_RECONNECT=0
IDLE=""
RECONNECT_MIN=""
RECONNECT_MAX=""

# Cipher offers/forces (both roles parse, program uses appropriately)

FORCE_CHACHA=0

OFFER_CHACHA=0

# Passthrough accumulator (future-proof)
EXTRA_ARGS=()

# Load global defaults if available
if [[ -f /etc/default/cyphorn ]]; then
  # shellcheck disable=SC1091
  source /etc/default/cyphorn
fi

usage() {
  cat <<'USAGE'
Usage:
  cyphornctl.sh {start|stop|restart|status|logs|show-cmd} --role {server|client} --dev IFACE [options]

Common options:
  --port N                  UDP port (default 55555)
  --debug                   Enable verbose logs
  --daemon                  Run cyphorn in daemon mode (default)
  --no-daemon               Run in foreground (cyphornctl still returns after spawn)
  --pidfile PATH            Explicit pidfile path
  --keep-dev                Do NOT delete TUN interface on app exit (script still deletes at restart/stop)
  --use-local-bin           Use ./build/cyphorn instead of /usr/sbin/cyphorn

Server options:
  --assign-tun-ip | --preup   Configure TUN before handshake
  --tun CIDR                  e.g. --tun 10.10.0.1/24
  --tun-ptp L,P               e.g. --tun-ptp 10.10.0.1,10.10.0.2

Client options:
  --server-ip A.B.C.D
  --peer-pubkey HEX32         64 hex chars for Ed25519 static pk
  --probe                     Send ICMP echo over TUN right after HS
  --udptest                   Send tiny UDP test packet every 2s (debug)
  --no-auto-reconnect
  --idle SEC
  --reconnect-min S
  --reconnect-max S

Other:
  Unknown flags are passed through as-is to cyphorn (future-proof).

Examples:
  sudo ./cyphornctl.sh start --role server --dev cytun0 --port 60000 --tun 10.10.0.1/24 --debug
  sudo ./cyphornctl.sh start --role client --dev cytun0 --server-ip 203.0.113.10 --peer-pubkey <hex> --tun-ptp 10.10.0.2,10.10.0.1 --probe
USAGE
}

need_root() { [[ $EUID -eq 0 ]] || { echo "This needs root (sudo)."; exit 1; }; }
exists_iface() { ip link show "$1" >/dev/null 2>&1; }
delete_iface() {
  local ifn="$1"
  if exists_iface "$ifn"; then
    ip link del "$ifn" 2>/dev/null || ip tuntap del dev "$ifn" mode tun 2>/dev/null || true
  fi
}
kill_by_pidfile() {
  local pf="$1"
  if [[ -f "$pf" ]]; then
    local pid
    pid="$(awk 'NR==1{print $1}' "$pf" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && ps -p "$pid" -o pid= >/dev/null 2>&1; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in {1..25}; do sleep 0.2; ps -p "$pid" -o pid= >/dev/null 2>&1 || break; done
      ps -p "$pid" -o pid= >/dev/null 2>&1 && kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$pf"
  fi
}
kill_by_pattern() {
  pkill -f "(^|/)cyphorn(\s|$).*--${ROLE}(\s|$).*--dev\s+${IFACE}" 2>/dev/null || true
}
stop_all() {
  need_root
  local pf="${PIDFILE:-/var/run/cyphorn-${ROLE}-${IFACE}.pid}"
  kill_by_pidfile "$pf"
  kill_by_pattern
  rm -f "/var/run/cyphorn-${IFACE}.lock" 2>/dev/null || true
  delete_iface "$IFACE"
}

# -------- Parse top-level command --------
CMD="${1:-}"; shift || true
[[ -z "${CMD:-}" ]] && { usage; exit 1; }

# -------- Parse args --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)                 ROLE="${2:-}"; shift 2 ;;
    --dev)                  IFACE="${2:-}"; shift 2 ;;
    --port)                 PORT="${2:-}"; shift 2 ;;

    --debug)                DEBUG=1; shift ;;
    --daemon)               DAEMON=1; shift ;;
    --no-daemon)            DAEMON=0; shift ;;
    --pidfile)              PIDFILE="${2:-}"; shift 2 ;;
    --keep-dev)             KEEP_DEV=1; shift ;;
    --use-local-bin)        BIN="./build/cyphorn"; shift ;;

    # Cipher knobs
    --force-chacha)         FORCE_CHACHA=1; shift ;;
    --offer-chacha)         OFFER_CHACHA=1; shift ;;

    # Server
    --assign-tun-ip|--preup) ASSIGN_TUN_IP=1; shift ;;
    --tun)                  TUN="${2:-}"; shift 2 ;;
    --tun-ptp)              TUN_PTP="${2:-}"; shift 2 ;;

    # Client
    --server-ip)            SERVER_IP="${2:-}"; shift 2 ;;
    --peer-pubkey)          PEER_PUBKEY="${2:-}"; shift 2 ;;
    --probe)                PROBE=1; shift ;;
    --udptest)              UDPTEST=1; shift ;;
    --no-auto-reconnect)    NO_AUTO_RECONNECT=1; shift ;;
    --idle)                 IDLE="${2:-}"; shift 2 ;;
    --reconnect-min)        RECONNECT_MIN="${2:-}"; shift 2 ;;
    --reconnect-max)        RECONNECT_MAX="${2:-}"; shift 2 ;;
    --mtu)        MTU="${2:-}"; shift 2 ;;

    --help|-h)              usage; exit 0 ;;

    --) shift; while [[ $# -gt 0 ]]; do EXTRA_ARGS+=("$1"); shift; done ;;
    *)  EXTRA_ARGS+=("$1"); shift ;;
  esac
done

[[ -z "$ROLE" ]] && { echo "Error: --role server|client is required"; exit 1; }
PIDFILE="${PIDFILE:-/var/run/cyphorn-${ROLE}-${IFACE}.pid}"

# -------- Build cyphorn command --------
build_cmd() {
  local args=("$BIN")

  if [[ "$ROLE" == "server" ]]; then
    args+=("--server" "--port" "$PORT" "--dev" "$IFACE")
    [[ $ASSIGN_TUN_IP -eq 1 ]] && args+=("--assign-tun-ip")
    if [[ -n "$TUN_PTP" ]]; then
      args+=("--tun-ptp" "$TUN_PTP")
    elif [[ -n "$TUN" ]]; then
      args+=("--tun" "$TUN")
    else
      # sensible default for server if nothing provided
      args+=("--tun" "10.10.0.1/24")
    fi
  else
    # client
    [[ -n "$SERVER_IP" ]]   || { echo "Error: client needs --server-ip"; exit 1; }
    [[ -n "$PEER_PUBKEY" ]] || { echo "Error: client needs --peer-pubkey"; exit 1; }
    args+=("--client" "--server-ip" "$SERVER_IP" "--peer-pubkey" "$PEER_PUBKEY" "--port" "$PORT" "--dev" "$IFACE")
    [[ $PROBE -eq 1 ]]              && args+=("--probe")
    [[ $UDPTEST -eq 1 ]]            && args+=("--udptest")
    [[ $NO_AUTO_RECONNECT -eq 1 ]]  && args+=("--no-auto-reconnect")
    [[ -n "$IDLE" ]]                && args+=("--idle" "$IDLE")
    [[ -n "$RECONNECT_MIN" ]]       && args+=("--reconnect-min" "$RECONNECT_MIN")
    [[ -n "$RECONNECT_MAX" ]]       && args+=("--reconnect-max" "$RECONNECT_MAX")

    if [[ -n "$TUN_PTP" ]]; then
      args+=("--tun-ptp" "$TUN_PTP")
    elif [[ -n "$TUN" ]]; then
      args+=("--tun" "$TUN")
    else
      # sensible default for client if nothing provided
      args+=("--tun-ptp" "10.10.0.2,10.10.0.1")
    fi
  fi

  # Ciphers/offers
  [[ $FORCE_CHACHA -eq 1 ]]  && args+=("--force-chacha")
  [[ $OFFER_CHACHA -eq 1 ]]  && args+=("--offer-chacha")

  # Debug
  [[ $DEBUG -eq 1 ]]         && args+=("--debug")

  # Lifecycle options
  if [[ $DAEMON -eq 1 ]]; then
    args+=("--daemon" "--pidfile" "$PIDFILE")
  fi
  [[ $KEEP_DEV -eq 1 ]] && args+=("--keep-dev")

  # Pass-through
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    args+=("${EXTRA_ARGS[@]}")
  fi

  printf '%q ' "${args[@]}"
}

do_start() {
  need_root
  # full clean before start
  stop_all

  [[ -x "$BIN" ]] || { echo "Binary not found at $BIN"; exit 1; }
  # Ensure /dev/net/tun exists (some kernels need it)
  if [[ ! -e /dev/net/tun ]]; then
    mkdir -p /dev/net || true
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 0666 /dev/net/tun || true
  fi

  local cmdline; cmdline="$(build_cmd)"
  echo "[run] $cmdline"
  eval "$cmdline"

if [[ -n "$MTU" ]]; then
  ip link set dev "$IFACE" mtu "$MTU" 2>/dev/null || true
  echo "Set MTU $MTU on $IFACE"
fi



  # Give it a moment to write pidfile if daemonized
  if [[ $DAEMON -eq 1 ]]; then
    sleep 0.4
    if [[ -f "$PIDFILE" ]]; then
      echo "Started $ROLE on $IFACE (pid $(cat "$PIDFILE"))."
    else
      echo "Started, but pidfile not found yet. Check logs."
    fi
  fi
}

do_status() {
  if [[ -f "$PIDFILE" ]]; then
    local pid; pid="$(awk 'NR==1{print $1}' "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && ps -p "$pid" -o pid= >/dev/null 2>&1; then
      echo "$ROLE on $IFACE is running (pid $pid)."
    else
      echo "$ROLE on $IFACE has stale/missing process for pidfile $PIDFILE."
    fi
  else
    if pgrep -fa "(^|/)cyphorn(\s|$).*--${ROLE}(\s|$).*--dev\s+${IFACE}" >/dev/null 2>&1; then
      echo "$ROLE on $IFACE seems running (no pidfile)."
    else
      echo "$ROLE on $IFACE is stopped."
    fi
  fi
  if exists_iface "$IFACE"; then ip -br addr show "$IFACE"; else echo "Interface $IFACE not present."; fi
}

do_logs() {
  if [[ -f "$LOG" ]]; then
    tail -n 200 -f "$LOG"
  else
    echo "Log file $LOG not found. Maybe enable --debug or check journal."
  fi
}

do_show_cmd() { build_cmd; echo; }

do_pubkey() {
  local f="/etc/cyphorntun/identity.yaml"
  if [[ -f "$f" ]]; then
    # Extract the line with "public_key" and show only the value
    local pk
    pk=$(grep -m1 'public_key:' "$f" | awk -F'"' '{print $2}')
    if [[ -n "$pk" ]]; then
      echo "Cyphorn Server Public Key:"
      echo "$pk"
    else
      echo "Public key not found in $f"
    fi
  else
    echo "Identity file $f not found. Start the server once to generate it."
  fi
}




case "$CMD" in
  start)    do_start ;;
  stop)     stop_all ;;
  restart)  stop_all; do_start ;;
  status)   do_status ;;
  logs)     do_logs ;;
  show-cmd) do_show_cmd ;;
  pubkey)   do_pubkey ;;
  *)        usage; exit 1 ;;
esac



