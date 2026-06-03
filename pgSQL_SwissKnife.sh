#!/bin/bash

# PostgreSQL SwissKnife - Main Menu

# Determine the installation directory
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${INSTALL_DIR}/modules"

# Handle Update Command
if [[ "$1" == "update" ]]; then
    echo "[INFO]: Updating PostgreSQL SwissKnife..."
    cd "$INSTALL_DIR" || exit 1
    
    if git pull; then
        echo "[SUCCESS]: Update completed successfully."
        exit 0
    else
        echo "[ERR]: Update failed. Please check your internet connection or git configuration."
        exit 1
    fi
fi

# Ensure modules are executable
if ls "${MODULES_DIR}"/*.sh 1> /dev/null 2>&1; then
    chmod +x "${MODULES_DIR}"/*.sh
fi

while true; do
    echo ""
    echo "========================================="
    echo "   PostgreSQL SwissKnife - Main Menu"
    echo "========================================="
    echo "1. Setup & Profile Management"
    echo "2. Backup Strategy"
    echo "3. Maintenance Tasks"
    echo "4. Performance Monitor"
    echo "5. Security Audit"
    echo "6. Systemd Integration"
    echo "7. Exit"
    echo "========================================="
    read -p "Select an option [1-7]: " CHOICE

    case "$CHOICE" in
        1)
            "${MODULES_DIR}/Setup.sh"
            ;;
        2)
            "${MODULES_DIR}/Backup.sh"
            ;;
        3)
            "${MODULES_DIR}/Maintenance.sh"
            ;;
        4)
            "${MODULES_DIR}/Performance.sh"
            ;;
        5)
            "${MODULES_DIR}/Security.sh"
            ;;
        6)
            "${MODULES_DIR}/Systemd.sh"
            ;;
        7)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Press Enter to try again."
            read
            ;;
    esac

    echo "Press Enter to return to menu..."
    read
done
