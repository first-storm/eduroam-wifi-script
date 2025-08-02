# UNSW eduroam Setup Script for Linux

This repository contains a set of scripts to simplify connecting to the UNSW eduroam WiFi network on Linux systems. It features an interactive setup assistant (`run.sh`) that guides you through the entire process, from certificate generation to network configuration.

### Disclaimers

**Original Author's Disclaimer:**
> I am not the author of this script, but I may add code to it. If you do not want my modifications, you can find the original release version in the releases section. This script was sent to me by UNSW IT via email, and I could not find it on any website, so I am sharing it with everyone. If UNSW does not want it to be shared and considers it a copyright violation, please contact me via email to have it removed.

**AI Assistance Disclaimer:**
> The `run.sh` and `extract_certs.sh` scripts, along with this README file, were developed with the assistance of an AI programming assistant (GitHub Copilot) to improve functionality, user experience, and documentation.

## Overview

The original `est-wifi-script.sh` handles the complex process of certificate enrollment. The new `run.sh` script acts as a user-friendly wrapper around it, automating the entire setup.

### Features

- **Interactive Setup:** An easy-to-follow command-line assistant.
- **Flexible Input:** Works with either an `ArubaQuickConnect.sh` file or a manually entered One-Time Password (OTP).
- **Automated Certificate Handling:** Automatically generates device certificates and extracts the necessary CA certificate chain.
- **NetworkManager Integration:** Automatically configures the eduroam connection in NetworkManager if available.
- **Manual Fallback:** Provides clear manual setup instructions if you don't use NetworkManager.

## Scripts in this Repository

- `run.sh`: The main interactive setup script. **This is the script you should run.**
- `extract_certs.sh`: A helper script to extract the UNSW root and issuing CA certificates from the configuration profile.
- `est-wifi-script.sh`: The original script from UNSW IT that handles certificate enrollment over secure transport (EST).

## Prerequisites

Before you begin, ensure you have the following command-line tools installed:
- `bash`
- `curl`
- `openssl`
- `nmcli` (for automatic NetworkManager configuration)
- `xmllint` (often part of `libxml2-utils` or `libxml2`)

You can usually install them with your system's package manager. For example, on Debian/Ubuntu:
```shell
sudo apt-get update
sudo apt-get install curl openssl network-manager libxml2-utils
```

## How to Use

1.  **Download the scripts**
    Clone this repository or download the files to a directory on your computer.

2.  **Get your OTP**
    Download the `ArubaQuickConnect.sh` file for Linux by following the instructions at [UNSW Get Online for Linux](https://www.unsw.edu.au/get-online/standard-unsw-linux-device). The `run.sh` script can automatically extract the OTP from this file.

3.  **Make Scripts Executable**
    Open a terminal, navigate to the directory containing the scripts, and run:
    ```shell
    chmod +x run.sh extract_certs.sh est-wifi-script.sh
    ```

4.  **Run the Setup Assistant**
    Execute the main script:
    ```shell
    ./run.sh
    ```

5.  **Follow the Prompts**
    The script will guide you through the following steps:
    - Choosing your setup method (Aruba file or manual OTP).
    - Entering your MAC address.
    - Confirming certificate generation.
    - Installing the CA certificate.
    - Configuring NetworkManager with your zID and password.

After the script finishes, you should be able to connect to the eduroam network.

## Original Documentation

For technical details about the certificate enrollment protocol (EST) and the original `est-wifi-script.sh`, please see the `README.old.md` file.
