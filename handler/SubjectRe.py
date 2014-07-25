# Copyright (C) 2014 SATOH Fumiyasu @ OSS Technology Corp., Japan
# Copyright (C) 1998-2014 by the Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
# USA.

"""Fix "Subject: Re: Re: Re[2]: ..." to "Subject: Re: ...".

e.g., in mm_cfg.py:

GLOBAL_PIPELINE.insert(GLOBAL_PIPELINE.index('CookHeaders'), 'SubjectRe')

NOTE: If you use subject_prefix on all lists, this handler is not required.
"""

from __future__ import nested_scopes
import re

from email.Header import Header, decode_header, make_header
from email.Errors import HeaderParseError

from Mailman import Utils

RECOLON = 'Re:'

# True/False
try:
    True, False
except NameError:
    True = 1
    False = 0



nonascii = re.compile('[^\s!-~]')

def uheader(mlist, s, header_name=None, continuation_ws='\t', maxlinelen=None):
    # Get the charset to encode the string in. Then search if there is any
    # non-ascii character is in the string. If there is and the charset is
    # us-ascii then we use iso-8859-1 instead. If the string is ascii only
    # we use 'us-ascii' if another charset is specified.
    charset = Utils.GetCharSet(mlist.preferred_language)
    if nonascii.search(s):
        # use list charset but ...
        if charset == 'us-ascii':
            charset = 'iso-8859-1'
    else:
        # there is no nonascii so ...
        charset = 'us-ascii'
    return Header(s, charset, maxlinelen, header_name, continuation_ws)

def change_header(name, value, mlist, msg, msgdata, delete=True, repl=True):
    if ((msgdata.get('from_is_list') == 2 or
        (msgdata.get('from_is_list') == 0 and mlist.from_is_list == 2)) and 
        not msgdata.get('_fasttrack')
       ) or name.lower() in ('from', 'reply-to'):
        msgdata.setdefault('add_header', {})[name] = value
    elif repl or not msg.has_key(name):
        if delete:
            del msg[name]
        msg[name] = value



def process(mlist, msg, msgdata):
    # VirginRunner sets _fasttrack for internally crafted messages.
    fasttrack = msgdata.get('_fasttrack')
    if not msgdata.get('isdigest') and not fasttrack:
        try:
            fix_subject_re(mlist, msg, msgdata)
        except (UnicodeError, ValueError):
            # Sometimes subject header is not MIME encoded for 8bit
            # simply abort fixing.
            pass



def fix_subject_re(mlist, msg, msgdata):
    subject = msg.get('subject', '')
    # Try to figure out what the continuation_ws is for the header
    if isinstance(subject, Header):
        lines = str(subject).splitlines()
    else:
        lines = subject.splitlines()
    ws = '\t'
    if len(lines) > 1 and lines[1] and lines[1][0] in ' \t':
        ws = lines[1][0]
    # The subject may be multilingual but we take the first charset as major
    # one and try to decode.  If it is decodable, returned subject is in one
    # line and cset is properly set.  If fail, subject is mime-encoded and
    # cset is set as us-ascii.  See detail for ch_oneline() (CookHeaders one
    # line function).
    subject, cset = ch_oneline(subject)
    # TK: Python interpreter has evolved to be strict on ascii charset code
    # range.  It is safe to use unicode string when manupilating header
    # contents with re module.  It would be best to return unicode in
    # ch_oneline() but here is temporary solution.
    subject = unicode(subject, cset)
    rematch = re.match('((RE|AW|SV|VS)\s*(\[\d+\])?\s*:\s*)+', subject, re.I)
    if not rematch:
        return

    subject = subject[rematch.end():]
    # If charset is 'us-ascii', try to concatnate as string because there
    # is some weirdness in Header module (TK)
    if cset == 'us-ascii':
        try:
            h = u' '.join([RECOLON, subject])
            h = h.encode('us-ascii')
            h = uheader(mlist, h, 'Subject', continuation_ws=ws)
            change_header('Subject', h, mlist, msg, msgdata)
            return
        except UnicodeError:
            pass
    # Get the header as a Header instance, with proper unicode conversion
    h = uheader(mlist, RECOLON, 'Subject', continuation_ws=ws)
    # TK: Subject is concatenated and unicode string.
    subject = subject.encode(cset, 'replace')
    h.append(subject, cset)
    change_header('Subject', h, mlist, msg, msgdata)



def ch_oneline(headerstr):
    # Decode header string in one line and convert into single charset
    # copied and modified from ToDigest.py and Utils.py
    # return (string, cset) tuple as check for failure
    try:
        d = decode_header(headerstr)
        # at this point, we should rstrip() every string because some
        # MUA deliberately add trailing spaces when composing return
        # message.
        d = [(s.rstrip(), c) for (s,c) in d]
        cset = 'us-ascii'
        for x in d:
            # search for no-None charset
            if x[1]:
                cset = x[1]
                break
        h = make_header(d)
        ustr = h.__unicode__()
        oneline = u''.join(ustr.splitlines())
        return oneline.encode(cset, 'replace'), cset
    except (LookupError, UnicodeError, ValueError, HeaderParseError):
        # possibly charset problem. return with undecoded string in one line.
        return ''.join(headerstr.splitlines()), 'us-ascii'
