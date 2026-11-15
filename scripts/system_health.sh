#!/usr/bin/env bash
# system_health.sh - collect host health, log it, warn on thresholds, return exit code.
# Exit codes: 0 healthy, 1 warning, 2 critical.
set -euo pipefail

CPU_T=90
MEM_T=85
DISK_T=80
CRIT_T=95
LOG_FILE="${HEALTH_LOG:-./health_log.txt}"
MAX_BYTES=1048576
KEEP=5
JSON=0
WEBHOOK_URL="${HEALTH_WEBHOOK_URL:-}"

usage() {
  cat <<USAGE
Usage: ${0##*/} [options]
  --cpu N        CPU warning threshold %      (default ${CPU_T})
  --mem N        Memory warning threshold %   (default ${MEM_T})
  --disk N       Disk warning threshold %     (default ${DISK_T})
  --crit N       Critical threshold % for any metric (default ${CRIT_T})
  --log FILE     Log file (default ${LOG_FILE}, env HEALTH_LOG)
  --max-bytes N  Rotate when log exceeds N bytes (default ${MAX_BYTES})
  --keep N       Rotated files to keep (default ${KEEP})
  --json         Output/log JSON instead of text
  -h, --help     Show this help
Env: HEALTH_WEBHOOK_URL - optional Slack/Discord webhook to post warnings.
Exit: 0 healthy, 1 warning, 2 critical.
USAGE
}

is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpu|--mem|--disk|--crit|--max-bytes|--keep)
      if [[ $# -lt 2 ]] || ! is_int "$2"; then
        echo "Error: $1 needs an integer value" >&2
        exit 64
      fi
      case "$1" in
        --cpu) CPU_T=$2 ;;
        --mem) MEM_T=$2 ;;
        --disk) DISK_T=$2 ;;
        --crit) CRIT_T=$2 ;;
        --max-bytes) MAX_BYTES=$2 ;;
        --keep) KEEP=$2 ;;
      esac
      shift 2
      ;;
    --log)
      if [[ $# -lt 2 ]]; then echo "Error: --log needs a file" >&2; exit 64; fi
      LOG_FILE=$2
      shift 2
      ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cpu_usage() {
  local _c u1 n1 s1 i1 w1 q1 sq1 u2 n2 s2 i2 w2 q2 sq2 idle total
  read -r _c u1 n1 s1 i1 w1 q1 sq1 _ < /proc/stat
  sleep 1
  read -r _c u2 n2 s2 i2 w2 q2 sq2 _ < /proc/stat
  idle=$(( (i2 + w2) - (i1 + w1) ))
  total=$(( (u2 + n2 + s2 + i2 + w2 + q2 + sq2) - (u1 + n1 + s1 + i1 + w1 + q1 + sq1) ))
  if [[ $total -le 0 ]]; then echo 0; else echo $(( 100 * (total - idle) / total )); fi
}

mem_usage() {
  awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{ if (t>0) printf "%d", (t-a)*100/t; else print 0 }' /proc/meminfo
}

HOST=$(hostname)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CPU=$(cpu_usage)
MEM=$(mem_usage)
read -r L1 L5 L15 _ < /proc/loadavg

WARNINGS=()
STATUS=0
check() { # name value threshold
  if [[ $2 -ge $CRIT_T ]]; then
    WARNINGS+=("[CRITICAL] $1 at ${2}% (>= ${CRIT_T}%)")
    STATUS=2
  elif [[ $2 -gt $3 ]]; then
    WARNINGS+=("[WARNING] $1 at ${2}% (> ${3}%)")
    if [[ $STATUS -lt 1 ]]; then STATUS=1; fi
  fi
}

check "CPU usage" "$CPU" "$CPU_T"
check "Memory usage" "$MEM" "$MEM_T"

DISK_NAMES=()
DISK_VALS=()
while read -r _fs _size _used _avail pct mount; do
  pct=${pct%\%}
  if is_int "$pct"; then
    DISK_NAMES+=("$mount")
    DISK_VALS+=("$pct")
    check "Disk $mount" "$pct" "$DISK_T"
  fi
done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay | tail -n +2)

TOP=$(ps -eo pid,comm,%mem --sort=-%mem | awk 'NR>1 && NR<=6 {print $1" "$2" "$3}')

render_text() {
  echo "[$TS] host=$HOST cpu=${CPU}% mem=${MEM}% load=$L1/$L5/$L15"
  local i
  for i in "${!DISK_NAMES[@]}"; do echo "  disk ${DISK_NAMES[$i]}=${DISK_VALS[$i]}%"; done
  echo "  top5 memory (pid comm %mem):"
  while read -r p c m; do echo "    $p $c $m"; done <<< "$TOP"
  for w in "${WARNINGS[@]}"; do echo "  $w"; done
}

render_json() {
  local i first=1 out
  out="{\"timestamp\":\"$TS\",\"host\":\"$(json_escape "$HOST")\",\"cpu_percent\":$CPU,\"mem_percent\":$MEM,"
  out+="\"load\":{\"1m\":$L1,\"5m\":$L5,\"15m\":$L15},\"disks\":["
  for i in "${!DISK_NAMES[@]}"; do
    if [[ $first -eq 0 ]]; then out+=","; fi
    first=0
    out+="{\"mount\":\"$(json_escape "${DISK_NAMES[$i]}")\",\"percent\":${DISK_VALS[$i]}}"
  done
  out+="],\"top_memory\":["
  first=1
  while read -r p c m; do
    if [[ $first -eq 0 ]]; then out+=","; fi
    first=0
    out+="{\"pid\":$p,\"command\":\"$(json_escape "$c")\",\"mem_percent\":$m}"
  done <<< "$TOP"
  out+="],\"status\":$STATUS,\"warnings\":["
  first=1
  for w in "${WARNINGS[@]}"; do
    if [[ $first -eq 0 ]]; then out+=","; fi
    first=0
    out+="\"$(json_escape "$w")\""
  done
  out+="]}"
  echo "$out"
}

rotate_log() {
  [[ -f $LOG_FILE ]] || return 0
  local size i
  size=$(wc -c < "$LOG_FILE")
  if [[ $size -le $MAX_BYTES ]]; then return 0; fi
  for (( i=KEEP-1; i>=1; i-- )); do
    if [[ -f "$LOG_FILE.$i" ]]; then mv -f "$LOG_FILE.$i" "$LOG_FILE.$((i+1))"; fi
  done
  mv -f "$LOG_FILE" "$LOG_FILE.1"
}

if [[ $JSON -eq 1 ]]; then OUTPUT=$(render_json); else OUTPUT=$(render_text); fi

mkdir -p "$(dirname "$LOG_FILE")"
rotate_log
echo "$OUTPUT" >> "$LOG_FILE"
echo "$OUTPUT"

if [[ -n "$WEBHOOK_URL" && ${#WARNINGS[@]} -gt 0 ]]; then
  msg="$HOST: $(printf '%s; ' "${WARNINGS[@]}")"
  curl -fsS -m 10 -H 'Content-Type: application/json' \
    -d "{\"text\":\"$(json_escape "$msg")\",\"content\":\"$(json_escape "$msg")\"}" \
    "$WEBHOOK_URL" >/dev/null || echo "webhook post failed" >&2
fi

exit "$STATUS"
