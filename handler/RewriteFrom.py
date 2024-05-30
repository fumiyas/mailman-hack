## Mailman 2.1: Rewrite the From: header field
## Copyright (c) 2009-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2
##
## See also: http://mm.tkikuchi.net/pipermail/mmjp-users/2008-February/002325.html

"""Rewrite the From: header field.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'RewriteFrom',
]

REWRITE_FROM = {
    ## For specific list
    'list-name-foo': {
        'from_name':	'%(from_name)s',
        'from_address':	'%(list_address)s',
    },
    ## For all lists
    '*': {
        'from_name':	'%(from_name)s {%(from_address)s}',
        'from_address':	'%(list_address)s',
        'save_original':'X-Original-From',
    },
}
"""

import re
from email.Utils import parseaddr
from email.Utils import formataddr

from Mailman import mm_cfg
from Mailman import Utils
from Mailman import Errors
from Mailman.SafeDict import SafeDict
from Mailman.Handlers.CookHeaders import change_header


def process(mlist, msg, msgdata):
    try:
        confs_by_list = mm_cfg.REWRITE_FROM
    except AttributeError:
        return

    if mlist.internal_name() in confs_by_list:
        conf = confs_by_list[mlist.internal_name()]
    elif '*' in confs_by_list:
        conf = confs_by_list['*']
    else:
        return

    from_name_fmt = conf.get('from_name', '%(from_name)s')
    from_address_fmt = conf.get('from_address', '%(from_address)s')
    save_original = conf.get('save_original')

    d = SafeDict({
        'list_real_name':	mlist.real_name,
        'list_name':		mlist.internal_name(),
        'list_address':	mlist.GetListEmail(),
        'list_domain':	mlist.host_name,
        'list_desc':		mlist.description,
        'list_info':		mlist.info,
    })

    lcset = Utils.GetCharSet(mlist.preferred_language)

    from_name, from_address = parseaddr(msg.get('From'))
    d['from_address'] = from_address
    try:
        d['from_local'], d['from_domain'] = re.split('@', from_address, 1)
    except ValueError:
        d['from_local'] = from_address
        d['from_domain'] = ''

    if from_name != '':
        d['from_name'] = Utils.oneline(from_name, lcset)
    else:
        d['from_name'] = d['from_local']

    try:
        membername = mlist.getMemberName(from_address) or None
        try:
            d['from_membername'] = membername.encode(lcset)
        except (AttributeError, UnicodeError):
            d['from_membername'] = d['from_name']
    except Errors.NotAMemberError:
        d['from_membername'] = d['from_name']

    from_name = from_name_fmt % d
    from_address = from_address_fmt % d

    if save_original:
        change_header(save_original, msg['From'], mlist, msg, msgdata, delete=False)

    change_header('From', formataddr((from_name, from_address)), mlist, msg, msgdata)
