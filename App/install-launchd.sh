#!/bin/bash
# Install/Uninstall G9 Helper launch agent for auto-restart

PLIST_NAME="com.hidpi.g9helper.plist"
PLIST_SRC="launch-agent/${PLIST_NAME}"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_NAME}"

case "$1" in
    install)
        echo "Installing G9 Helper launch agent..."

        # Check if app is installed
        if [ ! -d "/Applications/G9 Helper.app" ]; then
            echo "Error: G9 Helper.app not found in /Applications"
            echo "Please run: cp -r 'build/G9 Helper.app' /Applications/"
            exit 1
        fi

        # Create LaunchAgents directory if needed
        mkdir -p "$HOME/Library/LaunchAgents"

        # Copy plist
        cp "$PLIST_SRC" "$PLIST_DEST"

        # Load the agent
        launchctl unload "$PLIST_DEST" 2>/dev/null
        launchctl load "$PLIST_DEST"

        echo "Launch agent installed and loaded."
        echo "G9 Helper will now:"
        echo "  - Start automatically at login"
        echo "  - Auto-restart if it crashes"
        echo ""
        echo "To check status: launchctl list | grep g9helper"
        ;;

    uninstall)
        echo "Uninstalling G9 Helper launch agent..."

        # Unload the agent
        launchctl unload "$PLIST_DEST" 2>/dev/null

        # Remove plist
        rm -f "$PLIST_DEST"

        echo "Launch agent removed."
        ;;

    status)
        if launchctl list | grep -q "com.hidpi.g9helper"; then
            echo "G9 Helper launch agent is loaded"
            launchctl list | grep "com.hidpi.g9helper"
        else
            echo "G9 Helper launch agent is not loaded"
        fi
        ;;

    *)
        echo "Usage: $0 {install|uninstall|status}"
        echo ""
        echo "  install   - Install and enable auto-restart on crash"
        echo "  uninstall - Remove auto-restart"
        echo "  status    - Check if launch agent is loaded"
        exit 1
        ;;
esac
