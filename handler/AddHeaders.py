## Mailman 2.1: Add header fields to a posting message
## Copyright (c) 2009-2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <http://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Add header fields to a posting message.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'AddHeaders',
]

ADD_HEADERS = {
    ## For specific list
    'list-name': {
        'Reply-To': '%(from_header)s, %(list_address)s',
        ## fml compatibility
        'X-ML-Name': '%(list_name)s',
        'X-ML-Count': '%(post_id)d',
    },
    ## For all lists
    '*': {
        ## fml compatibility
        'X-ML-Name': '%(list_name)s',
        'X-ML-Count': '%(post_id)d',
    },
}
"""

import re

from email.Utils import parseaddr

from Mailman import mm_cfg
from Mailman import Utils
from Mailman import Errors
from Mailman.SafeDict import SafeDict
from Mailman.Handlers.CookHeaders import change_header


def process(mlist, msg, msgdata):
    try:
        confs_by_list = mm_cfg.ADD_HEADERS
    except AttributeError:
        return

    if mlist.internal_name() in confs_by_list:
        conf = confs_by_list[mlist.internal_name()]
    elif '*' in confs_by_list:
        conf = confs_by_list['*']
    else:
        return

    d = SafeDict({'list_real_name':   mlist.real_name,
        'list_name':        mlist.internal_name(),
        'list_address':     mlist.GetListEmail(),
        'list_domain':      mlist.host_name,
        'list_desc':        mlist.description,
        'list_info':        mlist.info,
        'post_id':          mlist.post_id,
    })

    lcset = Utils.GetCharSet(mlist.preferred_language)
    d['from_header'] = msg.get('From')
    from_name, from_address = parseaddr(d['from_header'])
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

    for name, value_fmt in conf.items():
        value = value_fmt % d
        change_header(name, value, mlist, msg, msgdata, delete=False)

