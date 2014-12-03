#!/usr/bin/perl

## FIXME: Mail archive in $dir/$name/archive/* by sequencer -N

## TODO:
##	approve_pass = password (for moderator?)
##	moderate = yes
##	moderator = moderator@example.jp
##	restrict_post = filename
##	subject_prefix = [mlname]
##	taboo_headers

use strict;
use warnings;

my $domain = $ARGV[0];
my $alias_file = $ARGV[1];
my $dir = $ARGV[2];

my $alias_value_by_name = {};
my $domains_by_name = {};
my $owners_by_name = {};
my $aliases = {};

sub alias_map {
  my @keys = split(/\s*,\s*/, $_[0]);
  my @values = ();

  for my $key (@keys) {
    if (defined(my $value = $aliases->{$key})) {
      push(@values, alias_map($value));
    } else {
      push(@values, $key);
    }
  }

  return @values;
}

sub md_conf
{
  my $md_conf_file = "$dir/$_[0].config";
  my $md_conf = {};

  open(my $md_conf_fh, '<', $md_conf_file)
    || die "ERROR: Cannot open: $md_conf_file: $!\n";
  while (<$md_conf_fh>) {
    chomp;
    if (/^(\w+)\s*=\s*(.?)\s*$/) {
      $md_conf->{$1} = $2;
    }
  }
  close($md_conf_fh);

  return $md_conf;
}

sub md_seq
{
  my $md_seq_file = "$dir/$_[0].seq";

  return '' unless (-f $md_seq_file);

  open(my $md_seq_fh, '<', $md_seq_file)
    || die "ERROR: Cannot open: $md_seq_file: $!\n";

    my $seq = <$md_seq_fh>;
    chomp($seq);
    close($md_seq_fh);

    return $seq;
}

## ======================================================================

open(my $alias_fh, '<', $alias_file)
  || die "ERROR: Cannot open: $alias_file: $!\n";

while (<$alias_fh>) {
  chomp;
  if (/^(\w[\w\-]*):\s*(".*\/wrapper\s+(?:sequencer|resend).*)$/) {
    my $name = $1;
    my $value = $2;

    $alias_value_by_name->{$name} = $value;

    ## FIXME: -h DOMAIN ??
    if ($value =~ /\s-r\s+\Q$name\E@([^\s"]*)/) {
      $domains_by_name->{$name} = $1;
    }
    else {
      $domains_by_name->{$name} = $domain;
    }

  } elsif (/^owner-(\w[\w\-]*):\s*(?::\s+)*(\S*)/) { ## (?::\s)* to strip garbage
    $owners_by_name->{$1} = $2;
  } elsif (/^(\w[\w\-]*):\s*(\S*)/) {
    $aliases->{$1} = $2;
  }
}

for my $name (keys %$alias_value_by_name) {
  #next if ($name =~ /^(test|testml)$/);

  my $domain = $domains_by_name->{$name};

  my $owners = $owners_by_name->{$name};
  if (!defined($owners)) {
    warn "ERROR: No owner address found: $name\n";
    next;
  }

  my $conf = md_conf($name);
  my $seq = md_seq($name);

  print join("\t",
    $name,
    $domain,
    join(',', alias_map($owners)),
    $conf->{admin_pass},
    $conf->{subject_prefix},
    $seq,
  ), "\n";
}

