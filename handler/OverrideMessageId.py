## Mailman 2.1: Override the 'Message-Id' header in a posting message
## Copyright (c) 2008-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Override the 'Message-Id' header.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'OverrideMessageId',
]

## By default, this handler affects all lists. Use the following if you
## want to apply to the specific list.
#OVERRIDE_MESSAGEID = ['list-name-foo', 'list-name-bar']
"""

import re

from Mailman import mm_cfg

RE_BRACKET = re.compile(r'^(<)?')
ORIG_NAME = 'X-Original-Message-Id'


def process(mlist, msg, msgdata):
    try:
        confs = mm_cfg.OVERRIDE_MESSAGEID
        if not mlist.internal_name() in confs:
            return
    except AttributeError:
        pass

    msgid_orig = msg.get('Message-Id')
    if not msgid_orig:
        return

    msgid_prefix = mlist.internal_name().replace('@', '=') + '%'
    msgid_new = RE_BRACKET.sub(r'\1' + msgid_prefix, msgid_orig, 1)

    for msgid in msg.get_all('Message-Id', []):
        msg[ORIG_NAME] = msgid
    del msg['Message-Id']
    msg['Message-Id'] = msgid_new
