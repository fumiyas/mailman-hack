## Mailman 2.1: Fix "Subject: Re: Re: Re[2]: ..." to "Subject: Re: ..."
## Copyright (C) 2014-2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <http://www.OSSTech.co.jp/>
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
## USA.

"""Fix "Subject: Re: Re: Re[2]: ..." to "Subject: Re: ...".

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
  'SubjectReReRe',
]

NOTE: If you use subject_prefix on all lists, this handler is not required.
"""

from Mailman import mm_cfg
from Mailman.Handlers.CookHeaders import prefix_subject
from Mailman.Handlers.CookHeaders import change_header

DUMMY_PREFIX = "DUMMY "


def process(mlist, msg, msgdata):
    ## VirginRunner sets _fasttrack for internally crafted messages.
    if msgdata.get('isdigest') or msgdata.get('_fasttrack'):
        return

    ## Same process is done by CookHeaders.py if subject_prefix is enabled
    if mlist.subject_prefix.strip():
        return

    old_style_save = mm_cfg.OLD_STYLE_PREFIXING
    mm_cfg.OLD_STYLE_PREFIXING = 0
    mlist.subject_prefix = DUMMY_PREFIX

    try:
        prefix_subject(mlist, msg, msgdata)
        subject = msg.get('subject')
        if subject:
            subject = str(subject)[len(DUMMY_PREFIX):]
            change_header('Subject', subject, mlist, msg, msgdata)
    except (UnicodeError, ValueError):
        ## Sometimes subject header is not MIME encoded for 8bit
        ## simply abort fixing.
        pass

    mm_cfg.OLD_STYLE_PREFIXING = old_style_save
    mlist.subject_prefix = ''
