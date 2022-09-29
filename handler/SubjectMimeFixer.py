## Mailman 2.1: Fix broken MIME-encoded subject header
## Copyright (C) 2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
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

"""Fix broken MIME-encoded subject header. E.g.,

    Subject: =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?==?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=

is fixed to:

    Subject: =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=
     =?ISO-2022-JP?B?GyRCJUYlOSVIGyhC?=

I.e., this handler adds missing "linear-white-space".
See "5. Use of encoded-words in message headers" in RFC 2047,
"MIME (Multipurpose Internet Mail Extensions) Part Three:
Message Header Extensions for Non-ASCII Text".

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'SubjectMimeFixer',
]
"""
import re

from Mailman.Handlers.CookHeaders import change_header

MIME_RE = re.compile(r'(=\?[\w\-]+\?(?:[Bb]\?[A-Za-z\d+\/]+={0,3}|[Qq]\?(?:[!-<>@-~]|=[A-Fa-f\d]{2})*?)\?=)(?=\S)')


def process(mlist, msg, msgdata):
    ## VirginRunner sets _fasttrack for internally crafted messages.
    if msgdata.get('isdigest') or msgdata.get('_fasttrack'):
        return

    subject = msg.get('subject')
    if not subject:
        return

    subject = MIME_RE.sub('\\1\n ', str(subject))
    change_header('Subject', subject, mlist, msg, msgdata)
