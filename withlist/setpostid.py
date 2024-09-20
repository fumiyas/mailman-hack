#!/usr/bin/python
##
## Mailman withlist: Set list's post_id attribute
## Copyright (c) SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Set list's post_id attribute

This script is intended to be run as a bin/withlist script, i.e.

% bin/withlist -l -r setpostid listname [options] post_id

Options:
    -i
    --increment

    -d
    --decrement

    -v
    --verbose
      Print what the script is doing
"""

import getopt

from Mailman import mm_cfg
from Mailman.i18n import _


def usage(code, msg=''):
    print _(__doc__.replace('%', '%%'))
    if msg:
        print msg
    sys.exit(code)

def setpostid(mlist, *args):
    try:
        opts, args = getopt.getopt(args,
	    'idv',
	    ['increment', 'decrement', 'verbose'])
    except getopt.error, msg:
        usage(1, msg)

    verbose = 0
    post_id = args[0]
    post_id_old = mlist.post_id
    for opt, arg in opts:
        if opt in ('-i', '--increment'):
            post_id = int(mlist.post_id) + int(post_id)
        elif opt in ('-d', '--decrement'):
            post_id = int(mlist.post_id) - int(post_id)
        elif opt in ('-v', '--verbose'):
            verbose = 1

    if verbose:
        print _('Current post_id: %(post_id_old)s')
    if verbose:
        print _('Setting post_id to: %(post_id)s')
    mlist.post_id = post_id

    print _('Saving list')
    mlist.Save()
    mlist.Unlock()


if __name__ == '__main__':
    usage(0)
