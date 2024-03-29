#!/usr/bin/python2
## -*- coding: utf-8 -*- vim:shiftwidth=4:expandtab:
##
## Mailman 2.1: Get and Set list configurations in JSON format
## Copyright (c) 2018-2024 SATOH Fumiyasu @ OSSTech Corp., Japan
##
## License: GNU General Public License version 2 or later
##

"""Get and Set list configurations via JSON data

Usage: mmconfigjson [OPTIONS] LISTNAME [NAME ...]

Options:
    --set
    -s
        Read configurations in JSON format from standard input
        and set to the list

Arguments:
    LISTNAME
        Listname
    NAME
        Configuration name(s) to print its value(s)

Examples:
    $ mmconfigjson managers
    ...
    $ mmconfigjson <(list_lists --bare)
    ...
    $ mmconfigjson admins host_name web_page_url invalid_name
    {
      "name": "admins",
      "host_name": "example.jp",
      "web_page_url": "https://lists.example.jp/mailman/"
    }
    $ echo '{ "available_languages": ["en","ja"] }' |mmconfigjson --set staff
"""

from __future__ import print_function

import sys
import getopt
import re
import types
import json

import paths
from Mailman import mm_cfg
from Mailman import Errors

from Mailman.MailList import MailList
from Mailman import i18n

C_ = i18n.C_

i18n.set_language(mm_cfg.DEFAULT_SERVER_LANGUAGE)

attr_name_re = re.compile(r'^[a-z][0-9a-z_]*$')


def usage():
    print(C_(__doc__))
    sys.exit(0)


def pdie(code, msg=''):
    if msg:
        print(msg, file=sys.stderr)
    sys.exit(code)


def isprimitive(v):
    return isinstance(v, (types.NoneType, bool, str, unicode, int, float, list, dict))


def json_load_byteified(file_handle):
    return _byteify(
        json.load(file_handle, object_hook=_byteify),
        ignore_dicts=True
    )


def json_loads_byteified(json_text):
    return _byteify(
        json.loads(json_text, object_hook=_byteify),
        ignore_dicts=True
    )


def _byteify(data, ignore_dicts=False):
    # if this is a unicode string, return its string representation
    if isinstance(data, unicode):
        return data.encode('utf-8')
    # if this is a list of values, return list of byteified values
    if isinstance(data, list):
        return [_byteify(item, ignore_dicts=True) for item in data]
    # if this is a dictionary, return dictionary of byteified keys and values
    # but only if we haven't already byteified it
    if isinstance(data, dict) and not ignore_dicts:
        return {
            _byteify(key, ignore_dicts=True): _byteify(value, ignore_dicts=True)
            for key, value in data.iteritems()
        }
    # if it's anything else, return it in its original form
    return data


def configjson(listname, read_attr_names, write_attrs):
    write_p = write_attrs is not None

    mlist = None
    try:
        try:
            mlist = MailList(listname, lock=write_p)
        except Errors.MMListError as e:
            pdie(2, C_('No such list "%(listname)s"\n%(e)s'))

        if not read_attr_names and not write_p:
            read_attr_names = filter(lambda n: attr_name_re.match(n), dir(mlist))
            read_attr_names.remove('password')  # has admin's SHA-1 password hash
            read_attr_names.remove('mod_password')  # ditto
            read_attr_names.remove('post_password')  # ditto
            read_attr_names.remove('passwords')  # has member's plain text password

        if read_attr_names:
            attrs = {"name": listname}
            for attr_name in read_attr_names:
                if attr_name in ['bounce_info', 'delivery_status']:
                    ## Not JSON serializable
                    continue
                try:
                    value = getattr(mlist, attr_name)
                except AttributeError:
                    continue
                if isprimitive(value):
                    attrs[attr_name] = value
            print(json.dumps(attrs, ensure_ascii=False, sort_keys=True, indent=2))

        if write_p:
            for attr_name, value in write_attrs.items():
                setattr(mlist, attr_name, value)
            mlist.Save()

    finally:
        if mlist and mlist.Locked():
            mlist.Unlock()


def main():
    try:
        opts, args = getopt.getopt(
            sys.argv[1:], 'hs',
            ['help', 'set'])
    except getopt.error as e:
        pdie(1, e)

    write_p = False
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt in ('-s', '--set'):
            write_p = True

    if len(args) < 1:
        pdie(1, C_('listname is required'))

    listname = args[0].lower().strip()
    read_attr_names = args[1:]

    write_attrs = None
    if write_p:
        write_attrs = json_load_byteified(sys.stdin)
        if not isinstance(write_attrs, dict):
            pdie(1, "Invalid input")

    if "/" in listname:
        with open(listname) as f:
            for line in f:
                configjson(line.strip(), read_attr_names, write_attrs)
    else:
        configjson(listname, read_attr_names, write_attrs)


if __name__ == '__main__':
    main()
