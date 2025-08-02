**Disclaimer:** I am not the author of this script, but I may add code to it. If you do not want my modifications, you can find the original release version in the releases section. This script was sent to me by UNSW IT via email, and I could not find it on any website, so I am sharing it with everyone. If UNSW does not want it to be shared and considers it a copyright violation, please contact me via email to have it removed.

# README

```
#---------------------------------------------------------#
#   ________    ______    _________      RFC 7030 + 8951  #
#  |_   __  | .' ____ \  |  _   _  |                      #
#    | |_ \_| | (___ \_| |_/ | | \_|                      #
#    |  _| _   _.____`.      | |     -- A WiFi enabling   #
#   _| |__/ | | \____) |    _| |_        shell script  -- #
#  |________|  \______.'   |_____|                        #
#   March 2025                            By Craig Martin #
#---------------------------------------------------------#
```

Enterprise Wifi uses certificates in place of passwords, which can be stollen by [WiFi attacks](https://en.wikipedia.org/wiki/Wireless_security). This is a stronger, although less convenient, means of authentication. In enterprise environment typically an agent or [MDM](https://en.wikipedia.org/wiki/Mobile_device_management) manages these certs.

The [Aruba](https://en.wikipedia.org/wiki/Aruba_Networks) [Clearpass](https://arubanetworking.hpe.com/techdocs/ArubaDocPortal/content/cons-cp-home.htm) application uses the [Enrollment over Secure Transport](https://en.wikipedia.org/wiki/Enrollment_over_Secure_Transport) (EST) [protocol](https://datatracker.ietf.org/doc/html/rfc7030) to manage certs, but it only supports Ubuntu. Here we recreate those actions so we can bring wifi to *BSD systems, and Linux built without [glibc](https://www.gnu.org/software/libc/) (eg [Alpine](https://www.alpinelinux.org/) and other [musl](https://musl.libc.org/) based distro).

Requires Bash, [Curl](https://curl.se/), [OpenSSL](https://www.openssl.org/), and sed. Your package manager of choice (apt, homebrew, yum, nix etc) should have all these. Will run from WSL, MacOS, most Linux.

Learn about [x509](https://en.wikipedia.org/wiki/X.509) and [ASN.1](https://en.wikipedia.org/wiki/ASN.1) with practical examples.

**Please read the code before using.**

**This is not intended for general consumption - advanced users only.**

```
SHA256:1a573a8ab1947f43ec2b45eba8388d7ddccd1eeea276e913f7b1cc270e3d02f6 est-wifi-script.sh (0.2.1-beta)
```

## est

EST Layering of Protocols.

```
   +--------------------------------------------+
   | EST request / response messages            |
   +--------------------------------------------+
   | HTTP for message transfer and signaling    |
   +--------------------------------------------+
   | TLS for transport security                 |
   +--------------------------------------------+
   | TCP for transport                          |
   +--------------------------------------------+
```

The EST messages and their corresponding media types for each operation are:

```
   +--------------------+--------------------------+-------------------+
   | Message type       | Request media type       | Request section(s)|
   |                    | Response media type(s)   | Response section  |
   | (per operation)    | Source(s) of types       |                   |
   +====================+==========================+===================+
   | Distribution of CA | N/A                      | Section 4.1       |
   | Certificates       | application/pkcs7-mime   | Section 4.1.1     |
   |                    | [RFC5751]                |                   |
   | /cacerts           |                          |                   |
   +--------------------+--------------------------+-------------------+
   | Client Certificate | application/pkcs10       | Sections 4.2/4.2.1|
   | Request Functions  | application/pkcs7-mime   | Section 4.2.2     |
   |                    | [RFC5967] [RFC5751]      |                   |
   | /simpleenroll      |                          |                   |
   | /simplereenroll    |                          |                   |
   +--------------------+--------------------------+-------------------+
   | CSR Attributes     | N/A                      | Section 4.5.1     |
   |                    | application/csrattrs     | Section 4.5.2     |
   |                    | (This document)          |                   |
   | /csrattrs          |                          |                   |
   +--------------------+--------------------------+-------------------+
```

Process diagram:

```
┌────────────┐                     ┌────────────┐                      ┌────────────┐
│ EST Client │                     │ EST Server │                      │   EST CA   │
└─────┬──────┘                     └──────┬─────┘                      └──────┬─────┘
      │                                   │                                   │
      │     https post OTP and MAC        |                                   |
      ├──────────────────────────────────►│                                   │
      │                                   │                                   │
      │       https get /cacerts          │                                   │
      ├──────────────────────────────────►│                                   │
      │                                   │                                   │
      │             Trust chain           │                                   │
      │◄──────────────────────────────────┤                                   │
      │                                   │                                   │
      │  Validate chain                   │                                   │
      ├───────────────────┐               │                                   │
      │                   │               │                                   │
      │◄──────────────────┘               │                                   │
      │                                   │                                   │
      │  Generate key and CSR             │                                   │
      ├───────────────────┐               │                                   │
      │                   │               │                                   │
      │◄──────────────────┘               │                                   │
      │                                   │                                   │
      │    https post CSR                 │                                   │
      ├──────────────────────────────────►│                                   │
      │                                   │                                   │
      │                                   │ Validate client request           │
      │                                   │                                   │
      │                                   ├─────────────────────┐             │
      │                                   │                     │             │
      │                                   │◄────────────────────┘             │
      │                                   │                                   │
      │                                   │         Request certificate       │
      │                                   ├──────────────────────────────────►│
      │                                   │                                   │
      │                                   │              Certificate          │
      │                                   │◄──────────────────────────────────┤
      │        PKCS#7 Certificate         │                                   │
      │◄──────────────────────────────────┤                                   │
      │                                   │                                   │
      │                                   │                                   │
```

In first post sever will reply with a [plist](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html) file of [x-apple-aspen-config](https://developer.apple.com/documentation/devicemanagement/profile).

#### Ref docs

* https://en.wikipedia.org/wiki/IEEE_802.1X
* https://github.com/santsys/aruba-clearpass-api
* https://github.com/cisco/libest/
* https://github.com/globalsign/est/

## Using

First obtain your 'One Time Password' from the portal. Change your browser to 'linux' to download `ArubaQuickConnect.sh`.

In Chrome / Edge open "More Tools" --> "Developer Tools" --> Network Conditions --> User Agent:

> Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/37.0.2062.94 Chrome/37.0.2062.94 Safari/537.36

Extract your OTP:

```shell
cd ~/Downloads
chmod +x ArubaQuickConnect.sh
./ArubaQuickConnect.sh --check
tail -n +505 ArubaQuickConnect.sh > ArubaQuickConnect.tar.gz
tar -xf ArubaQuickConnect.tar.gz
cat quickconnect/props/config.ini
```

### config

All configuration is set by environment variables.

Export OTP:

```shell
export est_otp="1234567890abcdef"
```

Then your [MAC](https://en.wikipedia.org/wiki/MAC_address) address info:

```shell
export mac_wifi="98:BE:94:XX:XX:02"
export mac_eth="98:BE:94:XX:XX:01"
```

## using

run:

```shell
./est-wifi-script.sh --help
./est-wifi-script.sh --enroll
```

### results

In the plist xml file are two certificates. The PayloadContent describes what they are.

Client cert:

> Issuing Certification Authority

And the root-ca cert:

> Root Certification Authority

Include the headers and footers for each cert:

```
-----BEGIN CERTIFICATE-----
Your Certificate content here
-----END CERTIFICATE-----
```

Create these two extra files, and now you can configure your Wifi.

The client (your device) will present its certificate to the RADIUS server, and the server presents its certificate to the client, ensuring both parties are authenticated.
