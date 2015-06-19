## Mailman 2.1: Fix broken MIME-encoded subject header
## Copyright (C) 2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
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

