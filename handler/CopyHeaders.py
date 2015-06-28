## Mailman 2.1: Copy values in header fields to another header fields
## Copyright (c) 2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <http://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 2

"""Copy values in header fields to another header fields

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
  'CopyHeaders',
]

COPY_HEADERS = {
  ## For specific list
  'list-name': {
    'Subject': 'X-Original-Subject',
  },
  ## For all lists
  '*': {
    'Subject': 'X-Original-Subject',
    'Reply-To': 'X-Original-Reply-To',
  },
}
"""

from Mailman import mm_cfg


def process(mlist, msg, msgdata):
    try:
	confs_by_list = mm_cfg.COPY_HEADERS
    except AttributeError:
	return

    if mlist.internal_name() in confs_by_list:
	conf = confs_by_list[mlist.internal_name()]
    elif '*' in confs_by_list:
	conf = confs_by_list['*']
    else:
	return

    for name_src, name_dst in conf.items():
        for value in msg.get_all(name_src, []):
            msg[name_dst] = value

