#!/bin/bash

# ==============================================================================
# Script: extract_certs.sh
# Description: Extract UNSW certificates from data/payload1.plist and create a certificate chain
# Author: Updated with xmllint approach
# Dependencies: xmllint (libxml2-utils)
# ==============================================================================

set -euo pipefail

# --- UI Helpers ---
supports_color() { [ -t 1 ] && command -v tput >/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; }
if supports_color; then
    C_BOLD="$(tput bold)"; C_RESET="$(tput sgr0)"
    C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"; C_RED="$(tput setaf 1)"; C_BLUE="$(tput setaf 4)"
else
    C_BOLD=""; C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi
QUIET=0
info()  { [ "$QUIET" -eq 0 ] && echo "${C_BLUE}[*]${C_RESET} $*"; }
success(){ [ "$QUIET" -eq 0 ] && echo "${C_GREEN}[✓]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err()   { echo "${C_RED}[x]${C_RESET} $*" >&2; }

print_usage() {
    cat <<EOF
${C_BOLD}Usage:${C_RESET} $(basename "$0") [options]

Extract UNSW certificates from a plist and create a PEM chain.

Options:
  -p, --plist <path>       Path to input plist (default: data/payload1.plist)
  -o, --out <filename>     Output chain filename (default: unsw_ca_chain.pem)
  -d, --outdir <dir>       Output directory (default: data)
  -q, --quiet              Reduce output
  -h, --help               Show this help

Dependencies: xmllint, base64, openssl
EOF
}

# --- Configuration (defaults, can be overridden by args) ---
PLIST_FILE="data/payload1.plist"
CHAIN_FILE="unsw_ca_chain.pem"
OUT_DIR="data"

# The display names of the certificates you want to extract.
ISSUING_CA_NAME="UNSW Issuing Certification Authority"
ROOT_CA_NAME="UNSW Root Certification Authority"

# --- Parse arguments ---
while [ "${1-}" != "" ]; do
    case "$1" in
        -p|--plist) PLIST_FILE="${2-}"; shift 2 ;;
        -o|--out)   CHAIN_FILE="${2-}"; shift 2 ;;
        -d|--outdir) OUT_DIR="${2-}"; shift 2 ;;
        -q|--quiet) QUIET=1; shift ;;
        -h|--help)  print_usage; exit 0 ;;
        *) err "Unknown option: $1"; print_usage; exit 2 ;;
    esac
done

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Temporary files
TMP_DIR="$(mktemp -d)"
ISSUING_CERT_B64="${TMP_DIR}/unsw_issuing_ca.b64"
ROOT_CERT_B64="${TMP_DIR}/unsw_root_ca.b64"

# --- Pre-flight Checks ---

# Check for the xmllint command
if ! command -v xmllint &> /dev/null; then
    err "'xmllint' not found. Install libxml2-utils (Debian/Ubuntu) or libxml2 (Fedora)."
    exit 1
fi
if ! command -v base64 &> /dev/null; then
    err "'base64' command not found. Please install coreutils/base64."
    exit 1
fi
if ! command -v openssl &> /dev/null; then
    err "'openssl' not found. Please install it first."
    exit 1
fi

# Check if the plist file exists and is readable
if [ ! -r "$PLIST_FILE" ]; then
    err "File '$PLIST_FILE' does not exist or is not readable."
    exit 1
fi

# Function to extract Base64 content for a given certificate display name.
extract_cert_data() {
    local cert_name="$1"
    local file_path="$2"
    local output_file="$3"

    info "Extracting certificate: ${cert_name}"
    local cert_data
    cert_data=$(xmllint --xpath "string(//dict[key='PayloadDisplayName' and string='$cert_name']/data)" "$file_path" 2>/dev/null | tr -d '[:space:]')

    if [ -z "$cert_data" ]; then
        err "Failed to find certificate data for: ${cert_name}. Check the display name or plist content."
        exit 1
    fi

    # Basic validation: base64 should be multiples of 4 and contain valid chars
    if ! printf '%s' "$cert_data" | grep -Eq '^[A-Za-z0-9+/=]+$'; then
        err "Extracted data for '${cert_name}' does not look like Base64."
        exit 1
    fi
    printf '%s' "$cert_data" > "$output_file"
    success "Saved Base64 data to ${output_file}"
}

# Cleanup function
cleanup() {
    [ "$QUIET" -eq 0 ] && echo "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Main logic
main() {
    info "Starting certificate extraction"
    info "Input plist: ${PLIST_FILE}"
    info "Output chain: ${OUT_DIR}/${CHAIN_FILE}"

    # Extract and convert UNSW Issuing Certification Authority
    extract_cert_data "$ISSUING_CA_NAME" "$PLIST_FILE" "$ISSUING_CERT_B64"
    info "Writing first certificate to chain..."
    if ! base64 -d "$ISSUING_CERT_B64" | openssl x509 -inform DER > "${OUT_DIR}/${CHAIN_FILE}" 2>/dev/null; then
        err "Failed to decode or parse issuing CA certificate."
        exit 1
    fi

    # Extract and convert UNSW Root Certification Authority
    extract_cert_data "$ROOT_CA_NAME" "$PLIST_FILE" "$ROOT_CERT_B64"
    info "Appending root certificate to chain..."
    if ! base64 -d "$ROOT_CERT_B64" | openssl x509 -inform DER >> "${OUT_DIR}/${CHAIN_FILE}" 2>/dev/null; then
        err "Failed to decode or parse root CA certificate."
        exit 1
    fi

    success "Created certificate chain: ${OUT_DIR}/${CHAIN_FILE}"
    [ "$QUIET" -eq 0 ] && echo "Done."
}

# Execute main function
main