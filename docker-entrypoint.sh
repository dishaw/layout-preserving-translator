#!/bin/sh
# Start BusyBox crond in background (logs level 2 = warnings+errors only)
crond -l 2

# Hand off to nginx in foreground so Docker tracks the main process
exec nginx -g 'daemon off;'
