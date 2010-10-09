package FusionInventory::Agent::Task::SNMPQuery::ThreeCom;

use strict;
use warnings;

sub GetMAC {
    my ($data, $device, $index, $walk) = @_;

    my $ifIndex;
    my $numberip;
    my $mac;
    my $short_number;
    my $dot1dTpFdbPort;
    my $add = 0;
    my $i;

    while (my ($number,$ifphysaddress) = each %{$data->{dot1dTpFdbAddress}}) {
        $short_number = $number;
        $short_number =~ s/$walk->{dot1dTpFdbAddress}->{OID}//;
        $dot1dTpFdbPort = $walk->{dot1dTpFdbPort}->{OID};

        $add = 1;
        if ($ifphysaddress eq "") {
            $add = 0;
        }
        if (($add == 1) && (exists($data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}))) {
            $ifIndex = $data->{dot1dBasePortIfIndex}->{
            $walk->{dot1dBasePortIfIndex}->{OID}.".".
            $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
            };

            if (exists $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}) {
                $i = @{$device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}};
            } else {
                $i = 0;
            }
            $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}->[$i]->{MAC} = $ifphysaddress;
            $i++;
        }
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
