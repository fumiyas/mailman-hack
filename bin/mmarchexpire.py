#! /usr/bin/python
## -*- coding: utf-8 -*- vim:shiftwidth=4:expandtab:
##
## Mailman 2.1: Get and Set list configurations in JSON format
## Copyright (c) 2018 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 2 or later
##

## FIXME
"""No document. Sorry..."""

from __future__ import print_function

import os
import errno
import sys
import getopt
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


def usage():
    print(C_(__doc__))
    sys.exit(0)


def pdie(code, msg=''):
    if msg:
        print(msg, file=sys.stderr)
    sys.exit(code)


def isprimitive(v):
    return isinstance(v, (types.NoneType, bool, str, unicode, int, float, list, dict))


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
        pdie(1, 'FIXME')

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
            return

        while len(d['archives']) > num:
            date = d['archives'].pop()
            date_dir = os.path.join(mlist.archive_dir(), date)
            date_db = os.path.join(mlist.archive_dir(), 'database', date + '-')

            paths = [date_dir, date_dir + '.txt', date_dir + '.txt.gz']
            paths.extend([date_db + x for x in ('article', 'author', 'date', 'subject', 'thread')])
            if mlist.archive_volume_frequency == 4: ## Daily
                paths.append(os.path.join(mlist.archive_dir(), 'attachments', date))
            else:
                pdie(3, 'FIXME: mlist.archive_volume_frequency must be 4 (Daily)')

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

        index_new = index + '.new'
        with os.fdopen(os.open(index_new, os.O_WRONLY | os.O_CREAT, 0o660), 'w') as f:
            pickle.dump(d, f)
        os.rename(index_new, index)

        if not dry_run_p:
            ## Update index.html
            archiver = HyperArchive(mlist)
            archiver.VERBOSE = verbose_p
            archiver.close()
    finally:
        if mlist:
            mlist.Unlock()


if __name__ == '__main__':
    main()
