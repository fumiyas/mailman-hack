## Mailman: Remove header fields in a posting message
## Copyright (c) 2006-2009 SATOH Fumiyasu @ OSS Technology, Inc.
##               <http://www.osstech.co.jp/>
##
## License: GNU General Public License version 2
## Date: 2009-06-04, since 2006-06-23

"""Remove header fields in a posting message.

e.g, in mm_cfg.py:

GLOBAL_PIPELINE.insert(GLOBAL_PIPELINE.index('CookHeaders'), 'RemoveHeaders')
REMOVE_HEADERS = {
  'list-name-foo': ['Received'],
  'list-name-bar': ['Organization', 'User-Agent', 'X-Mailer'],
}
"""

from Mailman import mm_cfg


def process(mlist, msg, msgdata):
    try:
	confs_by_list = mm_cfg.REMOVE_HEADERS
    except AttributeError:
	return

    if mlist.internal_name() in confs_by_list:
	conf = confs_by_list[mlist.internal_name()]
    elif '*' in confs_by_list:
	conf = confs_by_list['*']
    else:
	return

    for hfname in conf:
	del msg[hfname]

