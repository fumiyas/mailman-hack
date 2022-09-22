## Mailman 2.1: Rename header fields in a posting message
## Copyright (c) 2006-2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <http://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Rename header fields in a posting message.

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'RenameHeaders',
]

RENAME_HEADERS = {
    'list-name-foo': ['Received'],
    '*': ['Received', 'Disposition-Notification-To'],
}
"""

from Mailman import mm_cfg

RENAME_HEADERS_PREFIX = 'X-Original-'
RENAME_HEADERS_SUFFIX = ''


def process(mlist, msg, msgdata):
    try:
        confs_by_list = mm_cfg.RENAME_HEADERS
    except AttributeError:
        return

    if mlist.internal_name() in confs_by_list:
        conf = confs_by_list[mlist.internal_name()]
    elif '*' in confs_by_list:
        conf = confs_by_list['*']
    else:
        return

    try:
        prefix = mm_cfg.RENAME_HEADERS_PREFIX
    except AttributeError:
        prefix = RENAME_HEADERS_PREFIX

    try:
        suffix = mm_cfg.RENAME_HEADERS_SUFFIX
    except AttributeError:
        suffix = RENAME_HEADERS_SUFFIX

    if prefix == '' and suffix == '':
        return

    for name in conf:
        for body in msg.get_all(name, []):
            msg[prefix + name + suffix] = body
        del msg[name]
