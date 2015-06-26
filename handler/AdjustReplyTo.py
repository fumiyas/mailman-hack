## Mailman: Set the suitable(?) 'Reply-To' header field into a posting message
## Copyright (c) 2006-2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <http://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2
## Date: 2013-04-10, since 2006-12-21

"""Set the suitable(?) 'Reply-To' header field.

e.g., in mm_cfg.py:

GLOBAL_PIPELINE.insert(GLOBAL_PIPELINE.index('CookHeaders')+1, 'AdjustReplyTo')

## By default, this handler affects all lists. Use the following if you
## want to apply to the specific list.
#ADJUST_REPLYTO = ['list-name-foo', 'list-name-bar']
"""

import email
import re

from Mailman import mm_cfg
from Mailman import MemberAdaptor

ORIG_NAME = 'X-Original-Reply-To'


def process(mlist, msg, msgdata):
    try:
	confs = mm_cfg.ADJUST_REPLYTO
	if not mlist.internal_name() in confs:
	    return
    except AttributeError:
	pass

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

    ## Rename 'Reply-To' header to 'X-Original-Reply-To' if it exists.
    for addr in msg.get_all('Reply-To', []):
	msg[ORIG_NAME] = addr
    del msg['Reply-To']

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
    listaddr_set = False
    addrs_set = set()
    for hfname in ('From', 'To', 'Cc', ORIG_NAME):
	for name, addr in email.Utils.getaddresses(msg.get_all(hfname, [])):
	    if addr in addrs_set:
		continue
	    if addr == '':
	    	continue
	    if mlist.isMember(addr) and \
	       mlist.getDeliveryStatus(addr) == MemberAdaptor.ENABLED:
	    	continue
	    if domatch(listaddrs, addr):
		if listaddr_set:
		    ## List address has already been set
		    continue
		listaddr_set = True
	    msg['Reply-To'] = addr
	    addrs_set.add(addr)
    if not listaddr_set:
	## List address has NOT been set
	msg['Reply-To'] = mlist.reply_to_address or mlist.GetListEmail()

