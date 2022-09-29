#!/usr/bin/python
##
## Mailman withlist: Run command with locking list
## Copyright (c) 2013-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Usage: withlist -l -r run LISTNAME COMMAND [ARGUMENT ...]
"""

import sys
import os


def run(mlist, *args):
    if not mlist.Locked():
        print >>sys.stderr, 'List is not locked'
        sys.exit(1)

    pid = os.fork()
    if pid == 0:
        env = os.environ.copy()
        env['MM_LIST_REAL_NAME'] = mlist.real_name
        env['MM_LIST_NAME'] = mlist.internal_name()
        env['MM_LIST_ADDRESS'] = mlist.GetListEmail()
        env['MM_LIST_DOMAIN'] = mlist.host_name
        env['MM_LIST_POST_ID'] = str(mlist.post_id)
        env['MM_LIST_WEB_PAGE_URL'] = mlist.web_page_url
        os.execvpe(args[0], args, env)

    pid_exited, status = os.waitpid(pid, 0)
    sys.exit(status >> 8)
