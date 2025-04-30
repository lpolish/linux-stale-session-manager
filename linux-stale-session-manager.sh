#!/bin/bash

# Enhanced Stale User Session Manager
# Description: Interactive tool to identify and terminate stale user sessions
# Author: Your Name
# Version: 2.0
# Date: $(date +%Y-%m-%d)

# Configuration
CONFIG_FILE="/etc/stale_session_manager.conf"
LOG_FILE="/var/log/stale_session_manager.log"
DEFAULT_MAX_IDLE=120  # 2 hours in minutes
DEFAULT_WHITELIST=("root" "admin")
DRY_RUN=false
FORCE=false
NOTIFY_ADMIN=false
ADMIN_EMAIL="admin@example.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        MAX_IDLE_MINUTES=$DEFAULT_MAX_IDLE
        WHITELIST=("${DEFAULT_WHITELIST[@]}")
    fi
}

# Initialize logging
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Display header
header() {
    clear
    echo -e "${BLUE}"
    echo "###################################################"
    echo "#      STALE USER SESSION MANAGER v2.0           #"
    echo "###################################################"
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to get idle time in minutes from who -u output
get_idle_time() {
    local idle_string=$1

    if [[ $idle_string == *"days"* ]]; then
        days=$(echo "$idle_string" | awk '{print $1}')
        echo $((days * 1440))
    elif [[ $idle_string == *":"* ]]; then
        hours=$(echo "$idle_string" | cut -d: -f1)
        minutes=$(echo "$idle_string" | cut -d: -f2)
        echo $((hours * 60 + minutes))
    elif [[ $idle_string == *"s"* ]]; then
        echo 0
    else
        echo "$idle_string" | sed 's/[^0-9]*//g'
    fi
}

# Display current sessions
show_sessions() {
    header
    echo -e "${YELLOW}Current Active Sessions:${NC}"
    echo -e "${BLUE}USER\tTTY\tIDLE\tPID\tFROM${NC}"
    who -u | awk '{print $1"\t"$2"\t"$5"\t"$6"\t"$7}' | column -t -s $'\t'
    echo -e "\nPress any key to continue..."
    read -n 1 -s
}

# Scan for stale sessions
scan_sessions() {
    header
    echo -e "${YELLOW}Scanning for Stale Sessions (Idle > ${MAX_IDLE_MINUTES} minutes)...${NC}"
    echo ""

    STALE_SESSIONS=()
    while read -r line; do
        user=$(echo "$line" | awk '{print $1}')
        tty=$(echo "$line" | awk '{print $2}')
        idle=$(echo "$line" | awk '{print $5}')
        pid=$(echo "$line" | awk '{print $6}')
        from=$(echo "$line" | awk '{print $7}')

        if [[ ! "$tty" =~ ^pts/|^tty ]] || [[ " ${WHITELIST[@]} " =~ " ${user} " ]]; then
            continue
        fi

        idle_minutes=$(get_idle_time "$idle")

        if [[ "$idle_minutes" -ge "$MAX_IDLE_MINUTES" ]]; then
            STALE_SESSIONS+=("$user|$tty|$pid|$idle_minutes|$from")
            echo -e "${RED}[STALE] ${user} on ${tty} (idle: ${idle_minutes} minutes, PID: ${pid})${NC}"
        else
            echo -e "${GREEN}[ACTIVE] ${user} on ${tty} (idle: ${idle_minutes} minutes)${NC}"
        fi
    done < <(who -u)

    echo -e "\nFound ${#STALE_SESSIONS[@]} stale sessions"
    echo "Press any key to continue..."
    read -n 1 -s
}

# Terminate selected sessions
terminate_sessions() {
    header
    if [[ ${#STALE_SESSIONS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No stale sessions found to terminate.${NC}"
        sleep 2
        return
    fi

    echo -e "${YELLOW}Select sessions to terminate:${NC}"
    echo -e "${BLUE} # | USER\tTTY\tIDLE\tFROM${NC}"

    for i in "${!STALE_SESSIONS[@]}"; do
        IFS='|' read -ra SESSION <<< "${STALE_SESSIONS[$i]}"
        printf "${RED}%2d${NC} | ${SESSION[0]}\t${SESSION[1]}\t${SESSION[3]}m\t${SESSION[4]}\n" $((i+1))
    done

    echo -e "\nEnter session numbers to terminate (comma separated), 'a' for all, or 'q' to quit:"
    read -p "Selection: " selection

    if [[ "$selection" == "q" ]]; then
        return
    fi

    if [[ "$selection" == "a" ]]; then
        selected_indices=($(seq 0 $((${#STALE_SESSIONS[@]}-1))))
    else
        IFS=',' read -ra selected_indices <<< "$selection"
        for i in "${selected_indices[@]}"; do
            if [[ ! "$i" =~ ^[0-9]+$ ]] || [[ "$i" -lt 1 ]] || [[ "$i" -gt "${#STALE_SESSIONS[@]}" ]]; then
                echo -e "${RED}Invalid selection: $i${NC}"
                return
            fi
        done
        # Convert to 0-based array indices
        selected_indices=("${selected_indices[@]/#/$((i-1))}")
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "\n${YELLOW}DRY RUN: No sessions will actually be terminated${NC}"
    else
        echo -e "\n${RED}WARNING: This will terminate the selected sessions. Continue? [y/N]${NC}"
        read -n 1 -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    terminated=0
    for i in "${selected_indices[@]}"; do
        IFS='|' read -ra SESSION <<< "${STALE_SESSIONS[$i]}"
        user="${SESSION[0]}"
        tty="${SESSION[1]}"
        pid="${SESSION[2]}"
        idle="${SESSION[3]}"
        from="${SESSION[4]}"

        log "Attempting to terminate $user on $tty (idle: $idle minutes, PID: $pid)"

        if [[ "$DRY_RUN" == false ]]; then
            if kill -15 "$pid" 2>/dev/null; then
                sleep 1
                if ps -p "$pid" > /dev/null; then
                    if [[ "$FORCE" == true ]]; then
                        kill -9 "$pid"
                        log "Force terminated PID $pid ($user)"
                        echo -e "${RED}Force terminated ${user} on ${tty}${NC}"
                    else
                        log "Failed to terminate PID $pid ($user) with SIGTERM"
                        echo -e "${RED}Failed to terminate ${user} on ${tty} (try with --force)${NC}"
                        continue
                    fi
                else
                    log "Terminated PID $pid ($user)"
                    echo -e "${GREEN}Terminated ${user} on ${tty}${NC}"
                fi
                terminated=$((terminated + 1))

                if [[ "$NOTIFY_ADMIN" == true ]]; then
                    echo "Terminated stale session for $user on $tty (idle for $idle minutes)" | \
                    mail -s "Stale session terminated on $(hostname)" "$ADMIN_EMAIL"
                fi
            else
                log "Failed to terminate PID $pid ($user)"
                echo -e "${RED}Failed to terminate ${user} on ${tty}${NC}"
            fi
        else
            echo -e "${YELLOW}Would terminate ${user} on ${tty} (idle: $idle minutes)${NC}"
            terminated=$((terminated + 1))
        fi
    done

    echo -e "\n${GREEN}Successfully terminated $terminated sessions${NC}"
    sleep 2
}

# Configuration menu
config_menu() {
    while true; do
        header
        echo -e "${YELLOW}Configuration Menu${NC}"
        echo -e "1. Set maximum idle time (current: ${MAX_IDLE_MINUTES} minutes)"
        echo -e "2. Manage whitelist (current: ${WHITELIST[*]})"
        echo -e "3. Toggle email notifications (current: $([[ $NOTIFY_ADMIN == true ]] && echo "ON" || echo "OFF"))"
        echo -e "4. Set admin email (current: ${ADMIN_EMAIL})"
        echo -e "5. Save configuration to ${CONFIG_FILE}"
        echo -e "6. Return to main menu"
        echo -e "\nEnter your choice: "

        read -n 1 -s option
        case $option in
            1)
                read -p "Enter new maximum idle time in minutes: " MAX_IDLE_MINUTES
                ;;
            2)
                echo -e "\nCurrent whitelist: ${WHITELIST[*]}"
                echo -e "Enter users to add/remove (comma separated, prefix with - to remove): "
                read -r users_input
                IFS=',' read -ra users <<< "$users_input"
                for user in "${users[@]}"; do
                    if [[ "$user" == -* ]]; then
                        user="${user:1}"
                        WHITELIST=("${WHITELIST[@]/$user}")
                    else
                        WHITELIST+=("$user")
                    fi
                done
                WHITELIST=($(echo "${WHITELIST[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
                ;;
            3)
                NOTIFY_ADMIN=$([[ "$NOTIFY_ADMIN" == true ]] && echo false || echo true)
                ;;
            4)
                read -p "Enter admin email address: " ADMIN_EMAIL
                ;;
            5)
                echo "MAX_IDLE_MINUTES=$MAX_IDLE_MINUTES" > "$CONFIG_FILE"
                echo "WHITELIST=(${WHITELIST[*]})" >> "$CONFIG_FILE"
                echo "NOTIFY_ADMIN=$NOTIFY_ADMIN" >> "$CONFIG_FILE"
                echo "ADMIN_EMAIL=\"$ADMIN_EMAIL\"" >> "$CONFIG_FILE"
                echo -e "\n${GREEN}Configuration saved to $CONFIG_FILE${NC}"
                sleep 1
                ;;
            6)
                return
                ;;
            *)
                echo -e "\n${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main menu
main_menu() {
    while true; do
        header
        echo -e "${YELLOW}Main Menu${NC}"
        echo -e "1. Show current sessions"
        echo -e "2. Scan for stale sessions"
        echo -e "3. Terminate stale sessions"
        echo -e "4. Configuration"
        echo -e "5. Exit"
        echo -e "\nCurrent settings: Idle > ${MAX_IDLE_MINUTES} mins, Whitelist: ${WHITELIST[*]}"
        echo -e "Mode: $([[ $DRY_RUN == true ]] && echo "${YELLOW}DRY RUN${NC}" || echo "${RED}LIVE${NC}")"
        echo -e "\nEnter your choice: "

        read -n 1 -s option
        case $option in
            1)
                show_sessions
                ;;
            2)
                scan_sessions
                ;;
            3)
                terminate_sessions
                ;;
            4)
                config_menu
                ;;
            5)
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --idle)
            MAX_IDLE_MINUTES="$2"
            shift 2
            ;;
        --notify)
            NOTIFY_ADMIN=true
            shift
            ;;
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --whitelist)
            IFS=',' read -ra WHITELIST <<< "$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run    Only show what would be done"
            echo "  --force      Use SIGKILL if SIGTERM fails"
            echo "  --idle N     Set maximum idle time in minutes"
            echo "  --notify     Enable email notifications"
            echo "  --email      Set admin email address"
            echo "  --whitelist  Set whitelist (comma separated)"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
check_root
load_config
main_menu
