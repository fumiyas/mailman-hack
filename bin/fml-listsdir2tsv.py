#!/usr/bin/env python3
## -*- coding: utf-8 -*- vim:shiftwidth=4:expandtab:

import logging
import sys
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

email_default_domain = sys.argv[1]
lists_dir = sys.argv[2]
aliases_file = lists_dir + '/etc/aliases'


def entry2addresses(entry, lists_dir, email_default_domain, list_orig_dir):
    include_entry_m = re_include_entry.match(entry)
    if not include_entry_m:
        if '@' not in entry:
            entry += '@' + email_default_domain
        return [entry]

    if include_entry_m['list_dir'] != list_orig_dir:
        logger.warning("Include file for alias not in fml list directory: %s", e)
        return []

    include_file = '/'.join([lists_dir, include_entry_m['list_basedir'], include_entry_m['include_basename']])
    addrs = []
    try:
        with open(include_file) as f:
            for line in f:
                line = line.strip()
                if line == '' or line.startswith('#'):
                    continue
                addrs.extend(entry2addresses(line, lists_dir, email_default_domain, list_orig_dir))
    except Exception as e:
        logger.warning("Failed to open include file for alias: %s", e)

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
for alias in list(entries_by_alias.keys()):
    entries = entries_by_alias.get(alias)
    if entries is None or len(entries) != 1:
        continue

    list_entry_m = re_list_entry.search(entries[0])
    if not list_entry_m:
        ## メーリングリストのエイリアスエントリではないので無視
        continue
    if alias != list_entry_m['list_basedir']:
        logger.warning('List name does not match with list directory name: %s: %s', alias, list_entry_m['list_basedir'])
        continue

    alias_admin = alias + '-admin'
    if alias_admin not in entries_by_alias:
        logger.warning('Alias entry not found: %s', alias_admin)
        continue

    del(entries_by_alias[alias])
    for alias_x in [alias+'-ctl', alias+'-request', 'owner-'+alias, 'owner-'+alias+'-ctl']:
        try:
            del(entries_by_alias[alias_x])
        except KeyError:
            logger.warning('Alias entry not found: %s', alias_x)

    list_orig_dir = list_entry_m['list_dir']
    alias_admins = []
    for entry in entries_by_alias.pop(alias_admin):
        alias_admins.extend(entry2addresses(entry, lists_dir, email_default_domain, list_orig_dir))

    admins_by_name[alias] = alias_admins

for alias in entries_by_alias.keys():
    logger.warning('Unrecognized alias entry: %s', alias)

for list_name, admins in admins_by_name.items():
    if not admins:
        logger.warning('List has no admin address: %s', list_name)
    print(f'{list_name}\t{lists_dir}/{list_name}\t{" ".join(admins)}')
