package FusionInventory::Agent::Task::SNMPQuery::Procurve;

use strict;
use warnings;

sub GetMAC {
    my ($data, $device, $index, $walk) = @_;

    my $ifIndex;
    my $numberip;
    my $mac;
    my $short_number;
    my $dot1dTpFdbPort;

    my $i = 0;

    while (my ($number, $ifphysaddress) = each %{$data->{dot1dTpFdbAddress}}) {
        $short_number = $number;
        $short_number =~ s/$walk->{dot1dTpFdbAddress}->{OID}//;
        $dot1dTpFdbPort = $walk->{dot1dTpFdbPort}->{OID};
        if (exists $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}) {
            if (exists $data->{dot1dBasePortIfIndex}->{
                $walk->{dot1dBasePortIfIndex}->{OID}.".".
                $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
                }) {

                $ifIndex = $data->{dot1dBasePortIfIndex}->{
                $walk->{dot1dBasePortIfIndex}->{OID}.".".
                $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
                };
                if (not exists $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CDP}) {
                    my $add = 1;
                    if ($ifphysaddress eq "") {
                        $add = 0;
                    }
                    if ($ifphysaddress eq $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{MAC}) {
                        $add = 0;
                    }
                    if ($add == 1) {
                        if (exists $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}) {
                            $i = @{$device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}};
                            #$i++;
                        } else {
                            $i = 0;
                        }
                        $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CONNECTION}->[$i]->{MAC} = $ifphysaddress;
                        $i++;
                    }
                }
            }
        }
        delete $data->{dot1dTpFdbAddress}->{$number};
        delete $data->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number};
    }
}


sub CDPLLDPPorts {
    my ($data, $device, $walk, $index) = @_;

    my $short_number;
    my @port_number;

    if (ref($data->{cdpCacheAddress}) eq "HASH"){
        while (my ($number, $ip_hex) = each %{$data->{cdpCacheAddress}}) {
            $ip_hex =~ s/://g;
            $short_number = $number;
            $short_number =~ s/$walk->{cdpCacheAddress}->{OID}//;
            my @array = split(/\./, $short_number);
            my @ip_num = split(/(\S{2})/, $ip_hex);
            my $ip = (hex $ip_num[3]).".".(hex $ip_num[5]).".".(hex $ip_num[7]).".".(hex $ip_num[9]);
            if (($ip ne "0.0.0.0") && ($ip =~ /^([O1]?\d\d?|2[0-4]\d|25[0-5])\.([O1]?\d\d?|2[0-4]\d|25[0-5])\.([O1]?\d\d?|2[0-4]\d|25[0-5])\.([O1]?\d\d?|2[0-4]\d|25[0-5])$/)){
                $port_number[$array[1]] = 1;
                $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{IP} = $ip;
                $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CDP} = "1";
                if (defined($data->{cdpCacheDevicePort}->{$walk->{cdpCacheDevicePort}->{OID}.$short_number})) {
                    $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{IFDESCR} = $data->{cdpCacheDevicePort}->{$walk->{cdpCacheDevicePort}->{OID}.$short_number};
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
    if (ref($data->{lldpCacheAddress}) eq "HASH"){
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
