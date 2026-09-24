#!/usr/bin/env bash
# Container entrypoint for squid-openssl (SSL bump).
# Responsibilities:
#   1. Require an externally supplied CA (never generate one here).
#   2. (Re)initialize security_file_certgen's ssl_db when missing, incomplete,
#      or signed by a different CA than last time.
#   3. Drop privileges and exec Squid in the foreground as PID 1.
set -euo pipefail

SQUID_CERT_DIR="${SQUID_CERT_DIR:-/etc/squid/ssl_cert}"
SQUID_DB_DIR="${SQUID_DB_DIR:-/var/lib/squid/ssl_db}"
SQUID_DB_SIZE="${SQUID_DB_SIZE:-20MB}"
SQUID_CA_CERT="${SQUID_CA_CERT:-$SQUID_CERT_DIR/squid-CA.pem}"
SQUID_CA_KEY="${SQUID_CA_KEY:-$SQUID_CERT_DIR/squid-CA.key}"
SQUID_USER="${SQUID_USER:-proxy}"
SQUID_GROUP="${SQUID_GROUP:-proxy}"
SQUID_CONF="${SQUID_CONF:-/etc/squid/squid.conf}"
# Foreground only by default. Enable debug with e.g. SQUID_ARGS="-N -d 1".
SQUID_ARGS="${SQUID_ARGS:--N}"

# Written after a successful ssl_db init so a later CA rotation can be detected.
CA_FINGERPRINT_FILE="$SQUID_DB_DIR/.ca_fingerprint"

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { log "Error: $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Distros install the helper under different paths; allow an explicit override.
find_certgen() {
  local candidates=(
    "${SQUID_CERTGEN:-}"
    /usr/lib/squid/security_file_certgen
    /usr/libexec/squid/security_file_certgen
    /usr/lib/squid/ssl_crtd
  )
  local p
  for p in "${candidates[@]}"; do
    [[ -n "$p" && -x "$p" ]] && { printf '%s' "$p"; return 0; }
  done
  die "security_file_certgen not found; set SQUID_CERTGEN"
}

# Normalize to uppercase hex so OpenSSL's "sha256 Fingerprint=" prefix
# (and any future spacing changes) cannot cause a false CA-changed rebuild.
ca_fingerprint() {
  openssl x509 -noout -fingerprint -sha256 -in "$1" \
    | awk -F= '{print toupper($NF)}' \
    | tr -d '[:space:]'
}

# A directory alone is not enough: a crashed first run can leave an empty
# or half-written ssl_db that Squid will not repair by itself.
ssl_db_valid() {
  [[ -d "$SQUID_DB_DIR" ]] || return 1
  [[ -f "$CA_FINGERPRINT_FILE" ]] || return 1
  [[ -e "$SQUID_DB_DIR/size" || -e "$SQUID_DB_DIR/index.txt" || -d "$SQUID_DB_DIR/certs" ]] || return 1
  return 0
}

# CA/key and ssl_db are often bind-mounted :ro or tmpfs; chown must not
# abort startup when the filesystem rejects it.
chown_if_possible() {
  local target="$1"
  if chown -R "${SQUID_USER}:${SQUID_GROUP}" "$target" 2>/dev/null; then
    return 0
  fi
  log "Warning: cannot chown $target (read-only mount?); continuing"
}

if [[ ! -f "$SQUID_CA_CERT" || ! -f "$SQUID_CA_KEY" ]]; then
  die "CA certificate files not found
  Expected cert: $SQUID_CA_CERT
  Expected key:  $SQUID_CA_KEY"
fi

CURRENT_FINGERPRINT="$(ca_fingerprint "$SQUID_CA_CERT")"
[[ -n "$CURRENT_FINGERPRINT" ]] || die "failed to read CA fingerprint from $SQUID_CA_CERT"

NEED_INIT=0
if ! ssl_db_valid; then
  NEED_INIT=1
  if [[ -e "$SQUID_DB_DIR" ]]; then
    log "Certificate database missing or incomplete; rebuilding $SQUID_DB_DIR"
    rm -rf "$SQUID_DB_DIR"
  fi
else
  STORED_FINGERPRINT="$(tr -d '[:space:]' < "$CA_FINGERPRINT_FILE")"
  if [[ "$CURRENT_FINGERPRINT" != "$STORED_FINGERPRINT" ]]; then
    # Old dynamic certs were issued by a different CA; keep using them and
    # clients will fail TLS validation against the new trust anchor.
    log "CA change detected, wiping and rebuilding the certificate database..."
    rm -rf "$SQUID_DB_DIR"
    NEED_INIT=1
  fi
fi

if [[ "$NEED_INIT" -eq 1 ]]; then
  CERTGEN="$(find_certgen)"
  log "Initializing certificate database: $SQUID_DB_DIR (size $SQUID_DB_SIZE)"
  mkdir -p "$(dirname "$SQUID_DB_DIR")"
  "$CERTGEN" -c -s "$SQUID_DB_DIR" -M "$SQUID_DB_SIZE"
  mkdir -p "$SQUID_DB_DIR"
  # Record the fingerprint only after certgen succeeds.
  printf '%s\n' "$CURRENT_FINGERPRINT" > "$CA_FINGERPRINT_FILE"
  chown_if_possible "$SQUID_DB_DIR"
fi

# Best-effort hardening. Failures are ignored so :ro secret mounts still work.
chmod 0755 "$SQUID_CERT_DIR" 2>/dev/null || true
chmod 0644 "$SQUID_CA_CERT" 2>/dev/null || true
chmod 0640 "$SQUID_CA_KEY" 2>/dev/null || true
chown_if_possible "$SQUID_CERT_DIR"

# Opt-in only. Still not a substitute for rebuilding the image.
# Must run as root, before parse/exec, so Squid loads the refreshed bundle.
if [[ "${UPDATE_CA_CERTIFICATES:-0}" == "1" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    log "Warning: UPDATE_CA_CERTIFICATES=1 ignored (not root)"
  else
    log "Updating ca-certificates package and rebuilding trust store"
    apt-get update -qq
    apt-get install -y --no-install-recommends ca-certificates
    update-ca-certificates
  fi
fi

# Fail fast on a broken config instead of starting and crash-looping.
if [[ -f "$SQUID_CONF" ]]; then
  squid -k parse -f "$SQUID_CONF"
fi

# exec so Squid is PID 1 and receives SIGTERM from the runtime.
# gosu first when we are still root; Squid may also drop via cache_effective_user.
if have_cmd gosu && [[ "$(id -u)" -eq 0 ]]; then
  # shellcheck disable=SC2086
  exec gosu "${SQUID_USER}" squid $SQUID_ARGS -f "$SQUID_CONF"
fi

# shellcheck disable=SC2086
exec squid $SQUID_ARGS -f "$SQUID_CONF"
