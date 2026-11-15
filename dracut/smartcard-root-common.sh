#!/bin/sh
# dracut hook: smartcard-root-common
# Ensures realpath is available for cryptroot cleanup (dracut equivalent)

. /lib/smartcard-common-lib.sh

_realpath="$(_find_binary_path /usr/bin/realpath /bin/realpath /usr/local/bin/realpath)"
if [ -n "$_realpath" ]; then
    # realpath should already be in dracut by default, but ensure it's available
    return 0
fi

return 0
