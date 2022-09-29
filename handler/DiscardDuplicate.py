## Mailman 2.1: Discard duplicate messages
## Copyright (c) 2018-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Discard duplicate messages.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'DiscardDuplicate',
]

## By default, this handler affects all lists. Use the following if you
## want to apply to the specific list.
#DISCARD_DUPLICATE = ['list-name-foo', list-name-bar']
"""

import time

from Mailman import mm_cfg
from Mailman import Errors


class DuplicateDetected(Errors.DiscardMessage):
    """This message is a duplicate of past messages."""


def process(mlist, msg, msgdata):
    try:
        confs = mm_cfg.DISCARD_DUPLICATE
        if not mlist.internal_name() in confs:
            return
    except AttributeError:
        pass

    msgid = msg.get('Message-Id')
    if not msgid:
        return
    date = msg.get('Date')
    if not date:
        return

    try:
        xrecords = mlist.discard_duplicate_records
    except AttributeError:
        xrecords = mlist.discard_duplicate_records = {}

    xtime = time.time()
    for k, v in xrecords.items():
        if xtime - v > 60:
            del xrecords[k]

    xid = msgid + '\t' + date
    if xid in xrecords:
        raise DuplicateDetected

    xrecords[xid] = xtime
