## Mailman 2.1: Fix broken MIME-encoded display-name in From:/To:/Cc: header
## Copyright (C) 2022 SATOH Fumiyasu @ OSSTech Corp., Japan
##               <https://GitHub.com/fumiyas/mailman-hack>
##               <https://www.OSSTech.co.jp/>
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

"""Fix broken MIME-encoded display-name in From:/To:/Cc: header. E.g.:

    From: "=?UTF-8?B?5pel5pysIOWkqumDjg==?=" <taro@example.com>

is fixed to:

    From: =?UTF-8?B?5pel5pysIOWkqumDjg==?= <taro@example.com>

In mm_cfg.py:

GLOBAL_PIPELINE[GLOBAL_PIPELINE.index('CookHeaders'):0] = [
    'QuotedMimeFixer',
]
"""

import re

from Mailman.Handlers.CookHeaders import change_header

QUOTED_MIME_RE = re.compile(r'"(=\?[\w\-]+\?(?:[Bb]\?[A-Za-z\d+\/]+={0,3}|[Qq]\?(?:[!-<>@-~]|=[A-Fa-f\d]{2})*?)\?=)"')


def process(mlist, msg, msgdata):
    ## VirginRunner sets _fasttrack for internally crafted messages.
    if msgdata.get('isdigest') or msgdata.get('_fasttrack'):
        return

    for name in ('From', 'To', 'Cc'):
        value = msg.get(name)
        if not value:
            continue

        value = QUOTED_MIME_RE.sub('\\1', str(value))
        change_header(name, value, mlist, msg, msgdata)
