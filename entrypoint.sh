#!/bin/bash
set -e

# Support overriding paths via environment variables at container startup;
# fall back to defaults when not set
SQUID_CERT_DIR="${SQUID_CERT_DIR:-/etc/squid/ssl_cert}"
SQUID_DB_DIR="${SQUID_DB_DIR:-/var/lib/squid/ssl_db}"
SQUID_DB_SIZE="${SQUID_DB_SIZE:-20MB}"
SQUID_CA_CERT="${SQUID_CA_CERT:-$SQUID_CERT_DIR/squid-CA.pem}"
SQUID_CA_KEY="${SQUID_CA_KEY:-$SQUID_CERT_DIR/squid-CA.key}"

CA_FINGERPRINT_FILE="$SQUID_DB_DIR/.ca_fingerprint"

# The CA certificate is provided by an external build process;
# this script only verifies it exists, it does not generate it
if [ ! -f "$SQUID_CA_CERT" ] || [ ! -f "$SQUID_CA_KEY" ]; then
    echo "Error: CA certificate files not found" >&2
    echo "  Expected path: $SQUID_CA_CERT" >&2
    echo "  Expected path: $SQUID_CA_KEY" >&2
    exit 1
fi

CURRENT_FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in "$SQUID_CA_CERT")

# If the database already exists but the CA has changed, wipe and rebuild it
# to avoid issuing certificates that no longer match the current CA
if [ -d "$SQUID_DB_DIR" ] && [ -f "$CA_FINGERPRINT_FILE" ]; then
    STORED_FINGERPRINT=$(cat "$CA_FINGERPRINT_FILE")
    if [ "$CURRENT_FINGERPRINT" != "$STORED_FINGERPRINT" ]; then
        echo "CA change detected, wiping and rebuilding the certificate database..."
        rm -rf "$SQUID_DB_DIR"
    fi
fi

# The certificate database must be initialized manually;
# Squid/the helper will not create it automatically
if [ ! -d "$SQUID_DB_DIR" ]; then
    echo "Initializing certificate database: $SQUID_DB_DIR (size $SQUID_DB_SIZE)..."
    /usr/lib/squid/security_file_certgen -c -s "$SQUID_DB_DIR" -M "$SQUID_DB_SIZE"
    chown -R proxy:proxy "$SQUID_DB_DIR"
    echo "$CURRENT_FINGERPRINT" > "$CA_FINGERPRINT_FILE"
fi

chown -R proxy:proxy "$SQUID_CERT_DIR"

exec squid -N -d 1
