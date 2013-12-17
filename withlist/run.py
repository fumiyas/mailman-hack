#!/usr/bin/python
##
## Mailman withlist: Run command with locking list
## Copyright (c) 2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Usage: withlist -l -r run COMMAND [ARGUMENT ...]
"""

import sys
import os

def run(mlist, *args):
    if not mlist.Locked():
	print >>sys.stderr, 'List is not locked'
	sys.exit(1)

    pid = os.fork()
    if pid == 0:
	os.execvp(args[0], args)

    ## FIXME: Setenv:
    ## bindir
    ## privatedir
    ## m.real_name
    ## m.owner
    ## m.moderator
    ## m.post_id
    ## m.archive
    ## m.web_page_url

    pid_exited, status = os.waitpid(pid, 0)
    sys.exit(status >> 8)

