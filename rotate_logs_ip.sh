#!/bin/bash
LOG_FILE="/var/log/update_noip.log"
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 1048576 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
fi