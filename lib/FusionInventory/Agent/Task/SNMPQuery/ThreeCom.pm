package FusionInventory::Agent::Task::SNMPQuery::ThreeCom;

use strict;
use warnings;

sub GetMAC {
    my ($data, $device, $index, $walk) = @_;

    while (my ($number, $ifphysaddress) = each %{$data->{dot1dTpFdbAddress}}) {
        next unless $ifphysaddress;

        my $short_number = $number;
        $short_number =~ s/$walk->{dot1dTpFdbAddress}->{OID}//;
        my $dot1dTpFdbPort = $walk->{dot1dTpFdbPort}->{OID};

        next unless exists $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number};
        my $ifIndex = $data->{dot1dBasePortIfIndex}->{
            $walk->{dot1dBasePortIfIndex}->{OID}.".".
            $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
        };

        my $connection =
            $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION};
        my $i = $connection ? @{$connection} : 0;
        $connection->[$i]->{MAC} = $ifphysaddress;
    }
}


# In Intellijack 225, put mac address of port 'IntelliJack Ethernet Adapter' in port 'LAN Port'
sub RewritePortOf225 {
    my ($device, $index) = @_;

    $device->{PORTS}->{PORT}->[$index->{101}]->{MAC} = $device->{PORTS}->{PORT}->[$index->{1}]->{MAC};
    delete $device->{PORTS}->{PORT}->[$index->{1}];
    delete $device->{PORTS}->{PORT}->[$index->{101}]->{CONNECTIONS};
}


1;
