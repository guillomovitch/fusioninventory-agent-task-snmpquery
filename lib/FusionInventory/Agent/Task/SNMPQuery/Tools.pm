package FusionInventory::Agent::Task::SNMPQuery::Tools;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT = qw(
    lastSplitObject
);

sub lastSplitObject {
    my $var = shift;

    my @array = split(/\./, $var);
    return $array[-1];
}
