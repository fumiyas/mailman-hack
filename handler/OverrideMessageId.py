## Mailman: Override the 'Message-Id' header in a posting message
## Copyright (c) 2008-2009 SATOH Fumiyasu @ OSS Technology, Inc.
##               <http://www.osstech.co.jp/>
##
## License: GNU General Public License version 2
## Date: 2009-07-31, since 2008-07-17

"""Override the 'Message-Id' header.

e.g., in mm_cfg.py:

GLOBAL_PIPELINE.insert(GLOBAL_PIPELINE.index('CookHeaders'), 'OverrideMessageId')

## By default, this handler affects all lists. Use the following if you
## want to apply to the specific list.
#OVERRIDE_MESSAGEID = ['list-name-foo', list-name-bar']
"""

import re

from Mailman import mm_cfg

ORIG_NAME = 'X-Original-Message-Id'


def process(mlist, msg, msgdata):
    try:
	confs = mm_cfg.OVERRIDE_MESSAGEID
	if not mlist.internal_name() in confs:
	    return
    except AttributeError:
	pass

    msgid = msg.get('Message-Id')
    if not msgid:
	return

    match = re.match(r"^<?([^@>]+)(?:(@)([^>]+))?>?$", msgid)
    if not match:
	return
    msgid_local = match.group(1) or ''
    msgid_at = match.group(2) or ''
    msgid_domain = match.group(3) or ''
    msgid_at_domain = msgid_at + msgid_domain

    for msgid in msg.get_all('Message-Id', []):
	msg[ORIG_NAME] = msgid
    del msg['Message-Id']
    msg['Message-Id'] = '<%s-%s%s>' % (msgid_local, mlist.internal_name(), msgid_at_domain)

