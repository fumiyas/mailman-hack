#!/usr/bin/env python3
## -*- coding: utf-8 -*- vim:shiftwidth=4:expandtab:

import logging
import argparse
import sys
import os
import re


logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.WARN,
    format=(f'{sys.argv[0]}: %(levelname)s: %(message)s'),
)

re_line_continued = re.compile('^[ \t]')
re_alias = re.compile(r'^(?P<alias>[A-Za-z0-9_][-+_.=A-Za-z0-9]*):\s(?P<entry>.*)$')
re_entry_sp = re.compile(r'\s,\s')
re_list_entry = re.compile(r'^:include:(?P<list_dir>/.*/(?P<list_basedir>[^/]+))/include$')
re_include_entry = re.compile(r'^:include:(?P<list_dir>/.*/(?P<list_basedir>[^/]+))/(?P<include_basename>[^/]+)$')

args_parser = argparse.ArgumentParser(
    prog=sys.argv[0],
    add_help=True,
)
args_parser.add_argument(
    '--fml-dir', metavar='DIR',
    help='FML install directory',
)
args_parser.add_argument(
    '--default-admin', metavar='EMAIL_ADDRESS',
    help='Default admin (owner) e-mail address for lists without admin',
)
args_parser.add_argument(
    '--default-email-domain', metavar='DOMAIN_NAME',
    help='Append @DOMAIN_NAME to addresses without @ and domain part'
)
args_parser.add_argument(
    '--exclude-list-names-from', metavar='FILE',
    help='Read exclude list names from FILE',
    type=argparse.FileType('r'),
)
args_parser.add_argument(
    'lists_dir', metavar='DIR',
    help='FML mailing-list directory',
)
args = args_parser.parse_args()

lists_dir = args.lists_dir
email_domain_default = args.default_email_domain
fml_dir = args.fml_dir
aliases_file = lists_dir + '/etc/aliases'

exclude_list_names = set([
    name.rstrip('\n') for name in args.exclude_list_names_from.readlines()
])
args.exclude_list_names_from.close()


def htpasswd2addresses(list_name, fml_dir, email_domain_default):
    htpasswd_file = f'{fml_dir}/www/authdb/ml-admin/{list_name}/htpasswd'
    addrs = set()
    try:
        with open(htpasswd_file) as f:
            for line in f:
                line = line.strip()
                if line == '' or line.startswith('#') or line.find(':') < 1:
                    continue
                addr = line[:line.find(':')]
                if '@' not in addr:
                    addr += '@' + email_domain_default
                addrs.add(addr)
    except Exception as e:
        logger.warning("Failed to open file: %s: %s", htpasswd_file, e)

    return addrs


def entry2addresses(entry, lists_dir, email_domain_default, list_orig_dir):
    include_entry_m = re_include_entry.match(entry)
    if not include_entry_m:
        if '@' not in entry:
            entry += '@' + email_domain_default
        return set([entry])

    if include_entry_m['list_dir'] != list_orig_dir:
        logger.warning("Include file for alias not in fml list directory: Expected %s, actual", list_orig_dir, include_entry_m['list_dir'])
        return set()

    include_file = '/'.join([lists_dir, include_entry_m['list_basedir'], include_entry_m['include_basename']])
    addrs = set()
    try:
        with open(include_file) as f:
            for line in f:
                line = line.strip()
                if line == '' or line.startswith('#'):
                    continue
                addrs.update(entry2addresses(line, lists_dir, email_domain_default, list_orig_dir))
    except Exception as e:
        logger.warning("Failed to open file: %s: %s", include_file, e)

    return addrs


## コメント行と空行の削除、継続行のまとめ処理
lines = []
with open(aliases_file) as f:
    for line in f:
        line = line.rstrip()
        if line == '' or line.startswith('#'):
            continue

        if re_line_continued.search(line):
            line[-1] += line
            continue
        lines.append(line)

## エイリアス名ごとにエントリ内容の抽出
entries_by_alias = {}
for line in lines:
    alias_m = re_alias.search(line)
    if not alias_m:
        logger.warning('Invalid alias line: %s', line)
        continue
    if alias_m['alias'] in entries_by_alias:
        logger.warning('Duplicated alias: %s', alias_m['alias'])
        continue

    entries_by_alias[alias_m['alias']] = re_entry_sp.split(alias_m['entry'])

## エイリアス名からリスト名と管理者アドレスを抽出
admins_by_name = {}
for alias in sorted(entries_by_alias.keys()):
    entries = entries_by_alias.get(alias)
    if entries is None or len(entries) != 1:
        continue

    list_entry_m = re_list_entry.search(entries[0])
    if not list_entry_m:
        ## メーリングリストのエイリアスエントリではないので無視
        continue

    list_name = alias
    list_dir = f'{lists_dir}/{list_name}'
    list_aliases = [
        list_name,
        f'{list_name}-ctl',
        f'{list_name}-request',
        f'owner-{list_name}',
        f'owner-{list_name}-ctl'
    ]

    if list_name != list_entry_m['list_basedir']:
        logger.warning('List name does not match with list directory name: %s: %s', list_name, list_entry_m['list_basedir'])
        continue
    if not os.path.isdir(list_dir):
        logger.warning('List directory not found: %s', list_dir)
        continue
    list_config_file = f'{list_dir}/config.ph'
    if not os.path.isfile(list_config_file):
        logger.warning('List configuration file not found: %s', list_config_file)
        continue

    list_admin_alias = list_name + '-admin'
    try:
        list_admin_entry = entries_by_alias.pop(list_admin_alias)
    except KeyError:
        logger.warning('Alias entry not found for list admin: %s: %s', list_name, list_admin_alias)
        continue

    for list_alias in list_aliases:
        try:
            entries_by_alias.pop(list_alias)
        except KeyError:
            logger.warning('Alias entry not found for list: %s: %s', list_name, list_alias)

    if list_name in exclude_list_names:
        logger.info('List name exluded: %s', list_name)
        continue

    list_orig_dir = list_entry_m['list_dir']
    list_admins = set()
    for entry in list_admin_entry:
        list_admins.update(entry2addresses(entry, lists_dir, email_domain_default, list_orig_dir))

    if fml_dir:
        ## FIXME: Use f'{list_dir}/etc/passwd' file instead if no fml_dir specified
        list_admins_ht = htpasswd2addresses(list_name, fml_dir, email_domain_default)
        #if list_admins_ht != list_admins:
        #    logger.warning('List admins differ: %s: alias   : %s', list_name, list_admins)
        #    logger.warning('List admins differ: %s: htpasswd: %s', list_name, list_admins_ht)
        list_admins.update(list_admins_ht)

    admins_by_name[list_name] = list_admins

for alias in sorted(entries_by_alias.keys()):
    logger.warning('Unrecognized alias entry: %s', alias)

for list_name, admins in sorted(admins_by_name.items()):
    if not admins:
        logger.warning('List has no admin address: %s', list_name)
    print(f'{list_name}\t{lists_dir}/{list_name}\t{" ".join(admins)}')
