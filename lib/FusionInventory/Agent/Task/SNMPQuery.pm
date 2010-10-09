package FusionInventory::Agent::Task::SNMPQuery;

use strict;
use warnings;
use base 'FusionInventory::Agent::Task';

use threads;
use threads::shared;
if ($threads::VERSION > 1.32){
    threads->set_stack_size(20*8192);
}

use Data::Dumper;
use Encode qw(encode);
use ExtUtils::Installed;
use English qw(-no_match_vars);
use File::stat;
use UNIVERSAL::require;
use XML::Simple;

use FusionInventory::Logger;
use FusionInventory::Agent::Transmitter;
use FusionInventory::Agent::Storage;
use FusionInventory::Agent::XML::Query::SimpleMessage;

use FusionInventory::Agent::Task::SNMPQuery::Cisco;
use FusionInventory::Agent::Task::SNMPQuery::Procurve;
use FusionInventory::Agent::Task::SNMPQuery::ThreeCom;

our $VERSION = '1.2';
my $maxIdx : shared = 0;

my @infos = (
    [ qw/cpu INFO CPU/ ],
    [ qw/location INFO LOCATION/ ],
    [ qw/firmware INFO FIRMWARE/ ],
    [ qw/firmware1 INFO FIRMWARE/ ],
    [ qw/contant INFO CONTACT/ ],
    [ qw/comments INFO COMMENTS/ ],
    [ qw/uptime INFO UPTIME/ ],
    [ qw/serial INFO SERIAL/ ],
    [ qw/name INFO NAME/ ],
    [ qw/model INFO MODEL/ ],
    [ qw/entPhysicalModelName INFO MODEL/ ],
    [ qw/enterprise INFO MANUFACTURER/ ],
    [ qw/otherserial INFO OTHERSERIAL/ ],
    [ qw/memory INFO MEMORY/ ],
    [ qw/ram INFO RAM/ ],
);

my @printer_simple_infos = (
    [ qw/tonerblack CARTRIDGES TONERBLACK/ ],
    [ qw/tonerblack2 CARTRIDGES TONERBLACK2/ ],
    [ qw/tonercyan CARTRIDGES TONERCYAN/ ],
    [ qw/tonermagenta CARTRIDGES TONERMAGENTA/ ],
    [ qw/toneryellow CARTRIDGES TONERYELLOW/ ],
    [ qw/wastetoner CARTRIDGES WASTETONER/ ],
    [ qw/cartridgeblack CARTRIDGES CARTRIDGEBLACK/ ],
    [ qw/cartridgeblackphoto CARTRIDGES CARTRIDGEBLACKPHOTO/ ],
    [ qw/cartridgecyan CARTRIDGES CARTRIDGECYAN/ ],
    [ qw/cartridgecyanlight CARTRIDGES CARTRIDGECYANLIGHT/ ],
    [ qw/cartridgemagenta CARTRIDGES CARTRIDGEMAGENTA/ ],
    [ qw/cartridgemagentalight CARTRIDGES CARTRIDGEMAGENTALIGHT/ ],
    [ qw/cartridgeyellow CARTRIDGES CARTRIDGEYELLOW/ ],
    [ qw/maintenancekit CARTRIDGES MAINTENANCEKIT/ ],
    [ qw/drumblack CARTRIDGES DRUMBLACK/ ],
    [ qw/drumcyan CARTRIDGES DRUMCYAN/ ],
    [ qw/drummagenta CARTRIDGES DRUMMAGENTA/ ],
    [ qw/drumyellow CARTRIDGES DRUMYELLOW/ ],
    [ qw/pagecountertotalpages PAGECOUNTERS TOTAL/ ],
    [ qw/pagecounterblackpages PAGECOUNTERS BLACK/ ],
    [ qw/pagecountercolorpages PAGECOUNTERS COLOR/ ],
    [ qw/pagecounterrectoversopages PAGECOUNTERS RECTOVERSO/ ],
    [ qw/pagecounterscannedpages PAGECOUNTERS SCANNED/ ],
    [ qw/pagecountertotalpages_print PAGECOUNTERS PRINTTOTAL/ ],
    [ qw/pagecounterblackpages_print PAGECOUNTERS PRINTBLACK/ ],
    [ qw/pagecountercolorpages_print PAGECOUNTERS PRINTCOLOR/ ],
    [ qw/pagecountertotalpages_copy PAGECOUNTERS COPYTOTAL/ ],
    [ qw/pagecounterblackpages_copy PAGECOUNTERS COPYBLACK/ ],
    [ qw/pagecountercolorpages_copy PAGECOUNTERS COPYCOLOR/ ],
    [ qw/pagecountertotalpages_fax PAGECOUNTERS FAXTOTAL/ ],
);

my @printer_percent_infos = (
    [ qw/cartridgesblackMAX cartridgesblackREMAIN CARTRIDGE BLACK/ ],
    [ qw/cartridgescyanMAX cartridgescyanREMAIN CARTRIDGE CYAN/ ],
    [ qw/cartridgesyellowMAX cartridgesyellowREMAIN CARTRIDGE YELLOW/ ],
    [ qw/cartridgesmagentaMAX cartridgesmagentaREMAIN CARTRIDGE MAGENTA/ ],
    [ qw/cartridgescyanlightMAX cartridgescyanlightREMAIN CARTRIDGE CYANLIGHT/ ],
    [ qw/cartridgesmagentalightMAX cartridgesmagentalightREMAIN CARTRIDGE MAGENTALIGHT/ ],
    [ qw/cartridgesphotoconductorMAX cartridgesphotoconductorREMAIN CARTRIDGE PHOTOCONDUCTOR/ ],
    [ qw/cartridgesphotoconductorblackMAX cartridgesphotoconductorblackREMAIN CARTRIDGE PHOTOCONDUCTORBLACK/ ],
    [ qw/cartridgesphotoconductorcolorMAX cartridgesphotoconductorcolorREMAIN CARTRIDGE PHOTOCONDUCTORCOLOR/ ],
    [ qw/cartridgesphotoconductorcyanMAX cartridgesphotoconductorcyanREMAIN CARTRIDGE PHOTOCONDUCTORCYAN/ ],
    [ qw/cartridgesphotoconductoryellowMAX cartridgesphotoconductoryellowREMAIN CARTRIDGE PHOTOCONDUCTORYELLOW/ ],
    [ qw/cartridgesphotoconductormagentaMAX cartridgesphotoconductormagentaREMAIN CARTRIDGE PHOTOCONDUCTORMAGENTA/ ],
    [ qw/cartridgesunittransfertblackMAX cartridgesunittransfertblackREMAIN CARTRIDGE UNITTRANSFERBLACK/ ],
    [ qw/cartridgesunittransfertcyanMAX cartridgesunittransfertcyanREMAIN CARTRIDGE UNITTRANSFERCYAN/ ],
    [ qw/cartridgesunittransfertyellowMAX cartridgesunittransfertyellowREMAIN CARTRIDGE UNITTRANSFERYELLOW/ ],
    [ qw/cartridgesunittransfertmagentaMAX cartridgesunittransfertmagentaREMAIN CARTRIDGE UNITTRANSFERMAGENTA/ ],
    [ qw/cartridgeswasteMAX cartridgeswasteREMAIN CARTRIDGE WASTE/ ],
    [ qw/cartridgesfuserMAX cartridgesfuserREMAIN CARTRIDGE FUSER/ ],
    [ qw/cartridgesbeltcleanerMAX cartridgesbeltcleanerREMAIN CARTRIDGE BELTCLEANER/ ],
    [ qw/cartridgesmaintenancekitMAX cartridgesmaintenancekitREMAIN CARTRIDGE MAINTENANCEKIT/ ],
);

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $SIG{INT} = sub {
        warn "detection anormal end of runing program, will close it.\n";

        $self->sendEndToServer();
        return;
    };

    return $self;
}


sub run {
    my ($self) = @_;

    if (!$self->{target}->isa('FusionInventory::Agent::Target::Server')) {
        $self->{logger}->debug("No server. Exiting...");
        return;
    }

    my $options = $self->{prologresp}->getOptionsInfoByName('SNMPQUERY');
    if (!$options) {
        $self->{logger}->debug("No SNMPQUERY. Exiting...");
        return;
    }

    $self->{logger}->debug("FusionInventory SNMPQuery module ".$VERSION);

    FusionInventory::Agent::SNMP->require();
    if ($EVAL_ERROR) {
        $self->{logger}->debug("Can't load Net::SNMP. Exiting...");
        return;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $hour  = sprintf("%02d", $hour);
    $min  = sprintf("%02d", $min);
    $yday = sprintf("%04d", $yday);
    $self->{PID} = $yday.$hour.$min;

    # what is this for ?
    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, MaxLineLength => 16 * 1024);

    $self->startThreads();

    return;
}


sub startThreads {
    my ($self) = @_;

    my $num_files = 1;
    my $device;
    my @devicetype;
    my $num;
    my $log;

    my $storage = $self->{target}->getStorage();

    my $options = $self->{prologresp}->getOptionsInfoByName('SNMPQUERY');
    my $params  = $options->{PARAM}->[0];

    Parallel::ForkManager->require();
    if ($EVAL_ERROR) {
        if ($params->{CORE_QUERY} > 1) {
            $self->{logger}->debug("Parallel::ForkManager not installed, so only 1 core will be used...");
            $params->{CORE_QUERY} = 1;      
        }
    }

    $devicetype[0] = "NETWORKING";
    $devicetype[1] = "PRINTER";

    my $xml_thread = {};

    #===================================
    # Threads et variables partagÃ©es
    #===================================
    my %TuerThread : shared;
    my %ArgumentsThread :shared;
    my $devicelist = {};
    my %devicelist2 : shared;
    my $modelslist = {};
    my $authlist = {};
    my @Thread;
    my $sentxml = {};

    $ArgumentsThread{'id'} = &share([]);
    $ArgumentsThread{'log'} = &share([]);
    $ArgumentsThread{'Bin'} = &share([]);
    $ArgumentsThread{'PID'} = &share([]);

    # Dispatch devices to different core
    my @i;
    my $nbip = 0;
    my @countnb;
    my $core_counter = 0;

    for($core_counter = 0 ; $core_counter < $params->{CORE_QUERY} ; $core_counter++) {
        $countnb[$core_counter] = 0;
        $devicelist2{$core_counter} = &share({});
    }

    $core_counter = 0;
    if (defined($options->{DEVICE})) {
        if (ref($options->{DEVICE}) eq "HASH"){
            #if (keys (%{$data->{DEVICE}}) == 0) {
            for (@devicetype) {
                if ($options->{DEVICE}->{TYPE} eq $_) {
                    if (ref($options->{DEVICE}) eq "HASH"){
                        if ($core_counter eq $params->{CORE_QUERY}) {
                            $core_counter = 0;
                        }
                        $devicelist->{$core_counter}->{$countnb[$core_counter]} = {
                            ID             => $options->{DEVICE}->{ID},
                            IP             => $options->{DEVICE}->{IP},
                            TYPE           => $options->{DEVICE}->{TYPE},
                            AUTHSNMP_ID    => $options->{DEVICE}->{AUTHSNMP_ID},
                            MODELSNMP_ID   => $options->{DEVICE}->{MODELSNMP_ID}
                        };
                        $devicelist2{$core_counter}{$countnb[$core_counter]} = $countnb[$core_counter];
                        $countnb[$core_counter]++;
                        $core_counter++;
                    } else {
                        foreach $num (@{$options->{DEVICE}->{$_}}) {
                            if ($core_counter eq $params->{CORE_QUERY}) {
                                $core_counter = 0;
                            }
                            #### MODIFIER
                            $devicelist->{$core_counter}->{$countnb[$core_counter]} = $num;
                            $devicelist2{$core_counter}[$countnb[$core_counter]] = $countnb[$core_counter];
                            $countnb[$core_counter]++;
                            $core_counter++;
                        }
                    }
                }
            }
        } else {
            foreach $device (@{$options->{DEVICE}}) {
                if (defined($device)) {
                    if (ref($device) eq "HASH"){
                        if ($core_counter eq $params->{CORE_QUERY}) {
                            $core_counter = 0;
                        }
                        #### MODIFIER
                        $devicelist->{$core_counter}->{$countnb[$core_counter]} = {
                            ID             => $device->{ID},
                            IP             => $device->{IP},
                            TYPE           => $device->{TYPE},
                            AUTHSNMP_ID    => $device->{AUTHSNMP_ID},
                            MODELSNMP_ID   => $device->{MODELSNMP_ID}
                        };
                        $devicelist2{$core_counter}{$countnb[$core_counter]} = $countnb[$core_counter];
                        $countnb[$core_counter]++;
                        $core_counter++;
                    } else {
                        foreach $num (@{$device}) {
                            if ($core_counter eq $params->{CORE_QUERY}) {
                                $core_counter = 0;
                            }
                            #### MODIFIER
                            $devicelist->{$core_counter}->{$countnb[$core_counter]} = $num;
                            $devicelist2{$core_counter}[$countnb[$core_counter]] = $countnb[$core_counter];
                            $countnb[$core_counter]++;
                            $core_counter++;
                        }
                    }
                }
            }
        }
    }

    # Models SNMP
    $modelslist = modelParser($options);

    # Auth SNMP
    $authlist = authParser($options);

    my $pm;

    #============================================
    # Begin ForkManager (multiple core / process)
    #============================================
    my $max_procs = $params->{CORE_QUERY}*$params->{THREADS_QUERY};
    if ($params->{CORE_QUERY} > 1) {
        $pm = Parallel::ForkManager->new($max_procs);
    }

    if ($countnb[0] <  $params->{THREADS_QUERY}) {
        $params->{THREADS_QUERY} = $countnb[0];
    }

    my $xml_Thread : shared = '';
    my %xml_out : shared;
    my $sendXML :shared = 0;
    for(my $p = 0; $p < $params->{CORE_QUERY}; $p++) {
        if ($params->{CORE_QUERY} > 1) {
            my $pid = $pm->start and next;
        }
#      write_pid();
        # create the threads
        $TuerThread{$p} = &share([]);
        my $sendbylwp : shared;

# 0 : thread is alive, 1 : thread is dead 
        for(my $j = 0 ; $j < $params->{THREADS_QUERY} ; $j++) {
            $TuerThread{$p}[$j]    = 0;
        }
        #==================================
        # Prepare in variables devices to query
        #==================================
        $ArgumentsThread{'id'}[$p] = &share([]);
        $ArgumentsThread{'Bin'}[$p] = &share([]);
        $ArgumentsThread{'log'}[$p] = &share([]);
        $ArgumentsThread{'PID'}[$p] = &share([]);

        my $i = 0;
        my $Bin;
        while ($i < $params->{THREADS_QUERY}) {
            $ArgumentsThread{'Bin'}[$p][$i] = $Bin;
            $ArgumentsThread{'log'}[$p][$i] = $log;
            $ArgumentsThread{'PID'}[$p][$i] = $self->{PID};
            $i++;
        }
        #===================================
        # Create all Threads
        #===================================
        for(my $j = 0; $j < $params->{THREADS_QUERY}; $j++) {
            $Thread[$p][$j] = threads->create( sub {
                    my $p = shift;
                    my $t = shift;
                    my $devicelist = shift;
                    my $modelslist = shift;
                    my $authlist = shift;
                    my $self = shift;

                    my $device_id;

                    my $xml_thread = {};                                                   
                    my $count = 0;
                    my $xmlout;
                    my $xml;
                    my $data_compressed;
                    my $loopthread = 0;

                    $self->{logger}->debug("Core $p - Thread $t created");

                    while ($loopthread != 1) {
                        # Lance la procÃ©dure et rÃ©cupÃ¨re le rÃ©sultat
                        $device_id = "";
                        {
                            lock(%devicelist2);
                            if (keys %{$devicelist2{$p}} != 0) {
                                my @keys = sort keys %{$devicelist2{$p}};
                                $device_id = pop @keys;
                                delete $devicelist2{$p}{$device_id};
                            } else {
                                $loopthread = 1;
                            }
                        }
                        if ($loopthread != 1) {
                            my $datadevice = $self->query_device_threaded({
                                    device              => $devicelist->{$device_id},
                                    modellist           => $modelslist->{$devicelist->{$device_id}->{MODELSNMP_ID}},
                                    authlist            => $authlist->{$devicelist->{$device_id}->{AUTHSNMP_ID}}
                                });
                            $xml_thread->{DEVICE}->[$count] = $datadevice;
                            $xml_thread->{MODULEVERSION} = $VERSION;
                            $xml_thread->{PROCESSNUMBER} = $params->{PID};
                            $count++;
                            if (($count == 1) || (($loopthread == 1) && ($count > 0))) {
                                $maxIdx++;
                                $storage->save({
                                    idx => $maxIdx,
                                    data => $xml_thread
                                });

                                $count = 0;
                            }
                        }
                        sleep 1;
                    }

                    $TuerThread{$p}[$t] = 1;
                    $self->{logger}->debug("Core $p - Thread $t deleted");
                }, $p, $j, $devicelist->{$p},$modelslist,$authlist,$self)->detach();
            sleep 1;
        }

        # Send infos to server :
        my $xml_thread = {};
        $xml_thread->{AGENT}->{START} = '1';
        $xml_thread->{AGENT}->{AGENTVERSION} = $self->{config}->{VERSION};
        $xml_thread->{MODULEVERSION} = $VERSION;
        $xml_thread->{PROCESSNUMBER} = $params->{PID};
        $self->sendInformations({
                data => $xml_thread
            });
        undef($xml_thread);


        my $exit = 0;
        while($exit == 0) {
            sleep 2;
            my $count = 0;
            for(my $i = 0 ; $i < $params->{THREADS_QUERY} ; $i++) {
                if ($TuerThread{$p}[$i] == 1) {
                    $count++;
                }
                if ( $count eq $params->{THREADS_QUERY} ) {
                    $exit = 1;
                }
            }
            foreach my $idx (1..$maxIdx) {
                if (!defined($sentxml->{$idx})) {
                    my $data = $storage->restore({
                        idx => $idx
                    });

                    $self->sendInformations({
                        data => $data
                    });
                    $sentxml->{$idx} = 1;
                    $storage->remove({
                        idx => $idx
                    });
                    sleep 1;
                }
            }
        }

        if ($params->{CORE_QUERY} > 1) {
            $pm->finish;
        }
    }
    if ($params->{CORE_QUERY} > 1) {
        $pm->wait_all_children;
    }

    foreach my $idx (1..$maxIdx) {
        if (!defined($sentxml->{$idx})) {
            my $data = $storage->restore({
                idx => $idx
            });
            $self->sendInformations({
                data => $data
            });
            $sentxml->{$idx} = 1;
            sleep 1;
        }

    }
    $storage->removeSubDumps();

    # Send infos to server :
    undef($xml_thread);
    $xml_thread->{AGENT}->{END} = '1';
    $xml_thread->{PROCESSNUMBER} = $params->{PID};
    sleep 1; # Wait for threads be terminated
    $self->sendInformations({
            data => $xml_thread
        });
    undef($xml_thread);

}



sub sendEndToServer() {
    my ($self) = @_;

    my $options = $self->{prologresp}->getOptionsInfoByName('SNMPQUERY');
    my $params  = $options->{PARAM}->[0];

    # Send infos to server :
    my $xml_thread;
    $xml_thread->{AGENT}->{END} = '1';
    $xml_thread->{PROCESSNUMBER} = $params->{PID};
    $self->sendInformations({
            data => $xml_thread
        });
    undef($xml_thread);
}

sub sendInformations{
    my ($self, $message) = @_;

    my $xmlMsg = FusionInventory::Agent::XML::Query::SimpleMessage->new({
        logger   => $self->{logger},
        deviceid => $self->{deviceid},
        msg    => {
            QUERY   => 'SNMPQUERY',
            CONTENT => $message->{data},
        },
    });
    $self->{transmitter}->send({
        message => $xmlMsg,
        url     => $self->{target}->getUrl()
    });
}

sub authParser {
    #my ($self, $dataAuth) = @_;
    my $dataAuth = shift;
    my $authlist = {};
    if (ref($dataAuth->{AUTHENTICATION}) eq "HASH"){
        $authlist->{$dataAuth->{AUTHENTICATION}->{ID}} = {
            COMMUNITY      => $dataAuth->{AUTHENTICATION}->{COMMUNITY},
            VERSION        => $dataAuth->{AUTHENTICATION}->{VERSION},
            USERNAME       => $dataAuth->{AUTHENTICATION}->{USERNAME},
            AUTHPASSWORD   => $dataAuth->{AUTHENTICATION}->{AUTHPASSPHRASE},
            AUTHPROTOCOL   => $dataAuth->{AUTHENTICATION}->{AUTHPROTOCOL},
            PRIVPASSWORD   => $dataAuth->{AUTHENTICATION}->{PRIVPASSPHRASE},
            PRIVPROTOCOL   => $dataAuth->{AUTHENTICATION}->{PRIVPROTOCOL}
        };
    } else {
        foreach my $num (@{$dataAuth->{AUTHENTICATION}}) {
            $authlist->{ $num->{ID} } = {
                COMMUNITY      => $num->{COMMUNITY},
                VERSION        => $num->{VERSION},
                USERNAME       => $num->{USERNAME},
                AUTHPASSWORD   => $num->{AUTHPASSPHRASE},
                AUTHPROTOCOL   => $num->{AUTHPROTOCOL},
                PRIVPASSWORD   => $num->{PRIVPASSPHRASE},
                PRIVPROTOCOL   => $num->{PRIVPROTOCOL}
            };
        }
    }
    return $authlist;
}

sub modelParser {
    my $dataModel = shift;

    my $modelslist = {};
    my $lists;
    my $list;
    if (ref($dataModel->{MODEL}) eq "HASH"){
        foreach $lists (@{$dataModel->{MODEL}->{GET}}) {
            $modelslist->{$dataModel->{MODEL}->{ID}}->{GET}->{$lists->{OBJECT}} = {
                OBJECT   => $lists->{OBJECT},
                OID      => $lists->{OID},
                VLAN     => $lists->{VLAN}
            };
        }
        undef $lists;
        foreach $lists (@{$dataModel->{MODEL}->{WALK}}) {
            $modelslist->{$dataModel->{MODEL}->{ID}}->{WALK}->{$lists->{OBJECT}} = {
                OBJECT   => $lists->{OBJECT},
                OID      => $lists->{OID},
                VLAN     => $lists->{VLAN}
            };
        }
        undef $lists;
    } else {
        foreach my $num (@{$dataModel->{MODEL}}) {
            foreach $list ($num->{GET}) {
                if (ref($list) eq "HASH") {

                } else {
                    foreach $lists (@{$list}) {
                        $modelslist->{ $num->{ID} }->{GET}->{$lists->{OBJECT}} = {
                            OBJECT   => $lists->{OBJECT},
                            OID      => $lists->{OID},
                            VLAN     => $lists->{VLAN}
                        };
                    }
                }
                undef $lists;
            }
            foreach $list ($num->{WALK}) {
                if (ref($list) eq "HASH") {

                } else {
                    foreach $lists (@{$list}) {
                        $modelslist->{ $num->{ID} }->{WALK}->{$lists->{OBJECT}} = {
                            OBJECT   => $lists->{OBJECT},
                            OID      => $lists->{OID},
                            VLAN     => $lists->{VLAN}
                        };
                    }
                }
                undef $lists;
            }         
        }
    }
    return $modelslist;
}

sub query_device_threaded {
    my ($self, $params) = @_;

    my $ArraySNMPwalk = {};
    my $HashDataSNMP = {};
    my $datadevice = {};
    my $key;

    #threads->yield;
    ############### SNMP Queries ###############
    my $session = FusionInventory::Agent::SNMP->new ({
        version      => $params->{authlist}->{VERSION},
        hostname     => $params->{device}->{IP},
        community    => $params->{authlist}->{COMMUNITY},
        username     => $params->{authlist}->{USERNAME},
        authpassword => $params->{authlist}->{AUTHPASSWORD},
        authprotocol => $params->{authlist}->{AUTHPROTOCOL},
        privpassword => $params->{authlist}->{PRIVPASSWORD},
        privprotocol => $params->{authlist}->{PRIVPROTOCOL},
        translate    => 1,
    });
    if (!defined($session->{SNMPSession}->{session})) {
        return $datadevice;
    }

    my $error = '';
    # Query for timeout #
    my $description = $session->snmpGet({
        oid => '.1.3.6.1.2.1.1.1.0',
        up  => 1,
    });
    my $insertXML = '';
    if ($description =~ m/No response from remote host/) {
        $error = "No response from remote host";
        $datadevice->{ERROR}->{ID} = $params->{device}->{ID};
        $datadevice->{ERROR}->{TYPE} = $params->{device}->{TYPE};
        $datadevice->{ERROR}->{MESSAGE} = $error;
        return $datadevice;
    } else {
        # Query SNMP get #
        if ($params->{device}->{TYPE} eq "PRINTER") {
            $params = cartridgeSupport($params);
        }
        for $key ( keys %{$params->{modellist}->{GET}} ) {
            if ($params->{modellist}->{GET}->{$key}->{VLAN} == 0) {
                my $oid_result = $session->snmpGet({
                        oid => $params->{modellist}->{GET}->{$key}->{OID},
                        up  => 1,
                    });
                if (defined $oid_result
                    && $oid_result ne ""
                    && $oid_result ne "noSuchObject") {
                    $HashDataSNMP->{$key} = $oid_result;
                }
            }
        }
        $datadevice->{INFO}->{ID} = $params->{device}->{ID};
        $datadevice->{INFO}->{TYPE} = $params->{device}->{TYPE};
        # Conversion
        constructDataDeviceSimple($HashDataSNMP, $datadevice);

        # Query SNMP walk #
        my $vlan_query = 0;
        for $key ( keys %{$params->{modellist}->{WALK}} ) {
            $ArraySNMPwalk = $session->snmpWalk({
                    oid_start => $params->{modellist}->{WALK}->{$key}->{OID}
                });
            $HashDataSNMP->{$key} = $ArraySNMPwalk;
            if (exists($params->{modellist}->{WALK}->{$key}->{VLAN})) {
                if ($params->{modellist}->{WALK}->{$key}->{VLAN} == 1) {
                    $vlan_query = 1;
                }
            }
        }

        # Conversion
        constructDataDeviceMultiple(
            $HashDataSNMP,
            $datadevice,
            $self,
            $params->{modellist}->{WALK}->{vtpVlanName}->{OID},
            $params->{modellist}->{WALK}
        );

        if ($datadevice->{INFO}->{TYPE} eq "NETWORKING") {
            # Scan for each vlan (for specific switch manufacturer && model)
            # Implique de recrÃ©er une session spÃ©cialement pour chaque vlan : communautÃ©@vlanID
            if ($vlan_query == 1) {
                while ( (my $vlan_id,my $vlan_name) = each (%{$HashDataSNMP->{'vtpVlanName'}}) ) {
                    my $vlan_id_short = $vlan_id;
                    $vlan_id_short =~ s/$params->{modellist}->{WALK}->{vtpVlanName}->{OID}//;
                    $vlan_id_short =~ s/^.//;
                    #Initiate SNMP connection on this VLAN
                    my $session = FusionInventory::Agent::SNMP->new({
                        version      => $params->{authlist}->{VERSION},
                        hostname     => $params->{device}->{IP},
                        community    => $params->{authlist}->{COMMUNITY}."@".$vlan_id_short,
                        username     => $params->{authlist}->{USERNAME},
                        authpassword => $params->{authlist}->{AUTHPASSWORD},
                        authprotocol => $params->{authlist}->{AUTHPROTOCOL},
                        privpassword => $params->{authlist}->{PRIVPASSWORD},
                        privprotocol => $params->{authlist}->{PRIVPROTOCOL},
                        translate    => 1,
                    });

                    $ArraySNMPwalk = {};
                    #$HashDataSNMP  = {};
                    for my $link ( keys %{$params->{modellist}->{WALK}} ) {
                        if ($params->{modellist}->{WALK}->{$link}->{VLAN} == 1) {
                            $ArraySNMPwalk = $session->snmpWalk({
                                    oid_start => $params->{modellist}->{WALK}->{$link}->{OID}
                                });
                            $HashDataSNMP->{VLAN}->{$vlan_id}->{$link} = $ArraySNMPwalk;
                        }
                    }
                    # Detect mac adress on each port
                    if ($datadevice->{INFO}->{COMMENTS} =~ /Cisco/) {
                        ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Cisco::GetMAC($HashDataSNMP,$datadevice,$vlan_id,$self, $params->{modellist}->{WALK});
                    }
                    delete $HashDataSNMP->{VLAN}->{$vlan_id};
                }
            } else {
                if (defined ($datadevice->{INFO}->{COMMENTS})) {
                    if ($datadevice->{INFO}->{COMMENTS} =~ /3Com IntelliJack/) {
                        ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::ThreeCom::GetMAC($HashDataSNMP,$datadevice,$self,$params->{modellist}->{WALK});
                        $datadevice = FusionInventory::Agent::Task::SNMPQuery::ThreeCom::RewritePortOf225($datadevice, $self);
                    } elsif ($datadevice->{INFO}->{COMMENTS} =~ /ProCurve/) {
                        ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Procurve::GetMAC($HashDataSNMP,$datadevice,$self, $params->{modellist}->{WALK});
                    }
                }
            }
        }
    }
    return $datadevice;
}

sub constructDataDeviceSimple {
    my $HashDataSNMP = shift;
    my $datadevice = shift;
    if (exists $HashDataSNMP->{macaddr}) {
        $datadevice->{INFO}->{MAC} = $HashDataSNMP->{macaddr};
        delete $HashDataSNMP->{macaddr};
    }
    if (exists $HashDataSNMP->{cpuuser}) {
        $datadevice->{INFO}->{CPU} = $HashDataSNMP->{'cpuuser'} + $HashDataSNMP->{'cpusystem'};
        delete $HashDataSNMP->{'cpuuser'};
        delete $HashDataSNMP->{'cpusystem'};
    }
    foreach my $info (@infos) {
        putSimpleOid($HashDataSNMP, $datadevice, @$info)
    }

    if ($datadevice->{INFO}->{TYPE} eq "PRINTER") {
        foreach my $info (@printer_simple_infos) {
            putSimpleOid($HashDataSNMP, $datadevice, @$info);
        }
        foreach my $info (@printer_percent_infos) {
            putPercentOid($HashDataSNMP, $datadevice, @$info);
        }
    }
}


sub constructDataDeviceMultiple {
    my $HashDataSNMP = shift;
    my $datadevice = shift;
    my $self = shift;
    my $vtpVlanName_oid = shift;
    my $walkoid = shift;

    my $object;
    my $data;

    if (exists $HashDataSNMP->{ipAdEntAddr}) {
        my $i = 0;
        while ( ($object,$data) = each (%{$HashDataSNMP->{ipAdEntAddr}}) ) {
            $datadevice->{INFO}->{IPS}->{IP}->[$i] = $data;
            $i++;
        }
        delete $HashDataSNMP->{ipAdEntAddr};
    }
    if (exists $HashDataSNMP->{ifIndex}) {
        my $num = 0;
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifIndex}}) ) {
            $self->{portsindex}->{lastSplitObject($object)} = $num;
            $datadevice->{PORTS}->{PORT}->[$num]->{IFNUMBER} = $data;
            $num++;
        }
        delete $HashDataSNMP->{ifIndex};
    }
    if (exists $HashDataSNMP->{ifdescr}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifdescr}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFDESCR} = $data;
        }
        delete $HashDataSNMP->{ifdescr};
    }
    if (exists $HashDataSNMP->{ifName}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifName}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFNAME} = $data;
        }
        delete $HashDataSNMP->{ifName};
    }
    if (exists $HashDataSNMP->{ifType}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifType}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFTYPE} = $data;
        }
        delete $HashDataSNMP->{ifType};
    }
    if (exists $HashDataSNMP->{ifmtu}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifmtu}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFMTU} = $data;
        }
        delete $HashDataSNMP->{ifmtu};
    }
    if (exists $HashDataSNMP->{ifspeed}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifspeed}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFSPEED} = $data;
        }
        delete $HashDataSNMP->{ifspeed};
    }
    if (exists $HashDataSNMP->{ifstatus}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifstatus}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFSTATUS} = $data;
        }
        delete $HashDataSNMP->{ifstatus};
    }
    if (exists $HashDataSNMP->{ifinternalstatus}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifinternalstatus}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFINTERNALSTATUS} = $data;
        }
        delete $HashDataSNMP->{ifinternalstatus};
    }
    if (exists $HashDataSNMP->{iflastchange}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{iflastchange}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFLASTCHANGE} = $data;
        }
        delete $HashDataSNMP->{iflastchange};
    }
    if (exists $HashDataSNMP->{ifinoctets}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifinoctets}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFINOCTETS} = $data;
        }
        delete $HashDataSNMP->{ifinoctets};
    }
    if (exists $HashDataSNMP->{ifoutoctets}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifoutoctets}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFOUTOCTETS} = $data;
        }
        delete $HashDataSNMP->{ifoutoctets};
    }
    if (exists $HashDataSNMP->{ifinerrors}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifinerrors}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFINERRORS} = $data;
        }
        delete $HashDataSNMP->{ifinerrors};
    }
    if (exists $HashDataSNMP->{ifouterrors}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifouterrors}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFOUTERRORS} = $data;
        }
        delete $HashDataSNMP->{ifouterrors};
    }
    if (exists $HashDataSNMP->{ifPhysAddress}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifPhysAddress}}) ) {
            if ($data ne "") {
#            my @array = split(/(\S{2})/, $data);
#            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{MAC} = $array[3].":".$array[5].":".$array[7].":".$array[9].":".$array[11].":".$array[13];
                $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{MAC} = $data;
            }
        }
        delete $HashDataSNMP->{ifPhysAddress};
    }
    if (exists $HashDataSNMP->{ifaddr}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{ifaddr}}) ) {
            if ($data ne "") {
                my $shortobject = $object;
                $shortobject =~ s/$walkoid->{ifaddr}->{OID}//;
                $shortobject =~ s/^.//;
                $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{$data}]->{IP} = $shortobject;
            }
        }
        delete $HashDataSNMP->{ifaddr};
    }
    if (exists $HashDataSNMP->{portDuplex}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{portDuplex}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{IFPORTDUPLEX} = $data;
        }
        delete $HashDataSNMP->{portDuplex};
    }

    # Detect Trunk & CDP
    if (defined ($datadevice->{INFO}->{COMMENTS})) {
        if ($datadevice->{INFO}->{COMMENTS} =~ /Cisco/) {
            ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Cisco::TrunkPorts($HashDataSNMP,$datadevice, $self);
            ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Cisco::CDPPorts($HashDataSNMP,$datadevice, $walkoid, $self);
        } elsif ($datadevice->{INFO}->{COMMENTS} =~ /ProCurve/) {
            ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Cisco::TrunkPorts($HashDataSNMP,$datadevice, $self);
            ($datadevice, $HashDataSNMP) = FusionInventory::Agent::Task::SNMPQuery::Procurve::CDPLLDPPorts($HashDataSNMP,$datadevice, $walkoid, $self);
        }
    }

    # Detect VLAN
    if (exists $HashDataSNMP->{vmvlan}) {
        while ( ($object,$data) = each (%{$HashDataSNMP->{vmvlan}}) ) {
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{VLANS}->{VLAN}->{NUMBER} = $data;
            $datadevice->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{VLANS}->{VLAN}->{NAME} = $HashDataSNMP->{vtpVlanName}->{$vtpVlanName_oid.".".$data};
        }
        delete $HashDataSNMP->{vmvlan};
    }
}

sub putSimpleOid {
    my ($HashDataSNMP, $datadevice, $element, $xmlelement1, $xmlelement2) = @_;

    return unless exists $HashDataSNMP->{$element};
    
    SWITCH: {
        if ($element eq "name" || $element eq "otherserial") {
            # Rewrite hexa to string
            $HashDataSNMP->{$element} = hexaToString($HashDataSNMP->{$element});
            last SWITCH;
        }

        if ($element eq "ram" || $element eq "memory") {
            # End rewrite hexa to string
            $HashDataSNMP->{$element} = int(( $HashDataSNMP->{$element} / 1024 ) / 1024);
            last SWITCH;
        }

        if ($element eq "serial") {
            $HashDataSNMP->{$element} =~ s/^\s+//;
            $HashDataSNMP->{$element} =~ s/\s+$//;
            $HashDataSNMP->{$element} =~ s/(\.{2,})*//g;
            last SWITCH;
        }

        if ($element eq "firmware1") {
            $datadevice->{$xmlelement1}->{$xmlelement2} = $HashDataSNMP->{"firmware1"}." ".$HashDataSNMP->{"firmware2"};
            delete $HashDataSNMP->{"firmware2"};
            last SWITCH;
        }
        
        if (
            $element eq "wastetoner"     ||
            $element eq "maintenancekit" ||
            $element =~ /^toner/         ||
            $element =~ /^cartridge/     ||
            $element =~ /^drum/
        ) {
            if ($HashDataSNMP->{$element."-level"} eq "-3") {
                $datadevice->{$xmlelement1}->{$xmlelement2} = 100;
            } else {
                putPercentOid($HashDataSNMP,$datadevice,$element."-capacitytype",$element."-level", $xmlelement1, $xmlelement2);
            }
            last SWITCH;
        }

        # default
        $datadevice->{$xmlelement1}->{$xmlelement2} = $HashDataSNMP->{$element};
    }

    delete $HashDataSNMP->{$element};
}

sub putPercentOid {
    my ($HashDataSNMP, $datadevice, $element1, $element2, $xmlelement1, $xmlelement2) = @_;

    return unless exists $HashDataSNMP->{$element1};

    return unless
        isInteger($HashDataSNMP->{$element2}) &&
        isInteger($HashDataSNMP->{$element1}) &&
        $HashDataSNMP->{$element1} ne '0';

    $datadevice->{$xmlelement1}->{$xmlelement2} =
        int ((100 * $HashDataSNMP->{$element2}) / $HashDataSNMP->{$element1});

    delete $HashDataSNMP->{$element2};
    delete $HashDataSNMP->{$element1};
}



sub lastSplitObject {
    my $var = shift;

    my @array = split(/\./, $var);
    return $array[-1];
}


sub cartridgeSupport {
    my $params = shift;

    for my $key (keys %{$params->{modellist}->{GET}}) {
        next unless
            $key eq "wastetoner"     ||
            $key eq "maintenancekit" ||
            $key =~ /^toner/         ||
            $key =~ /^cartridge/     ||
            $key =~ /^drum/;

        my $capacity = $params->{modellist}->{GET}->{$key."-capacitytype"};
        $capacity->{OID} = $params->{modellist}->{GET}->{$key}->{OID};
        $capacity->{OID} =~ s/43.11.1.1.6/43.11.1.1.8/;
        $capacity->{VLAN} = 0;

        my $level = $params->{modellist}->{GET}->{$key."-level"};
        $level->{OID} = $params->{modellist}->{GET}->{$key}->{OID};
        $level->{OID} =~ s/43.11.1.1.6/43.11.1.1.9/;
        $level->{VLAN} = 0;
    }

    return $params;
}


sub isInteger {
    $_[0] =~ /^[+-]?\d+$/;
}

sub hexaToString {
    my $val = shift;

    if ($val =~ /0x/) {
        $val =~ s/0x//g;
        $val =~ s/([a-fA-F0-9][a-fA-F0-9])/chr(hex($1))/g;
        $val = encode('UTF-8', $val);
        $val =~ s/\0//g;
        $val =~ s/([\x80-\xFF])//g;
        $val =~ s/[\x00-\x1F\x7F]//g;
    }
    return $val;
}

1;
