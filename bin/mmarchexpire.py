#! /usr/bin/python
## -*- coding: utf-8 -*- vim:shiftwidth=4:expandtab:
##
## Mailman 2.1: Expire list archives
## Copyright (c) 2018 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Expire list archives

Usage: mmarchexpire [OPTIONS] LISTNAME VOLUMES

Options:
    --verbose
    -v
        Vervose mode
    --dry-run
    -n
        Perform a trial run with no changes made

Arguments:
    LISTNAME
        Listname
    VOLUMES
        Number of volumes to remain
"""

from __future__ import print_function

import os
import errno
import sys
import getopt
import re
import calendar
import shutil
import cPickle as pickle

import paths
from Mailman import mm_cfg
from Mailman import Errors

from time import sleep
from Mailman.MailList import MailList
from Mailman.Archiver.HyperArch import HyperArchive
from Mailman import i18n

C_ = i18n.C_

i18n.set_language(mm_cfg.DEFAULT_SERVER_LANGUAGE)

month_by_name = {
  'January': 1,
  'February': 2,
  'March': 3,
  'April': 4,
  'May': 5,
  'June': 6,
  'July': 7,
  'August': 8,
  'September': 9,
  'October': 10,
  'November': 11,
  'December': 12,
}
date_is_daily = re.compile(r'^\d{8}$')
date_is_monthly = re.compile(r'^(?P<year>\d{4})-(?P<month_name>' + '|'.join(month_by_name) + r')$')


def usage():
    print(C_(__doc__))
    sys.exit(0)


def pdie(code, msg=''):
    if msg:
        print(msg, file=sys.stderr)
    sys.exit(code)


def main():
    try:
        opts, args = getopt.getopt(
            sys.argv[1:], 'hvn',
            ['help', 'verbose', 'dry-run'])
    except getopt.error, msg:
        pdie(1, msg)

    dry_run_p = False
    verbose_p = False
    values = None
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt in ('-v', '--verbose'):
            verbose_p = True
        elif opt in ('-n', '--dry-run'):
            dry_run_p = True
            verbose_p = True

    if len(args) < 1:
        pdie(1, C_('listname is required'))

    listname = args[0].lower().strip()
    num = int(args[1])
    if num < 1:
        pdie(1, 'Number (>0) required')

    mlist = None
    try:
        try:
            mlist = MailList(listname, lock=True)
        except Errors.MMListError, e:
            pdie(2, C_('No such list "%(listname)s"\n%(e)s'))

        index = os.path.join(mlist.archive_dir(), 'pipermail.pck')
        with open(index, 'r') as f:
            d = pickle.load(f)

        if not (len(d['archives']) > num):
            if verbose_p:
                print("No expirations", file=sys.stderr)
            return

        a_dir = os.path.join(mlist.archive_dir(), 'attachments')
        while len(d['archives']) > num:
            date = d['archives'].pop()
            date_dir = os.path.join(mlist.archive_dir(), date)
            date_db = os.path.join(mlist.archive_dir(), 'database', date + '-')

            paths = [date_dir, date_dir + '.txt', date_dir + '.txt.gz']
            paths.extend([date_db + x for x in ('article', 'author', 'date', 'subject', 'thread')])
            if date_is_daily.match(date):
                paths.append(os.path.join(a_dir, date))
            elif date_is_monthly.match(date):
                m = date_is_monthly.match(date)
                year = int(m.group('year'))
                month = month_by_name[m.group('month_name')]
                mdays = calendar.monthrange(year, month)[1]
                for mday in range(1, mdays+1):
                    paths.append(os.path.join(a_dir, '%d%02d%02d' % (year, month, mday)))
            else:
                print('Unsupported date format: %s' % date, file=sys.stderr)

            for path in paths:
                if verbose_p:
                    print(path)
                if dry_run_p:
                    continue
                try:
                    if os.path.isdir(path):
                        shutil.rmtree(path)
                    else:
                        os.unlink(path)
                except OSError as e:
                    if e.errno <> errno.ENOENT: raise

        if not dry_run_p:
            index_new = index + '.new'
            with os.fdopen(os.open(index_new, os.O_WRONLY | os.O_CREAT, 0o660), 'w') as f:
                pickle.dump(d, f)
            os.rename(index_new, index)
            ## Update index.html
            archiver = HyperArchive(mlist)
            archiver.VERBOSE = verbose_p
            archiver.close()
    finally:
        if mlist:
            mlist.Unlock()


if __name__ == '__main__':
    main()
