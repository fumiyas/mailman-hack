#!/usr/bin/python
##
## Mailman withlist: Set list's owner e-mail address(es)
## Copyright (c) SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Set list's owner e-mail address(es)

This script is intended to be run as a bin/withlist script, i.e.

% bin/withlist -l -r setowner listname [options] owner ...

Options:
    -a
    --add
      Add specified owner e-mail address(es) to the owner list

    -r
    --remove
      Remove specified owner e-mail address(es) from the owner list

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

def setowner(mlist, *args):
    try:
        opts, args = getopt.getopt(args,
	    'arv',
	    ['add', 'remove', 'verbose'])
    except getopt.error, msg:
        usage(1, msg)

    verbose = 0
    owner_arg = list(args)
    owner_old = mlist.owner
    owner_new = None
    for opt, arg in opts:
        if opt in ('-a', '--add'):
	    owner_new = owner_old + [x for x in owner_arg if x not in owner_old]
        elif opt in ('-r', '--remove'):
	    owner_new = [x for x in owner_old if x not in owner_arg]
        elif opt in ('-v', '--verbose'):
            verbose = 1

    if not owner_new:
	owner_new = owner_arg

    if verbose:
        print _('Current owner: %(owner_old)s')
        print _('Setting owner to: %(owner_new)s')
    mlist.owner = owner_new

    print _('Saving list')
    mlist.Save()
    mlist.Unlock()


if __name__ == '__main__':
    usage(0)
