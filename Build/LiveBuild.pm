#
# Author: Jan Blunck <jblunck@infradead.org>
#
# This file is part of build.
#
# build is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# build is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with build.  If not, see <http://www.gnu.org/licenses/>.
#

package Build::LiveBuild;

use strict;

eval { require Archive::Tar; };
*Archive::Tar::new = sub {die("Archive::Tar is not available\n")} unless defined &Archive::Tar::new;

sub filter {
  my ($content) = @_;

  return '' unless defined $content;

  $content =~ s/^#.*$//mg;
  $content =~ s/^!.*$//mg;
  $content =~ s/^\s*//mg;
  return $content;
}

sub parse_package_list {
  my ($content) = @_;
  my @packages = split /\n/, filter($content);

  return @packages;
};

sub parse_archive {
  my ($content) = @_;
  my @repos;

  my @lines = split /\n/, filter($content);
  for (@lines) {
    next if /^deb-src /;

    die("bad path using not obs:/ URL: $_\n") unless $_ =~ /^deb\s+obs:\/\/\/?([^\s\/]+)\/([^\s\/]+)\/?\s+.*$/;
    push @repos, "$1/$2";
  }

  return @repos;
}

sub unify {
  my %h = map {$_ => 1} @_;
  return grep(delete($h{$_}), @_);
}

sub parse {
  my ($config, $filename, @args) = @_;

  # TODO: check that filename exists

  # check that filename is a tar
  my $tar = Archive::Tar->new;
  $tar->read($filename) || die "Read failed: $filename\n";

  # check that directory layout matches live-build directory structure

  # defaults live-build package dependencies base on 4.0~a26 gathered with:
  # $ grep Check_package -r /usr/lib/live/build
  my @lb4_requirements = (
    'apt-utils', 'dctrl-tools', 'debconf', 'dosfstools', 'e2fsprogs', 'grub',
    'librsvg2-bin', 'live-boot', 'live-config', 'mtd-tools', 'parted',
    'squashfs-tools', 'syslinux', 'syslinux-common', 'wget', 'xorriso',
    'zsync' );

  # dependency injection based on live-build version
  my @packages = @{$config->{'substitute'}->{'build-packages:livebuild'} || []};
  push @packages, @lb4_requirements unless @packages;

  # always require the list of packages required by live-boot for
  # bootstrapping the target distribution image (e.g. with debootstrap)
  push @packages, ( 'live-build-desc' );

  for my $file ($tar->list_files('')) {
    next unless $file =~ /^config\/package-lists\/.*\.list.*/;
    push @packages, parse_package_list($tar->get_content($file));
  }

  my @repos;
  for my $file ($tar->list_files('')) {
    next unless $file =~ /^config\/archives\/.*\.list.*/;
    push @repos, parse_archive($tar->get_content($file));
  }

  my $ret = {};
  ($ret->{'name'} = $filename) =~ s/\.[^.]+$//;
  $ret->{'deps'} = [ unify(@packages) ];
  $ret->{'path'} = [ unify(@repos) ];
  for (@{$ret->{'path'}}) {
    my @s = split('/', $_, 2);
    $_ = { 'project' => $s[0], 'repository' => $s[1] };
  }

  return $ret;
}

1;