#!/usr/bin/env bash

set -euo pipefail

# Colors for better visual feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper: colored output
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_header() { echo -e "\n${BOLD}$1${NC}"; }

# Helper: prompt yes/no with better UX
ask_yes_no() {
  local prompt="${1:-Proceed?}"
  local default="${2:-n}"
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  
  echo -ne "${YELLOW}➤ ${prompt} ${hint}: ${NC}"
  read -r ans
  
  if [[ -z "$ans" ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  
  case "${ans,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Helper: validate MAC address
validate_mac() {
  local mac="$1"
  if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    return 1
  fi
  return 0
}

# Helper: show spinner
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$pid" 2>/dev/null; do
    for ((i=0; i<${#spinstr}; i++)); do
      printf " %s  " "${spinstr:$i:1}"
      sleep $delay
      printf "\b\b\b\b"
    done
  done
  printf "    \b\b\b\b"
}

# Clear screen and show welcome
clear
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                    eduroam Setup Assistant                     ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo
print_info "This tool will help you configure eduroam network access."
print_info "You'll need either an ArubaQuickConnect.sh file OR an OTP code."
echo
print_info "Version: 0.3.0"
echo

# Initialize variables
otp=""
mac_input=""
aruba_file=""
setup_mode=""

# Step 1: Choose setup method
print_header "Step 1: Choose Setup Method"
echo "1) I have an ArubaQuickConnect.sh file"
echo "2) I have an OTP code"
echo -n "Select option (1-2): "
read -r choice

case "$choice" in
  1)
    setup_mode="file"
    echo -n "Enter path to ArubaQuickConnect.sh: "
    read -r aruba_file
    
    if [[ ! -f "$aruba_file" ]]; then
      print_error "File not found: $aruba_file"
      exit 1
    fi
    
    print_info "Extracting configuration..."
    chmod +x "$aruba_file"
    
    # Extract in background with spinner
    (
      workdir="$(mktemp -d)"
      trap 'rm -rf "$workdir"' EXIT
      cp "$aruba_file" "$workdir/ArubaQuickConnect.sh"
      cd "$workdir"
      tail -n +505 ArubaQuickConnect.sh > ArubaQuickConnect.tar.gz
      tar -xf ArubaQuickConnect.tar.gz 2>/dev/null
      
      if [[ -f quickconnect/props/config.ini ]]; then
        otp="$(awk -F= '/^[[:space:]]*global\.otp[[:space:]]*=/ {print $2}' quickconnect/props/config.ini | sed 's/[[:space:]]//g' | head -n1)"
        echo "$otp" > /tmp/eduroam_otp_temp
      fi
    ) &
    
    spinner $!
    
    if [[ -f /tmp/eduroam_otp_temp ]]; then
      otp="$(cat /tmp/eduroam_otp_temp)"
      rm -f /tmp/eduroam_otp_temp
      print_success "Extracted OTP: ${otp}"
    else
      print_warning "Could not extract OTP from file."
    fi
    ;;
  2)
    setup_mode="manual"
    ;;
  *)
    print_error "Invalid option"
    exit 1
    ;;
esac

# Step 2: Collect required information
print_header "Step 2: Required Information"

if [[ -z "$otp" ]]; then
  while [[ -z "$otp" ]]; do
    echo -n "Enter OTP code: "
    read -r otp
    [[ -z "$otp" ]] && print_error "OTP cannot be empty"
  done
fi

while [[ -z "$mac_input" ]]; do
  echo -n "Enter MAC address (e.g., AA:BB:CC:DD:EE:FF): "
  read -r mac_input
  if ! validate_mac "$mac_input"; then
    print_error "Invalid MAC address format"
    mac_input=""
  fi
done

# Step 3: Generate certificates
print_header "Step 3: Certificate Generation"

if ask_yes_no "Generate certificates for this device?" "y"; then
  export est_otp="${otp}"
  export mac_wifi="${mac_input}"
  export mac_eth="${mac_input}"
  
  if [[ ! -x "./est-wifi-script.sh" ]]; then
    print_error "est-wifi-script.sh not found in current directory"
    exit 1
  fi
  
  print_info "Generating certificates..."
  log_file=$(mktemp)
  (./est-wifi-script.sh --enroll > "$log_file" 2>&1) &
  pid=$!
  spinner $pid
  
  if wait $pid; then
    print_success "Certificates generated successfully"
    rm -f "$log_file"
  else
    print_error "Certificate generation failed. Log:"
    cat "$log_file"
    rm -f "$log_file"
    exit 1
  fi
fi

# Step 4: Extract certificates
if [[ -f "data/payload1.plist" ]]; then
  print_header "Step 4: Certificate Extraction"
  
  if [[ ! -x "./extract_certs.sh" ]]; then
    print_error "extract_certs.sh not found"
    exit 1
  fi
  
  print_info "Extracting certificates..."
  log_file=$(mktemp)
  (./extract_certs.sh > "$log_file" 2>&1) &
  pid=$!
  spinner $pid

  if wait $pid; then
    print_success "Certificates extracted successfully"
    rm -f "$log_file"
  else
    print_error "Certificate extraction failed. Log:"
    cat "$log_file"
    rm -f "$log_file"
  fi
fi

# Step 5: Copy CA certificate
print_header "Step 5: Certificate Installation"

if ask_yes_no "Install CA certificate to ~/.config/eduroam/certs/ ?" "y"; then
  src="data/unsw_ca_chain.pem"
  dst_dir="${HOME}/.config/eduroam/certs"
  
  if [[ ! -f "$src" ]]; then
    print_error "Certificate not found: $src"
  else
    mkdir -p "$dst_dir"
    cp -f "$src" "$dst_dir/"
    print_success "Certificate installed to $dst_dir/"
  fi
fi

# Step 6: Configure NetworkManager
print_header "Step 6: Network Configuration"

if command -v nmcli &> /dev/null && ask_yes_no "Configure eduroam automatically?" "y"; then
  ca_cert_path=""
  
  if [[ -f "${HOME}/.config/eduroam/certs/unsw_ca_chain.pem" ]]; then
    ca_cert_path="${HOME}/.config/eduroam/certs/unsw_ca_chain.pem"
  elif [[ -f "data/unsw_ca_chain.pem" ]]; then
    ca_cert_path="$(realpath "data/unsw_ca_chain.pem")"
  fi
  
  if [[ -z "$ca_cert_path" ]]; then
    print_error "CA certificate not found"
  else
    echo -n "Enter your zID (e.g., z1234567): "
    read -r zid
    echo -n "Enter your zID password: "
    read -r -s zpassword
    echo
    
    if [[ -z "$zid" || -z "$zpassword" ]]; then
      print_error "zID and password are required"
    else
      print_info "Configuring eduroam..."
      
      # Remove existing connection if present
      nmcli connection delete "eduroam" 2>/dev/null || true
      
      if nmcli connection add type wifi con-name "eduroam" ifname "*" ssid "eduroam" -- \
        wifi-sec.key-mgmt wpa-eap \
        802-1x.eap peap \
        802-1x.phase2-auth mschapv2 \
        802-1x.ca-cert "$ca_cert_path" \
        802-1x.identity "${zid}@ad.unsw.edu.au" \
        802-1x.password "$zpassword" 2>/dev/null; then
        
        print_success "eduroam configured successfully!"
        print_info "You should now be able to connect to eduroam"
      else
        print_error "Failed to configure eduroam"
      fi
    fi
  fi
else
  # Show manual configuration instructions
  echo
  echo -e "${BOLD}Manual Configuration Instructions:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${BOLD}Network Settings:${NC}"
  echo "  • Network: eduroam"
  echo "  • Security: WPA & WPA2 Enterprise"
  echo "  • Authentication: Protected EAP (PEAP)"
  echo
  echo -e "${BOLD}Authentication:${NC}"
  echo "  • Anonymous identity: (leave empty)"
  echo "  • Domain: (leave empty)"
  echo -e "  • CA certificate: ${BLUE}~/.config/eduroam/certs/unsw_ca_chain.pem${NC}"
  echo "  • PEAP version: Automatic"
  echo "  • Inner authentication: MSCHAPv2"
  echo
  echo -e "${BOLD}Credentials:${NC}"
  echo -e "  • Username: ${BLUE}z1234567@ad.unsw.edu.au${NC} (use your zID)"
  echo "  • Password: Your zID password"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo
print_success "Setup complete!"