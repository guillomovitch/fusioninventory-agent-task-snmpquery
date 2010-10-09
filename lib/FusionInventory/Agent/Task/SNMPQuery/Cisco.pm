package FusionInventory::Agent::Task::SNMPQuery::Cisco;

use strict;
use warnings;

sub TrunkPorts {
    my ($data, $device, $index) = @_;

   while ( (my $port_id, my $trunk) = each (%{$data->{vlanTrunkPortDynamicStatus}}) ) {
      if ($trunk eq "1") {
         $device->{PORTS}->{PORT}->[$index->{lastSplitObject($port_id)}]->{TRUNK} = $trunk;
      } else {
         $device->{PORTS}->{PORT}->[$index->{lastSplitObject($port_id)}]->{TRUNK} = '0';
      }
      delete $data->{vlanTrunkPortDynamicStatus}->{$port_id};
   }
   if (keys (%{$data->{vlanTrunkPortDynamicStatus}}) eq "0") {
      delete $data->{vlanTrunkPortDynamicStatus};
   }
}

sub CDPPorts {
   my $data = shift,
   my $device = shift;
   my $oid_walks = shift;
   my $index = shift;

   my $short_number;

   if (ref($data->{cdpCacheAddress}) eq "HASH"){
      while ( my ( $number, $ip_hex) = each (%{$data->{cdpCacheAddress}}) ) {
         $ip_hex =~ s/://g;
         $short_number = $number;
         $short_number =~ s/$oid_walks->{cdpCacheAddress}->{OID}//;
         my @array = split(/\./, $short_number);
         my @ip_num = split(/(\S{2})/, $ip_hex);
         my $ip = (hex $ip_num[3]).".".(hex $ip_num[5]).".".(hex $ip_num[7]).".".(hex $ip_num[9]);
         if ($ip ne "0.0.0.0") {
            $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{IP} = $ip;
            $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CDP} = "1";
            if (defined($data->{cdpCacheDevicePort}->{$oid_walks->{cdpCacheDevicePort}->{OID}.$short_number})) {
               $device->{PORTS}->{PORT}->[$index->{$array[1]}]->{CONNECTIONS}->{CONNECTION}->{IFDESCR} = $data->{cdpCacheDevicePort}->{$oid_walks->{cdpCacheDevicePort}->{OID}.$short_number};
            }
         }
         delete $data->{cdpCacheAddress}->{$number};
         if (ref($data->{cdpCacheDevicePort}) eq "HASH"){
            delete $data->{cdpCacheDevicePort}->{$number};
         }
      }
      if (keys (%{$data->{cdpCacheAddress}}) eq "0") {
         delete $data->{cdpCacheAddress};
      }
      if (ref($data->{cdpCacheDevicePort}) eq "HASH"){
         if (keys (%{$data->{cdpCacheDevicePort}}) eq "0") {
            delete $data->{cdpCacheDevicePort};
         }
      }
   }
}



sub GetMAC {
   my $data = shift,
   my $device = shift;
   my $vlan_id = shift;
   my $index = shift;
   my $oid_walks = shift;

   my $ifIndex;
   my $numberip;
   my $mac;
   my $short_number;
   my $dot1dTpFdbPort;

   my $i = 0;
   # each VLAN WALK per port
   while ( my ($number,$ifphysaddress) = each (%{$data->{VLAN}->{$vlan_id}->{dot1dTpFdbAddress}}) ) {
      $short_number = $number;
      $short_number =~ s/$oid_walks->{dot1dTpFdbAddress}->{OID}//;
      $dot1dTpFdbPort = $oid_walks->{dot1dTpFdbPort}->{OID};
      if (exists $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}) {
         if (exists $data->{VLAN}->{$vlan_id}->{dot1dBasePortIfIndex}->{
                              $oid_walks->{dot1dBasePortIfIndex}->{OID}.".".
                              $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
                           }) {

            $ifIndex = $data->{VLAN}->{$vlan_id}->{dot1dBasePortIfIndex}->{
                              $oid_walks->{dot1dBasePortIfIndex}->{OID}.".".
                              $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number}
                           };
            if (not exists $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{CONNECTIONS}->{CDP}) {
               my $add = 1;
               if ($ifphysaddress eq "") {
                  $add = 0;
               }
               if ($ifphysaddress eq $device->{PORTS}->{PORT}->[$index->{$ifIndex}]->{MAC}) {
                  $add = 0;
               }
               if ($add eq "1") {
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
#      delete $data->{VLAN}->{$vlan_id}->{dot1dTpFdbAddress}->{$number};
#      delete $data->{VLAN}->{$vlan_id}->{dot1dTpFdbPort}->{$dot1dTpFdbPort.$short_number};
   }
}



sub lastSplitObject {
   my $var = shift;

   my @array = split(/\./, $var);
   return $array[-1];
}

1;
