#!/bin/bash
export PATH="$HOME/.foundry/bin:$PATH"
cd /home/david/blockdev/lelangfi
exec forge "$@"
