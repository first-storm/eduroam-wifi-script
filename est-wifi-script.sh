#!/usr/bin/env bash

#---------------------------------------------------------#
#   ________    ______    _________       RFC 7030 + 8951 #
#  |_   __  | .' ____ \  |  _   _  |                      #
#    | |_ \_| | (___ \_| |_/ | | \_|                      #
#    |  _| _   _.____`.      | |     -- A WiFi enabling   #
#   _| |__/ | | \____) |    _| |_        shell script  -- #
#  |________|  \______.'   |_____|                        #
#   March 2025                            By Craig Martin #
#---------------------------------------------------------#

# Please EXERCISE CAUTION. This script is NOT intended
# as a general solution for all Linux users to run.
# If you do not understand CSR process please do not use.

#----------------------------------------------------------
# vars
#----------------------------------------------------------

estserverurl="https://onboard-portal.it.unsw.edu.au"
my_version="0.2.1-beta"

scriptpath="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
datastore="$scriptpath/data"
logdir="$scriptpath/logs"

# where to store curl cookies
cookie_jar="$datastore/cookies.txt"

# enable extra debug log info? 0 = off, 1 = on.
debugprint=0

[ ! -d "$datastore" ] && mkdir -p "$datastore";
[ ! -d "$logdir" ] && mkdir -p "$logdir";

set -o errexit
set -o pipefail

#----------------------------------------------------------
# internal script functions
#----------------------------------------------------------


show_help() {
    echo "
    Using: ./est-script.sh [OPTION]
        
        --help           Show this help information (default)
        --version        Show script version
        
        --enroll         Get a certificate
        --reenroll       Renew the certificate
    ";
    exit 0;
}


show_version() {
    echo "$my_version";
    exit 0;
}


check_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo "ERROR: curl is required but not installed or not in the PATH."
        exit 1
    fi

    if ! command -v openssl &> /dev/null; then
        echo "ERROR: openssl is required but not installed or not in the PATH."
        exit 1
    fi

    if ! command -v sed &> /dev/null; then
        echo "ERROR: sed is required but not installed or not in the PATH."
        exit 1
    fi
}


checkvar_otp() {
    if [ -z "${est_otp}" ]; then
        echo "ERROR: est_otp variable is not set."
        exit 1
    fi

    otp_length=${#est_otp}
    if [ "$otp_length" -lt 10 ] || [ "$otp_length" -gt 40 ]; then
        echo "ERROR: est_otp variable length is not within the range of 10 to 40 characters."
        exit 1
    else
        echo "[*] check est_otp var"
    fi

    theotp=$est_otp

    if [ "$debugprint" -eq 1 ]; then
        echo "[*] check est val: $theotp"
    fi
}


checkvar_macinfo() {
    if [ -z "$mac_wifi" ] || [ -z "$mac_eth" ]; then
        echo "Error: Both mac_wifi and mac_eth must be set."
        exit 1
    fi

    # Regular expression for a valid MAC address
    mac_regex="^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$"

    if [[ ! "$mac_wifi" =~ $mac_regex ]]; then
        echo "Error: mac_wifi is not a valid MAC address."
        exit 1
    else
        echo "[*] check mac_wifi $mac_wifi";
    fi
    if [[ ! "$mac_eth" =~ $mac_regex ]]; then
        echo "Error: mac_eth is not a valid MAC address."
        exit 1
    else
        echo "[*] check mac_eth $mac_eth";
    fi
}


check_uplink() {
    curl $estserverurl --silent > /dev/null 2>&1;
    thetimenow=$(date +"%H:%M:%S %d/%m/%y")
    if [ $? -ne 0 ]; then
        echo "ERROR: can not reach EST server $thetimenow";
        exit 1;
    else
        echo "[*] internet seems OK $thetimenow";
    fi
}


#----------------------------------------------------------
# EST client functions
#----------------------------------------------------------


#
# init - first interaction with EST server. 
# http post with OTP and MAC
#
estclient_hello() {
    echo "[*] create and post auth payload";

    # note system time needs to be correct by NTP
    thetimenow=$(date +%s)

cat <<EOF > "$datastore"/payload1_send.json
{
  "device_type": "Other",
  "id": 1,
  "network_interfaces": [
    { "interface_type": "Wireless", "mac_address": "$mac_wifi" },
    { "interface_type": "Wired", "mac_address": "$mac_eth" }
  ],
  "otp": "$theotp",
  "timestamp": $thetimenow
}
EOF
    ls -la -- "$datastore"/payload1_send.json

    curl \
        --tlsv1.2 \
        --verbose \
        --user-agent "Mozilla/5.0" \
        --cookie-jar "$cookie_jar" \
        --output "$datastore"/payload1.plist \
        -H "Content-Type: application/json" \
        -d @"$datastore"/payload1_send.json \
        $estserverurl/onboard/mdps_qc_enroll.php 2> "$logdir"/curl_payload1.log

    if [ $? -ne 0 ]; then
        echo "ERROR: auth post failed.";
        exit 1;
    fi

    ls -la -- "$datastore"/payload1.plist
}


#
# http get ca cert trust anchor
# https://www.rfc-editor.org/rfc/rfc7030.html#section-4.1
#
get_cacerts() {
    echo "[*] GET /cacerts from EST server";

    curl \
        --tlsv1.2 \
        --verbose \
        --user-agent "Mozilla/5.0" \
        --cookie-jar "$cookie_jar" \
        --cookie "$cookie_jar" \
        --output "$datastore"/ca_root.b64 \
        $estserverurl/.well-known/est/qc:"$theotp"/cacerts 2> "$logdir"/curl_cacerts.log

    if [ $? -ne 0 ]; then
        echo "ERROR: fetching cacerts failed.";
        exit 1;
    fi

    openssl base64 -d -in "$datastore"/ca_root.b64 -out "$datastore"/ca_root.bin
}


#
# convert ca_root.bin to pem format so we can use as trust anchor:
# $ curl --cacert $datastore/ca_root.pem
#
get_cacerts_process() {
    echo "[*] convert ca_root.bin to ca_root.pem for client trust anchor";

    openssl pkcs7 -in "$datastore"/ca_root.bin -inform DER -out "$datastore"/ca_root.pem -outform PEM
}


#
# EST client requests a list of CA-desired CSR attributes from the CA by sending an HTTPS GET
# https://www.rfc-editor.org/rfc/rfc7030.html#section-4.5
#
get_csrattr() {
    echo "[*] GET /csrattrs info from EST server";

    curl \
        --tlsv1.2 \
        --verbose \
        --user-agent "Mozilla/5.0" \
        --cookie-jar "$cookie_jar" \
        --cookie "$cookie_jar" \
        --output "$datastore"/ca_csrattr.b64 \
        $estserverurl/.well-known/est/qc:"$theotp"/csrattrs 2> "$logdir"/curl_csrattr.log

    if [ $? -ne 0 ]; then
        echo "ERROR: fetching csrattrs failed.";
        exit 1;
    fi

    openssl base64 -d -in "$datastore"/ca_csrattr.b64 -out "$datastore"/ca_csrattr.bin
    openssl asn1parse -inform DER -in "$datastore"/ca_csrattr.bin > "$datastore"/ca_csrattr.txt
}


#
# create private key for CSR
#
estclient_csr_mykeys() {
    if [ ! -f "$datastore/private_key.pem" ]; then
        
        echo "[*] create private key";
        openssl genpkey -algorithm RSA \
            -out "$datastore"/private_key.pem \
            -pkeyopt rsa_keygen_bits:4096 &> /dev/null
        
        if [ $? -ne 0 ]; then
            echo "ERROR: failed to gen private key.";
            exit 1;
        fi
    else
        echo "[*] private key already exists";
    fi

    ls -la -- "$datastore"/private_key.pem;

    # private key info
    if [ "$debugprint" -eq 1 ]; then
        echo "----- private_key.pem ----- ";
        openssl rsa -in "$datastore"/private_key.pem -noout -modulus
        echo "-------------------- ";
    fi
}


#
# EST client to create a certificate signing request
# https://www.rfc-editor.org/rfc/rfc8951.html#name-clarification-of-asn1-for-c
#
# note: OpenSSL v3 discourages RSA-1 signatures - can cause errors
#
estclient_csr_gen() {
    echo "[*] Create CSR config file";

cat <<EOF > "$datastore"/csr_config.cnf
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
prompt             = no

[ req_distinguished_name ]
CN = Request Linux Certificate
EOF
    ls -la -- "$datastore"/csr_config.cnf

    echo "[*] Gen CSR cert";
    openssl req \
        -sha1 \
        -new -key "$datastore"/private_key.pem \
        -out "$datastore"/csr_mydevice.csr \
        -config "$datastore"/csr_config.cnf 

    # View the CSR:
    if [ "$debugprint" -eq 1 ]; then
        openssl req -in "$datastore"/csr_mydevice.csr -text -noout
    fi

    # strip --- comments from cert. Need extra leading and trailing newlines in output
    # otherwise we see this error from server reply:
    #   Error parsing CSR: Unexpected identifier (0x0a) when looking for SEQUENCE at offset 0
    sed -e 's/^---.*//g' "$datastore"/csr_mydevice.csr > "$datastore"/csr_mydevice_fix.csr
}


#
# EST client http post CSR
# and then server will reply with our wifi certificate
#

estclient_csr_post_new() {
    echo "[*] POST csr_mydevice_fix.csr to /simpleenroll";

    curl \
        --tlsv1.2 \
        --verbose \
        --user-agent "Mozilla/5.0" \
        --cookie-jar "$cookie_jar" \
        --cookie "$cookie_jar" \
        --output "$datastore"/csr_post_reply.b64 \
        --header "Content-Type: application/csrattrs" \
        --data-binary @"$datastore"/csr_mydevice_fix.csr \
        $estserverurl/.well-known/est/qc:"$theotp"/simplereenroll 2> "$logdir"/curl_simpleenroll.log

    echo "[*] Reply from CSR post simpleenroll";
    ls -la -- "$datastore"/csr_post_reply.b64
}

estclient_csr_post_exist() {
    echo "[*] POST csr_mydevice_fix.csr to /simplereenroll";

    curl \
        --tlsv1.2 \
        --verbose \
        --user-agent "Mozilla/5.0" \
        --cookie-jar "$cookie_jar" \
        --cookie "$cookie_jar" \
        --output "$datastore"/csr_post_reply.b64 \
        --header "Content-Type: application/csrattrs" \
        --data-binary @"$datastore"/csr_mydevice_fix.csr \
        $estserverurl/.well-known/est/qc:"$theotp"/simplereenroll 2> "$logdir"/curl_simplereenroll1.log

    echo "[*] Reply from CSR post simpleReenroll";
    ls -la -- "$datastore"/csr_post_reply.b64
}


#
# process the file we get back from doing CSR
# "$datastore"/csr_post_reply.b64
#
estclient_csr_certback() {
    echo "[*] Assemble PKCS7 cert from CSR";

    echo "-----BEGIN PKCS7-----" > "$datastore"/client.pk
    cat "$datastore"/csr_post_reply.b64 >> "$datastore"/client.pk
    echo "-----END PKCS7-----" >> "$datastore"/client.pk
    ls -la -- "$datastore"/client.pk

    echo "[*] convert client PKCS7 cert to pem";
    openssl pkcs7 -in "$datastore"/client.pk -print_certs > "$datastore"/client.pem
    ls -la -- "$datastore"/client.pem;

    echo "[*] CSR Common name:";
    openssl x509 -in "$datastore"/client.pem -text -noout | grep -i "CN" || { echo "BAD CSR Reply" && exit 1; }

    # should have same modulus as private_key.pem
    if [ "$debugprint" -eq 1 ]; then
        echo "----- client.pem -----";
        openssl x509 -in "$datastore"/client.pem -noout -modulus
        echo "----------------------";
    fi
}


#
# output wifi client info
#
estclient_wifi_client_cnf() {
    echo "==========================";
    echo "..:: wifi client info ::.."
    echo "==========================";
    echo "SSID: eduroam-unsw + eduroam";
    echo "security: WPA / WPA2 Enterprise";
    echo "key-mgmt: wpa-eap";
    echo "eap: tls";
    echo "phase2-auth: mschapv2";
    echo " ";
    echo "User Name: in data/payload1.plist";
    echo "User Password: in data/payload1.plist";
    echo "client cert: data/client.pem";
    echo "private key: data/private_key.pem";
    echo " ";
    echo "ca cert: in data/payload1.plist at bottom";
    echo " ";
    echo "==========================";
}


#----------------------------------------------------------
# logic / action
#----------------------------------------------------------


#
# /simpleenroll - requests a new certificate
# https://www.rfc-editor.org/rfc/rfc7030.html#section-4.2.1
#
do_enroll() {
    echo "[*] starting Enroll (new)";
    check_dependencies;
    check_uplink;
    checkvar_otp;
    checkvar_macinfo;
    estclient_csr_mykeys;
    estclient_hello;
    get_cacerts;
    get_cacerts_process;
    get_csrattr;
    estclient_csr_gen;
    estclient_csr_post_new;
    estclient_csr_certback;
    estclient_wifi_client_cnf;
    echo "[*] finished Enroll";
    exit 0;
}


#
# /simplereenroll - renews an existing certificate
# https://www.rfc-editor.org/rfc/rfc7030.html#section-4.2.2
#
do_reenroll() {
    echo "[*] starting ReEnroll (existing)";
    check_dependencies;
    check_uplink;
    checkvar_otp;
    checkvar_macinfo;
    estclient_csr_mykeys;
    estclient_hello;
    echo " TODO CSR";
    echo "[*] finished ReEnroll";
    exit 0;
}


#----------------------------------------------------------
# main
#----------------------------------------------------------


if [ $# -eq 0 ]; then
    show_help
fi


while [[ "$1" =~ ^- ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --version)
            show_version
            ;;
        --enroll)
            do_enroll
            ;;
        --reenroll)
            do_reenroll
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

#----------------------------------------------------------
