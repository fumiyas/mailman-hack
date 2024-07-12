## Mailman 2.1: Set the suitable(?) 'Reply-To' header field into a posting message
## Copyright (c) 2006-2024 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Set the suitable(?) 'Reply-To' header field.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders')+1:0] = [
    'AdjustReplyTo',
]

## By default, this handler affects all lists. Use the following if you
## want to apply to the specific list.
#ADJUST_REPLYTO = ['list-name-foo', 'list-name-bar']
"""

import email
import re

from collections import OrderedDict
from Mailman import mm_cfg
from Mailman import MemberAdaptor
from Mailman.Handlers.CookHeaders import change_header, uheader

COMMASPACE = ',\n '


def process(mlist, msg, msgdata):
    ## Check reply_goes_to_list value:
    ## 0 - Reply-To: not munged
    ## 1 - Reply-To: set back to the list
    ## 2 - Reply-To: set to an explicit value (reply_to_address)
    if mlist.reply_goes_to_list == 0:
        if msg.has_key('Reply-To'):
            return
    elif mlist.reply_goes_to_list == 1:
        return
    elif mlist.reply_goes_to_list == 2:
        return

    try:
        confs = mm_cfg.ADJUST_REPLYTO
        if not mlist.internal_name() in confs:
            return
    except AttributeError:
        pass

    def domatch(addrpatterns, addr):
        for addrpattern in addrpatterns:
            if not addrpattern:
                ## Ignore blank or empty lines
                continue
            try:
                if re.match(addrpattern, addr, re.IGNORECASE):
                    return True
            except re.error:
                ## The pattern is a malformed regexp -- try matching safely,
                ## with all non-alphanumerics backslashed:
                if re.match(re.escape(addrpattern), addr, re.IGNORECASE):
                    return True
        return False

    ## Set 'Reply-To' header to the list's posting address and
    ## the address(es) taken from 'From', 'To', 'Cc' and 'Reply-To' headers.
    listaddrs = [mlist.GetListEmail()]
    listaddrs += [alias.strip() for alias in mlist.acceptable_aliases.splitlines()]
    reply_to = OrderedDict()
    for hfname in ('From', 'To', 'Cc', 'Reply-To'):
        for name, addr in email.Utils.getaddresses(msg.get_all(hfname, [])):
            if not addr or addr in reply_to:
                continue
            if mlist.isMember(addr) and \
               mlist.getDeliveryStatus(addr) == MemberAdaptor.ENABLED:
                continue
            if domatch(listaddrs, addr):
                continue
            reply_to[addr] = email.Utils.formataddr((name, addr))
    if mlist.reply_to_address:
        reply_to[""] = mlist.reply_to_address
    else:
        i18ndesc = uheader(mlist, mlist.description, 'Reply-To')
        reply_to[""] = email.Utils.formataddr((str(i18ndesc), mlist.GetListEmail()))

    change_header('Reply-To', COMMASPACE.join(reply_to.values()), mlist, msg, msgdata)
