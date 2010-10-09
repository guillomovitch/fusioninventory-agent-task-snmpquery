package FusionInventory::Agent::Task::SNMPQuery::Procurve;

use strict;
use warnings;

sub GetMAC {
    my ($data, $device, $index, $walk) = @_;

    while (my ($number, $ifphysaddress) = each %{$data->{dot1dTpFdbAddress}}) {
        next unless $ifphysaddress;

        my $short_number = $number;
        $short_number =~ s/$walk->{dot1dTpFdbAddress}->{OID}//;
        my $dot1dTpFdbPort = $walk->{dot1dTpFdbPort}->{OID};

        my $key = $dot1dTpFdbPort . $short_number;
        next unless exists $data->{dot1dTpFdbPort}->{$key};

        my $subkey =
            $walk->{dot1dBasePortIfIndex}->{OID} .
            "." .
            $data->{dot1dTpFdbPort}->{$key};

        next unless exists $data->{dot1dBasePortIfIndex}->{$subkey};

        my $ifIndex = $data->{dot1dBasePortIfIndex}->{$subkey};

        my $port = $device->{PORTS}->{PORT}->[$index->{$ifIndex}];

        next if exists $port->{CONNECTIONS}->{CDP};
        next if $ifphysaddress eq $port->{MAC};

        my $connection = $port->{CONNECTIONS}->{CONNECTION};
        my $i = $connection ? @{$connection} : 0;
        $connection->[$i]->{MAC} = $ifphysaddress;
    }
}


sub CDPLLDPPorts {
    my ($data, $device, $walk, $index) = @_;

    my $short_number;
    my @port_number;

    if (ref $data->{cdpCacheAddress} eq "HASH") {
        while (my ($number, $ip_hex) = each %{$data->{cdpCacheAddress}}) {
            $short_number = $number;
            $short_number =~ s/$walk->{cdpCacheAddress}->{OID}//;
            my @array = split(/\./, $short_number);
            my $ip = getStringIpAddress($ip_hex);
            if ($ip ne "0.0.0.0") {
                $port_number[$array[1]] = 1;
                my $port = $device->{PORTS}->{PORT}->[$index->{$array[1]}];
                $port->{CONNECTIONS}->{CONNECTION}->{IP} = $ip;
                $port->{CONNECTIONS}->{CDP} = 1;
                my $key = $walk->{cdpCacheDevicePort}->{OID} . $short_number;
                if (defined $data->{cdpCacheDevicePort}->{$key}) {
                    $port->{CONNECTIONS}->{CONNECTION}->{IFDESCR} =
                        $data->{cdpCacheDevicePort}->{$key};
                }
            }
            delete $data->{cdpCacheAddress}->{$number};
            if (ref($data->{cdpCacheDevicePort}) eq "HASH"){
                delete $data->{cdpCacheDevicePort}->{$number};
            }
        }
        if (keys (%{$data->{cdpCacheAddress}}) == 0) {
            delete $data->{cdpCacheAddress};
        }
        if (ref($data->{cdpCacheDevicePort}) eq "HASH"){
            if (keys (%{$data->{cdpCacheDevicePort}}) == 0) {
                delete $data->{cdpCacheDevicePort};
            }
        }
    }

    if (ref $data->{lldpCacheAddress} eq "HASH") {
        while (my ($number, $chassisname) = each %{$data->{lldpCacheAddress}}) {
            $short_number = $number;
            $short_number =~ s/$walk->{lldpCacheAddress}->{OID}//;
            my @array = split(/\./, $short_number);
            if (!defined($port_number[$array[1]])) {
                $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{SYSNAME} = $chassisname;
                $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CDP} = "1";
                if (defined($data->{lldpCacheDevicePort}->{$walk->{lldpCacheDevicePort}->{OID}.$short_number})) {
                    $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{IFDESCR} = $data->{lldpCacheDevicePort}->{$walk->{lldpCacheDevicePort}->{OID}.$short_number};
                }

                delete $data->{lldpCacheAddress}->{$number};
                if (ref($data->{lldpCacheDevicePort}) eq "HASH"){
                    delete $data->{lldpCacheDevicePort}->{$number};
                }
            }
        }
        if (keys (%{$data->{lldpCacheAddress}}) == 0) {
            delete $data->{lldpCacheAddress};
        }
        if (ref($data->{lldpCacheDevicePort}) eq "HASH"){
            if (keys (%{$data->{lldpCacheDevicePort}}) == 0) {
                delete $data->{lldpCacheDevicePort};
            }
        }
    }
}


1;
