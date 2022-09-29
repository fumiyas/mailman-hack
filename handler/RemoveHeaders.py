## Mailman 2.1: Remove header fields in a posting message
## Copyright (c) 2006-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Remove header fields in a posting message.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'RemoveHeaders',
]

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
