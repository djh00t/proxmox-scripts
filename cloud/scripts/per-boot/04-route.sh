#!/bin/bash
###
### Script to find and configure management and public interfaces
###
### This script will:
### 1. Find the management interface
### 2. Find the public interface (if it exists)
### 3. Find the IPv4 & IPv6 default gateways for the management interface
### 4. Find the IPv4 & IPv6 default gateways for the public interface
### 5. Install yq yaml cli toolset to allow netplan YAML manipulation
### 6. Remove legacy default route configurations from both interfaces
### 7. Configure interface specific routes with $ROUTES_METRIC set
### 8. Configure a backup default route on the management interface with a metric of 254
### 9. Remove excessive DNS servers from public interface (K8S can only have 3 DNS servers maximum)
### 10. Test to make sure that expected routes are present on each interface

# Set $CONF to netplan config file
CONF="/etc/netplan/50-cloud-init.yaml"
CONF_SHORT=$(basename $CONF)
BACKUP_DIR="$HOME/.config/netplan/"

# Add global IPv4 and IPv6 array entries
V=(4 6)

###
### Management NIC Configuration
###
ROUTES_MGMT4=(10.0.0.0/8 172.16.0.0/12)
ROUTES_MGMT_METRIC4=10
ROUTES_MGMT6=(::/0)
ROUTES_MGMT_METRIC6=254

###
### Public NIC Configuration
###
ROUTES_PUBLIC4=(0.0.0.0/0)
ROUTES_PUBLIC_METRIC4=10
ROUTES_PUBLIC6=(::/0)
ROUTES_PUBLIC_METRIC6=10

function get() {
    # Show what $CONF looks like now
    echo -e "=================================================================================="
    echo
    cat $CONF
    echo
    echo -e "=================================================================================="
}

function debug() {
    # echo $1 to screen if $DEBUG is set to 1
    if [ "$DEBUG" == "1" ]; then
        echo -e "| CORE\t\tDEBUG\t\t$1"
    fi
}

###
### Setup Environment Variables
###

# Get management interface name
INTERFACE_MGMT=$(ip link show | grep -e ^2\:\  | awk '{ print $2 }')
# Remove trailing colon from $INTERFACE_PUBLIC
INTERFACE_MGMT=${INTERFACE_MGMT::-1}

# Get public Interface name
INTERFACE_PUBLIC=$(ip link show | grep -e ^3\:\  | awk '{ print $2 }')
# Remove trailing colon from $INTERFACE_PUBLIC
INTERFACE_PUBLIC=${INTERFACE_PUBLIC::-1}

# If $INTERFACE_MGMT is empty echo an alert and set $INTERFACE_MGMT to 'none'
if [ -z "$INTERFACE_MGMT" ]; then
    echo -e " --------------------------------------------------------------------------------------------"
    echo -e "| CORE\t\tFAIL\t\tManagement interface:\tMissing!"
    unset INTERFACE_MGMT
else
    echo -e " --------------------------------------------------------------------------------------------"
    echo -e "| CORE\t\tOK\t\tManagement interface:\t$INTERFACE_MGMT"
    

    # Check if $INTERFACE_MGMT in $CONF is using gateway4 statements or route statements and import them into $ROUTES_MGMT_GATEWAY4
    ROUTES_MGMT_GATEWAY4=$(yq -e ".network.ethernets.$INTERFACE_MGMT.gateway4" $CONF 2>/dev/null)
    # If $ROUTES_MGMT_GATEWAY4 is "null" try finding a route statement
    if [ "$ROUTES_MGMT_GATEWAY4" == "null" ]; then
        eval ROUTES_MGMT_GATEWAY4=$(yq -e '.network.ethernets.'$INTERFACE_MGMT'.routes[] | select(.to == "0.0.0.0/0" or .to == "default" or .to == "10.0.0.0/8" or .to == "172.16.0.0/12")| .via' $CONF | uniq)
    fi
    debug "ROUTES_MGMT_GATEWAY4: $ROUTES_MGMT_GATEWAY4"

    # Check if $INTERFACE_MGMT in $CONF is using gateway6 statements or route statements and import them into $ROUTES_MGMT_GATEWAY6
    ROUTES_MGMT_GATEWAY6=$(yq -e '.network.ethernets.'$INTERFACE_MGMT'.gateway6' $CONF 2>/dev/null)
    # If $ROUTES_MGMT_GATEWAY6 is "null" try finding a route statement
    if [ "$ROUTES_MGMT_GATEWAY6" == "null" ]; then
        eval ROUTES_MGMT_GATEWAY6=$(yq -e '.network.ethernets.'$INTERFACE_MGMT'.routes[] | select(.to == "::/0")| .via' $CONF | uniq)
    fi
    debug "ROUTES_MGMT_GATEWAY6: $ROUTES_MGMT_GATEWAY6"
fi

# If $INTERFACE_PUBLIC is empty echo an alert and set $INTERFACE_PUBLIC to 'none'
if [ -z "$INTERFACE_PUBLIC" ]; then
    echo -e "| CORE\t\tFAIL\t\tPublic interface:\tMissing!"
    echo -e " --------------------------------------------------------------------------------------------"
    unset INTERFACE_PUBLIC
else
    echo -e "| CORE\t\tOK\t\tPublic interface:\t$INTERFACE_PUBLIC"
    echo -e " --------------------------------------------------------------------------------------------"

    # Check if $INTERFACE_PUBLIC in $CONF is using gateway4 statements or route statements and import them into $ROUTES_PUBLIC_GATEWAY4
    ROUTES_PUBLIC_GATEWAY4=$(yq -e ".network.ethernets.$INTERFACE_PUBLIC.gateway4" $CONF 2>/dev/null)
    # If $ROUTES_PUBLIC_GATEWAY4 is "null" try finding a route statement
    if [ "$ROUTES_PUBLIC_GATEWAY4" == "null" ]; then
        eval ROUTES_PUBLIC_GATEWAY4=$(yq -e '.network.ethernets.'$INTERFACE_PUBLIC'.routes[] | select(.to == "0.0.0.0/0" or .to == "default")| .via' $CONF | uniq)
    fi
    debug "ROUTES_PUBLIC_GATEWAY4: $ROUTES_PUBLIC_GATEWAY4"

    # Check if $INTERFACE_PUBLIC in $CONF is using gateway6 statements or route statements and import them into $ROUTES_PUBLIC_GATEWAY6
    ROUTES_PUBLIC_GATEWAY6=$(yq -e ".network.ethernets.$INTERFACE_PUBLIC.gateway6" $CONF 2>/dev/null)
    # If $ROUTES_PUBLIC_GATEWAY6 is "null" try finding a route statement
    if [ "$ROUTES_PUBLIC_GATEWAY6" == "null" ]; then
        eval ROUTES_PUBLIC_GATEWAY6=$(yq -e '.network.ethernets.'$INTERFACE_PUBLIC'.routes[] | select(.to == "::/0")| .via' $CONF | uniq)
    fi
    debug "ROUTES_PUBLIC_GATEWAY6: $ROUTES_PUBLIC_GATEWAY6"
fi

function install_yq() {
    # Install yq if it is not installed
    if ! command -v yq &>/dev/null; then
        echo -e "| CORE\t\tADD\t\tyq CLI tools not found, installing.."

        # Install yq yaml cli toolset
        wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&
            chmod +x /usr/bin/yq

        # Add yq bash autocompletion
        yq shell-completion bash >/etc/bash_completion.d/yq
    else
        debug "CORE\t\tOK\t\tyq CLI tools found, skipping install.."
    fi
}

function config_backup() {
    # Check if $BACKUP_DIR exists if not create it
    if [ ! -d "$BACKUP_DIR" ]; then
        echo
        echo -e "| CORE\t\tADD\t\t$BACKUP_DIR does not exist, creating it.."
        mkdir -p $BACKUP_DIR
        debug "CORE\t\tOK\t\tDone."
    fi
    # Take backup of $CONF
    cp $CONF $BACKUP_DIR/$CONF_SHORT
}

function config_restore() {
    # Restore $CONF from backup
    echo
    echo -e "| CORE\t\tFAIL\t\tRestoring $CONF from backup.."
    echo
    cp $BACKUP_DIR/$CONF_SHORT $CONF
    echo -e "| CORE\t\tFAIL\t\tDone."
}

function routes_delete_legacy_gw() {
    # Delete legacy default route configurations for ipv4 and ipv6 from $ETH if they exist
    for i in "${V[@]}"; do
        TEXT="legacy $ETH.gateway$i default gateway"
        # Check if legacy default gateway exists in $CONF
        ERR=$(
            yq -e '.network.ethernets.'$ETH'.gateway'$i'' $CONF &>/dev/null
            echo $?
        )
        # If $ERR=0, legacy default gateway exists in $CONF so delete it
        # If $ERR=1, legacy default gateway does not exist in $CONF so skip
        if [ "$ERR" = "0" ]; then
            debug "| $ETH\t\tFIX\t\tA $TEXT exists, deleting it.."
            yq -e 'del(.network.ethernets.'$ETH'.gateway'$i')' -i $CONF
        else
            debug "| $ETH\t\tSKIP\t\tA $TEXT does not exist, skipping.."
        fi
    done
}

function routes_check_if_exist() {
    # Set INTERFACE to $1
    INTERFACE=$1
    # Set ROUTE to $2
    ROUTE=$2

    # Check if $ROUTE exists on $INTERFACE in $CONF
    ERR=$(
        yq -e '.network.ethernets.'$INTERFACE'.routes[] | select(.to == "'$ROUTE'")' $CONF &>/dev/null
        echo $?
    )
    # If $ERR=0, $ROUTE exists on $INTERFACE in $CONF so delete it
    # If $ERR=1, $ROUTE does not exist on $INTERFACE in $CONF so skip
    if [ "$ERR" = "0" ]; then
        debug "| $INTERFACE\t\tFIX\t\tA route to $ROUTE exists, deleting it.."
        yq -e 'del(.network.ethernets.'$INTERFACE'.routes[] | select(.to == "'$ROUTE'"))' -i $CONF
    else
        debug "| $INTERFACE\t\tSKIP\t\tA route to $ROUTE does not exist, skipping.."
    fi
}

function routes_add_interface_routes() {
    INTERFACES=($(yq -e '.network.ethernets| keys' $CONF | cut -c 3-))

    debug "| $ETH\t\tADD\t\tAdding IPv4 routes.."
    for j in "${ROUTES4[@]}"; do
        # Check to see if route already exists on this interface
        routes_check_if_exist $ETH $j
        # Add route to $ETH
        debug "| $ETH\t\tADD\t\tAdding IPv4 route $j to $ETH.."
        yq -e '.network.ethernets.'$ETH'.routes += [{"to": "'$j'", "via": "'$ROUTES_GATEWAY4'", "metric": "'$ROUTES_METRIC4'", "on-link": true}]' -i $CONF
    done

    # If $ETH = $INTERFACE_MGMT add backup default route
    if [ "$ETH" = "$INTERFACE_MGMT" ]; then
        # Check to see if route already exists on this interface
        routes_check_if_exist $ETH 0.0.0.0/0
        # Add route to $ETH
        debug "| $ETH\t\tADD\t\tAdding IPv4 backup default route to $ETH.."
        yq -e '.network.ethernets.'$ETH'.routes += [{"to": "0.0.0.0/0", "via": "'$ROUTES_GATEWAY4'", "metric": 254, "on-link": true}]' -i $CONF
    fi

    debug "| $ETH\t\tADD\t\tAdding IPv6 routes.."
    for j in "${ROUTES6[@]}"; do
        # Check to see if route already exists on this interface
        routes_check_if_exist $ETH $j
        # Add route to $ETH
        debug "| $ETH\t\tADD\t\tAdding IPv6 route $j to $ETH.."
        yq -e '.network.ethernets.'$ETH'.routes += [{"to": "'$j'", "via": "'$ROUTES_GATEWAY6'", "metric": "'$ROUTES_METRIC6'", "on-link": true}]' -i $CONF
    done
}

function routes_test() {
    # Make sure routes are configured correctly
    V=(4 6)
    for i in ${V[@]}; do
        debug "| Testing $ps IPv$i routes.."
        # Set $ROUTES to $ROUTES4 or $ROUTES6
        eval "ROUTES=(\"\${ROUTES$i[@]}\")"
        debug "| Testing $ps routes to ${ROUTES[@]}"

        # Set $ROUTES_METRIC to $ROUTES_METRIC4 or $ROUTES_METRIC6
        eval "ROUTES_METRIC=\$ROUTES_METRIC$i"
        debug "| Testing $ps routes with metric $ROUTES_METRIC"

        # Set $ROUTES_GATEWAY to ROUTES_GATEWAY4 or ROUTES_GATEWAY6
        eval "ROUTES_GATEWAY=\$ROUTES_GATEWAY$i"
        debug "| Testing $ps routes with gateway $ROUTES_GATEWAY"

        for r in "${ROUTES[@]}"; do
            debug "| $ETH\t\tTEST - $ps route to $r via $ROUTES_GATEWAY with metric $ROUTES_METRIC and on-link enabled.."
            # Set common response string
            TEXT="Route to $r via $ROUTES_GATEWAY with metric $ROUTES_METRIC and on-link enabled"
            ERR=$(
                yq -e '.network.ethernets.'$ETH'.routes[] | select(.to == "'"$r"'" and .via == "'"$ROUTES_GATEWAY"'" and .on-link == 'true')' $CONF &>/dev/null
                echo $?
            )
            if [ "$ERR" = "1" ]; then
                echo -e "| $ETH\t\tFAIL\t\t$TEXT does not exist, test has failed!"
                echo
                echo -e "| CORE\t\tRESTORE\t\tRestoring $CONF from backup and exiting.."
                config_restore
                exit 1
            else
                debug "| $ETH\t\tPASS\t\t$TEXT exists, test passed.."
            fi
        done
        # Cleanup Variables
        unset ROUTES ROUTES_METRIC ROUTES_GATEWAY
    done
}

function dns_delete_public() {
    # Check if $INTERFACE_MGMT exists and count how many nameservers are defined for it
    IFMGT=$(yq -e '.network.ethernets.'$INTERFACE_MGMT'.nameservers.addresses' $CONF 2>/dev/null | grep -v "null" | grep -v "no matches found" | wc -l)

    # If $IFMGT has greater than 0 nameservers defined, proceed. If it has 0 nameservers defined exit 1 telling the user to define nameservers for $INTERFACE_MGMT
    if [ "$IFMGT" -gt 0 ]; then
        debug "| $INTERFACE_MGMT\t\tOK\t\t$IFMGT nameservers are defined.."
    else
        echo -e "| $INTERFACE_MGMT\t\FAIL\t\tNo nameservers defined for $INTERFACE_MGMT!!!"
        echo -e "| $INTERFACE_MGMT\t\FAIL\t\tPlease define nameservers for $INTERFACE_MGMT in $CONF and re-run this script.."
        echo -e "| CORE\t\FAIL\t\tRestoring $CONF from backup.."
        config_restore
        exit 1
    fi

    # Check if $INTERFACE_PUBLIC exists and count how many nameservers are defined for it
    IFPUB=$(yq -e '.network.ethernets.'$INTERFACE_PUBLIC'.nameservers.addresses' $CONF 2>/dev/null | grep -v "null" | grep -v "no matches found" | wc -l)

    # If $IFPUB has greater than 0 nameservers defined, delete them all. If it has 0 nameservers defined continue.
    if [ "$IFPUB" -gt 0 ]; then
        debug "| $INTERFACE_PUBLIC\t\FAIL\t\t$IFPUB nameservers are defined.."
        debug "| $INTERFACE_PUBLIC\t\tFIX\t\tDeleting all nameservers from $INTERFACE_PUBLIC.."
        yq -e 'del(.network.ethernets.'$INTERFACE_PUBLIC'.nameservers)' -i $CONF
    else
        debug "$INTERFACE_PUBLIC\t\tOK\t\tNo nameservers defined.."
    fi
}

debug -e "########################################################################"
debug -e "#                   NETWORK/ROUTING BOOT SCRIPT                        #"
debug -e "########################################################################"

# Install yq YAML cli toolset
install_yq

# Backup $CONF in case something goes wrong
config_backup

###
### Active traffic testing
###
# Read in CSV data and run ping tests against each row of the CSV data below.
# Return PASS if $? of the ping command matches the EXPECTED_RESULT column.
# Return FAIL if $? of the ping command does not match the EXPECTED_RESULT column.
#
# Ping command example:
#  ping -$IPv -a -c 3 -W 1 -I $INTERFACE $DESTINATION
#
# Example results:
#  Interface             Destination                 Description     Expected Result    Actual Result
#  $INTERFACE_MGMT   4   $ROUTES_MGMT_GATEWAY4    Default GW      PASS               PASS
#  $INTERFACE_MGMT   4   172.16.0.10                 DNS Server      PASS               PASS
#  $INTERFACE_MGMT   4   1.1.1.1                     Cloudflare DNS  PASS               PASS
#  $INTERFACE_MGMT   4   8.8.8.8                     Google DNS      PASS               PASS
#  $INTERFACE_MGMT   4   172.16.0.254                Non-Existent    FAIL               FAIL
#  $INTERFACE_MGMT   4   10.100.100.100              Non-Existent    FAIL               FAIL
#  $INTERFACE_MGMT   6   $ROUTES_MGMT_GATEWAY6       Default GW      PASS               PASS
#  $INTERFACE_MGMT   6   2606:4700:4700::1111        Cloudflare DNS  FAIL               FAIL
#  $INTERFACE_MGMT   6   2001:4860:4860::8888        Google DNS      FAIL               FAIL
#  $INTERFACE_MGMT   6   2606:4700:4700::1001        Non-Existent    FAIL               FAIL
#  $INTERFACE_MGMT   6   2001:db8::1                 Non-Existent    FAIL               FAIL
#  $INTERFACE_PUBLIC 4   $ROUTES_PUBLIC_GATEWAY4     Default GW      PASS               PASS
#  $INTERFACE_PUBLIC 4   1.1.1.1                     Cloudflare DNS  PASS               PASS
#  $INTERFACE_PUBLIC 4   8.8.8.8                     Google DNS      PASS               PASS
#  $INTERFACE_PUBLIC 6   $ROUTES_PUBLIC_GATEWAY6     Default GW      PASS               PASS
#  $INTERFACE_PUBLIC 6   2606:4700:4700::1111        Cloudflare DNS  PASS               PASS
#  $INTERFACE_PUBLIC 6   2001:4860:4860::8888        Google DNS      PASS               PASS
#  $INTERFACE_PUBLIC 6   2606:4700:4700::1001        Non-Existent    FAIL               FAIL
#
# Imported CSV format:
# INTERFACE,IPv,DESTINATION,DESCRIPTION,EXPECTED_RESULT
#   INTERFACE: Interface to run ping test from
#   IPv: IPv4 or IPv6
#   DESTINATION: Destination to ping
#   DESCRIPTION: Description of test
#   EXPECTED_RESULT: 0 for PASS, 1 for FAIL

# CSV Test Data
CSV="INTERFACE,IPv,DESTINATION,DESCRIPTION,EXPECTED_RESULT
$INTERFACE_MGMT,4,$ROUTES_MGMT_GATEWAY4,Default GW,0
$INTERFACE_MGMT,4,172.16.0.10,DNS Server,0
$INTERFACE_MGMT,4,1.1.1.1,Cloudflare DNS,0
$INTERFACE_MGMT,4,8.8.8.8,Google DNS,0
$INTERFACE_MGMT,4,172.16.0.254,Non-Existent RFC1918,1
$INTERFACE_MGMT,4,10.100.100.100,Non-Existent RFC1918,1
$INTERFACE_MGMT,6,$ROUTES_MGMT_GATEWAY6,Default GW,0
$INTERFACE_MGMT,6,2606:4700::1111,Cloudflare DNS,1
$INTERFACE_MGMT,6,2001:4860:4860::8888,Google DNS,1
$INTERFACE_MGMT,6,2001:db8::1,Non Existent IPv6,1
$INTERFACE_PUBLIC,4,$ROUTES_PUBLIC_GATEWAY4,Default GW,0
$INTERFACE_PUBLIC,4,1.1.1.1,Cloudflare DNS,0
$INTERFACE_PUBLIC,4,8.8.8.8,Google DNS,0
$INTERFACE_PUBLIC,6,$ROUTES_PUBLIC_GATEWAY6,Default GW,0
$INTERFACE_PUBLIC,6,2606:4700::1111,Cloudflare DNS,0
$INTERFACE_PUBLIC,6,2001:4860:4860::8888,Google DNS,0
$INTERFACE_PUBLIC,6,2001:db8::1,Non Existent IPv6,1"

# Function that runs ping test and returns PASS or FAIL in format above, using CSV data from variable $CSV
function ping_test() {
    COUNTER=0
    while IFS= read -r line; do
        COUNTER=$((COUNTER + 1))
        # echo -e "Line $COUNTER: $line"

        # Read comma separated values into an array
        IFS=',' read -r -a array <<<"$line"
        INTERFACE=${array[0]}
        IPv=${array[1]}
        DESTINATION=${array[2]}
        DESCRIPTION=${array[3]}
        EXPECTED_RESULT=${array[4]}

        # Run ping test
        # If IPv is 4, use -4, if IPv is 6, use -6
        if [ "$IPv" == "4" ]; then
            # echo -e "ping -4 -a -c 3 -W 1 -I ${INTERFACE} ${DESTINATION} > /dev/null 2>&1"
            ping -4 -c 1 -W 0.5 -I ${INTERFACE} ${DESTINATION} >/dev/null 2>&1
            ERRLVL=$?
            # echo -e "ERRLVL:          $ERRLVL"
        elif [ "$IPv" == "6" ]; then
            # echo -e "ping -6 -c 3 -W 1 -I ${INTERFACE} ${DESTINATION} > /dev/null 2>&1"
            ping -6 -c 1 -W 0.5 -I ${INTERFACE} ${DESTINATION} >/dev/null 2>&1
            ERRLVL=$?
            # echo -e "ERRLVL:           $ERRLVL"
        fi

        # If $ERRLVL is 0, set to PASS, if $ERRLVL is 1, set to FAIL
        if [ "$ERRLVL" == "0" ]; then
            ACTUAL_RESULT="PASS"
        elif [ "$ERRLVL" == "1" ]; then
            ACTUAL_RESULT="FAIL"
        fi

        # If $EXPECTED_RESULT is 0, set to PASS, if $EXPECTED_RESULT is 1, set to FAIL
        if [ "$EXPECTED_RESULT" == "0" ]; then
            EXPECTED_RESULT="PASS"
        elif [ "$EXPECTED_RESULT" == "1" ]; then
            EXPECTED_RESULT="FAIL"
        fi

        # If ACTUAL_RESULT does not match EXPECTED_RESULT, set OKFAIL to FAIL, else set OKFAIL to PASS
        if [ "$ACTUAL_RESULT" != "$EXPECTED_RESULT" ]; then
            OKFAIL="FAIL"
        else
            OKFAIL="OK"
        fi

        echo -e "$COUNTER|$INTERFACE IPv$IPv|$DESTINATION|$DESCRIPTION|$EXPECTED_RESULT|$ACTUAL_RESULT|$OKFAIL"

    done < <(echo -e "${CSV}" | tail -n +2)
}

###
### ping_test results formats
###
# These functions will provide ping_test results in various formats including:
#  - Pretty Text (default)
#  - Pipe Separated Values (default)
#  - Tab Separated Values (screen friendly)
#  - CSV
#  - JSON
#  - YAML

# Pretty Text Output
function ping_test_pretty() {
    # If csvkit isn't installed on the system, install it
    if ! command -v csvjson &>/dev/null; then
        echo -e "csvkit not installed, installing..."
        DEBIAN_FRONTEND=noninteractive sudo apt-get install -y csvkit
    fi
    # Header Row

    PRETTY="TEST|INTERFACE|DESTINATION|DESCRIPTION|EXPECT|ACTUAL|OK/FAIL"
    PRETTY=$PRETTY$'\n'
    PRETTY+=$(ping_test)
    echo -e " --------------------------------------------------------------------------------------------"
    echo -e "$PRETTY" | csvlook
    echo -e " --------------------------------------------------------------------------------------------"
}

function ping_test_psv() {
    # Generate Pipe Separated Values output
    echo -e "TEST|INTERFACE|DESTINATION|DESCRIPTION|EXPECT|ACTUAL|OK/FAIL"
    ping_test
}

function ping_test_tsv() {
    # Generate Tab Separated Values output
    ping_test | column -t -s "|" --table-columns TEST,INTERFACE,DESTINATION,DESCRIPTION,EXPECT,ACTUAL,OK/FAIL
}

# Function that formats ping_test results in CSV
function ping_test_csv() {
    echo -e "TEST,INTERFACE,DESTINATION,DESCRIPTION,EXPECT,ACTUAL,OK/FAIL"
    ping_test | sed 's/|/,/g'
}

# Function that formats ping_test results in JSON
function ping_test_json() {
    # Generate JSON output
    ping_test | column -t -s "|" --table-columns TEST,INTERFACE,DESTINATION,DESCRIPTION,EXPECT,ACTUAL,OK/FAIL -J
}

# Function that formats ping_test results in YAML
function ping_test_yaml() {
    # Generate YAML output
    ping_test | column -t -s "|" --table-columns TEST,INTERFACE,DESTINATION,DESCRIPTION,EXPECT,ACTUAL,OK/FAIL -J | yq -p=json
}

function help() {
    # Script arguments
    echo -e "Usage: $0 [OPTION]..."
    echo
    echo -e "  -c, --csv       Display ping_test results in comma separated values format"
    echo -e "  -d, --debug     Display debug information while executing"
    echo -e "  -h, --help      Display this help and exit"
    echo -e "  -j, --json      Display ping_test results in JSON format"
    echo -e "  -p, --pretty    Display ping_test results in pretty text format (default)"
    echo -e "  -s, --psv       Display ping_test results in pipe separated values format"
    echo -e "  -t, --tsv       Display ping_test results in tab separated values format"
    echo -e "  -y, --yaml      Display ping_test results in YAML format"
}

# Script arguments
while [ "$1" != "" ]; do
    case $1 in
    -c | --csv)
        set OUTPUT=CSV
        shift
        ;;
    -d | --debug)
        set DEBUG=1
        shift
        ;;
    -h | --help)
        help
        exit
        ;;
    -j | --json)
        set OUTPUT=JSON
        shift
        ;;
    -p | --pretty)
        set OUTPUT=PRETTY
        shift
        ;;
    -s | --psv)
        set OUTPUT=PSV
        shift
        ;;
    -t | --tsv)
        set OUTPUT=TSV
        shift
        ;;
    -y | --yaml)
        set OUTPUT=YAML
        shift
        ;;
    *)
        set OUTPUT=PRETTY
        shift
        ;;
    esac
done

###
### Management NIC Changes
###
ETH=$INTERFACE_MGMT
ROUTES4=(${ROUTES_MGMT4[@]})
ROUTES_METRIC4=$ROUTES_MGMT_METRIC4
ROUTES_GATEWAY4=$ROUTES_MGMT_GATEWAY4
ROUTES6=(${ROUTES_MGMT6[@]})
ROUTES_METRIC6=$ROUTES_MGMT_METRIC6
ROUTES_GATEWAY6=$ROUTES_MGMT_GATEWAY6
debug " --------------------------------------------------------------------------------------------"
debug "ETH:             $ETH"
debug "ROUTES4:         ${ROUTES4[@]}"
debug "ROUTES_METRIC4:  $ROUTES_METRIC4"
debug "ROUTES6:         ${ROUTES6[@]}"
debug "ROUTES_METRIC6:  $ROUTES_METRIC6"
debug " --------------------------------------------------------------------------------------------"

# Delete legacy default IPv4 and IPv6 route configurations from $ETH if they exist
routes_delete_legacy_gw

# Add IPv4 and IPv6 routes to $ETH with metric set to $ROUTES_METRIC if they are defined in
# $ROUTES4, $ROUTES6, $ROUTES_METRIC4, $ROUTES_METRIC6 and don't exist in $CONF already
routes_add_interface_routes

# Make sure that correct routes exist in $CONF on correct interface
# If not raise alarm and exit 1
routes_test

###
### Public NIC Changes
###
ETH=$INTERFACE_PUBLIC
ROUTES4=(${ROUTES_PUBLIC4[@]})
ROUTES_METRIC4=$ROUTES_PUBLIC_METRIC4
ROUTES_GATEWAY4=$ROUTES_PUBLIC_GATEWAY4
ROUTES6=(${ROUTES_PUBLIC6[@]})
ROUTES_METRIC6=$ROUTES_PUBLIC_METRIC6
ROUTES_GATEWAY6=$ROUTES_PUBLIC_GATEWAY6
debug " --------------------------------------------------------------------------------------------"
debug "| ETH:             $ETH"
debug "| ROUTES4:         ${ROUTES4[@]}"
debug "| ROUTES_METRIC4:  $ROUTES_METRIC4"
debug "| ROUTES6:         ${ROUTES6[@]}"
debug "| ROUTES_METRIC6:  $ROUTES_METRIC6"
debug " --------------------------------------------------------------------------------------------"

# Delete legacy default IPv4 and IPv6 route configurations from $ETH if they exist
routes_delete_legacy_gw

# Add IPv4 and IPv6 routes to $ETH with metric set to $ROUTES_METRIC if they are defined in
# $ROUTES4, $ROUTES6, $ROUTES_METRIC4, $ROUTES_METRIC6 and don't exist in $CONF already
routes_add_interface_routes

# Make sure that correct routes exist in $CONF on correct interface
# If not raise alarm and exit 1
routes_test

# Delete excessive DNS servers from '.network.ethernets.$ETH.dns.nameservers' in $CONF
# making sure that $INTERFACE_MGMT does have DNS nameservers defined
dns_delete_public

###
### Testing
###

# Test from both interfaces using IPv4 and IPv6, ensuring results are as expected
case $OUTPUT in
CSV)
    ping_test_csv
    ;;
JSON)
    ping_test_json
    ;;
PRETTY)
    ping_test_pretty
    ;;
PSV)
    ping_test_psv
    ;;
TSV)
    ping_test_tsv
    ;;
YAML)
    ping_test_yaml
    ;;
*) # Default
    ping_test_pretty
    ;;
esac

# Test to see if config is valid using netplan try, capturing stderr to $error
debug "| CORE\t\tINFO\t\tTesting configuration using netplan try"
#error=$(netplan try --timeout 3 --state $BACKUP_DIR --debug 2>&1 >/dev/null)
error=$(netplan try --timeout 3 --debug 2>&1 >/dev/null)
# If $error is not empty, then netplan try failed
if [ -n "$error" ]; then
    # Raise alarm and exit 1
    echo -e "| CORE\t\tERROR\t\tNetplan try failed with error: $error"
    echo -e "| CORE\t\tROLLBACK\tRolling back to original configuration"
    echo -e " --------------------------------------------------------------------------------------------"
    config_restore
    exit 1
else
    # If $error is empty, then netplan try succeeded
    debug "| CORE\t\tSUCCESS\t\tnetplan try succeeded"
    # Apply config using netplan apply
    debug "| CORE\t\tINFO\t\tApplying configuration using netplan apply"
    netplan apply
    echo -e "| CORE\t\tOK\t\tNetplan apply succeeded"
    echo -e " --------------------------------------------------------------------------------------------"
fi

exit 0

#EOF