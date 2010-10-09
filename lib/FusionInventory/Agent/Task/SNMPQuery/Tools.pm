package FusionInventory::Agent::Task::SNMPQuery::Tools;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT = qw(
    lastSplitObject
    getStringIpAddress
);

sub lastSplitObject {
    my $var = shift;

    my @array = split(/\./, $var);
    return $array[-1];
}

sub getStringIpAddress {
    my ($hex) = @_;

    $hex =~ s/://g;
    my @bytes = split(/\S{2}/, $hex);

    my $string =
        (hex $bytes[3]) . "." .
        (hex $bytes[5]) . "." .
        (hex $bytes[7]) . "." .
        (hex $bytes[9]);

    return $string;
}

