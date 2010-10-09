package FusionInventory::Agent::Task::SNMPQuery::Cisco;

use strict;
use warnings;

sub GetMAC {
    my ($data, $device, $vlan_id, $index, $walk) = @_;

    # each VLAN WALK per port
    while (my ($number, $ifphysaddress) = each %{$data->{VLAN}->{$vlan_id}->{dot1dTpFdbAddress}}) {
        next unless $ifphysaddress;

        my $short_number = $number;
        $short_number =~ s/$walk->{dot1dTpFdbAddress}->{OID}//;
        my $dot1dTpFdbPort = $walk->{dot1dTpFdbPort}->{OID};

        my $key = $dot1dTpFdbPort . $short_number;
        next unless exists $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$key};

        my $subkey = 
            $walk->{dot1dBasePortIfIndex}->{OID} . 
            "." .
            $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$key};

        next unless
            exists $data->{VLAN}->{$vlan_id}->{dot1dBasePortIfIndex}->{$subkey};

        my $ifIndex =
            $data->{VLAN}->{$vlan_id}->{dot1dBasePortIfIndex}->{$subkey};

        my $port = $device->{PORTS}->{PORT}->[$index->{$ifIndex}];

        next if exists $port->{CONNECTIONS}->{CDP};
        next if $ifphysaddress eq $port->{MAC};

        my $connection = $port->{CONNECTIONS}->{CONNECTION};
        my $i = $connection ? @{$connection} : 0;
        $connection->[$i]->{MAC} = $ifphysaddress;
    }
}

sub TrunkPorts {
    my ($data, $device, $index) = @_;

    while (my ($port_id, $trunk) = each %{$data->{vlanTrunkPortDynamicStatus}}) {
        my $port =
            $device->{PORTS}->{PORT}->[$index->{lastSplitObject($port_id)}];
        $port->{TRUNK} = $trunk == 1 ? 1 : 0;
        delete $data->{vlanTrunkPortDynamicStatus}->{$port_id};
    }

    if (keys (%{$data->{vlanTrunkPortDynamicStatus}}) == 0) {
        delete $data->{vlanTrunkPortDynamicStatus};
    }
}

sub CDPPorts {
    my ($data, $device, $walk, $index) = @_;

    next unless ref $data->{cdpCacheAddress} eq "HASH";

    while (my ($number, $ip_hex) = each %{$data->{cdpCacheAddress}}) {
        $ip_hex =~ s/://g;
        my $short_number = $number;
        $short_number =~ s/$walk->{cdpCacheAddress}->{OID}//;
        my @array = split(/\./, $short_number);
        my @ip_num = split(/(\S{2})/, $ip_hex);
        my $ip =
            (hex $ip_num[3]) . "." .
            (hex $ip_num[5]) . "." .
            (hex $ip_num[7]) . "." .
            (hex $ip_num[9]);
        if ($ip ne "0.0.0.0") {
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

sub lastSplitObject {
    my $var = shift;

    my @array = split(/\./, $var);
    return $array[-1];
}

1;
