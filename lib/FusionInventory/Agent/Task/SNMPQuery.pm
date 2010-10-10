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
use FusionInventory::Agent::Task::SNMPQuery::Tools;

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

    my @devicetype = qw/
        NETWORKING
        PRINTER
    /;

    #===================================
    # Threads et variables partagÃ©es
    #===================================
    my %TuerThread : shared;
    my %ArgumentsThread :shared;
    my $devicelist = {};
    my %devicelist2 : shared;
    my @Thread;
    my $sentxml = {};

    $ArgumentsThread{'id'} = &share([]);
    $ArgumentsThread{'log'} = &share([]);
    $ArgumentsThread{'Bin'} = &share([]);
    $ArgumentsThread{'PID'} = &share([]);

    # Dispatch devices to different core
    my @countnb;

    for (my $i = 0 ; $i < $params->{CORE_QUERY} ; $i++) {
        $countnb[$i] = 0;
        $devicelist2{$i} = &share({});
    }

    my $core_counter = 0;
    if (defined($options->{DEVICE})) {
        if (ref($options->{DEVICE}) eq "HASH") {
            foreach my $type (@devicetype) {
                next unless $options->{DEVICE}->{TYPE} eq $type;
                if (ref($options->{DEVICE}) eq "HASH") {
                    if ($core_counter eq $params->{CORE_QUERY}) {
                        $core_counter = 0;
                    }
                    $devicelist->{$core_counter}->{$countnb[$core_counter]} = 
                        $options->{DEVICE};
                    $devicelist2{$core_counter}{$countnb[$core_counter]} = $countnb[$core_counter];
                    $countnb[$core_counter]++;
                    $core_counter++;
                } else {
                    foreach my $num (@{$options->{DEVICE}->{$type}}) {
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
        } else {
            foreach my $device (@{$options->{DEVICE}}) {
                next unless $device;
                if (ref $device eq "HASH") {
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
                    foreach my $num (@{$device}) {
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

    # Models SNMP
    my $modelslist = getModelsList($options);

    # Auth SNMP
    my $authlist = FusionInventory::Agent::SNMP->getAuthList($options);

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
        $ArgumentsThread{'PID'}[$p] = &share([]);

        my $Bin;
        for (my $i = 0; $i < $params->{THREADS_QUERY}; $i++) {
            $ArgumentsThread{'Bin'}[$p][$i] = $Bin;
            $ArgumentsThread{'PID'}[$p][$i] = $self->{PID};
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
        my $xml_thread = {
            AGENT => {
                START => 1,
                AGENTVERSION => $self->{config}->{VERSION}
            },
            MODULEVERSION => $VERSION,
            PROCESSNUMBER => $params->{PID}
        };
        $self->sendInformations({
            data => $xml_thread
        });

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
            foreach my $idx (1 .. $maxIdx) {
                next if $sentxml->{$idx};
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

        if ($params->{CORE_QUERY} > 1) {
            $pm->finish;
        }
    }
    if ($params->{CORE_QUERY} > 1) {
        $pm->wait_all_children;
    }

    foreach my $idx (1 .. $maxIdx) {
        next if $sentxml->{$idx};
        my $data = $storage->restore({
            idx => $idx
        });
        $self->sendInformations({
            data => $data
        });
        $sentxml->{$idx} = 1;
        sleep 1;
    }
    $storage->removeSubDumps();

    # Send infos to server :
    my $xml_thread = {
        AGENT => { END => 1 },
        PROCESSNUMBER => $params->{PID}
    };
    sleep 1; # Wait for threads be terminated
    $self->sendInformations({
        data => $xml_thread
    });
}



sub sendEndToServer {
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

sub sendInformations {
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

sub getModelsList {
    my ($options) = @_;

    my $list;

    if (ref($options->{MODEL}) eq "HASH") {
        # a single model object
        foreach my $item (@{$options->{MODEL}->{GET}}) {
            $list->{$options->{MODEL}->{ID}}->{GET}->{$item->{OBJECT}} = $item;
        }
        foreach my $item (@{$options->{MODEL}->{WALK}}) {
            $list->{$options->{MODEL}->{ID}}->{WALK}->{$item->{OBJECT}} = $item;
        }
    } else {
        # a list of model objects
        foreach my $model (@{$options->{MODEL}}) {
            foreach my $item ($model->{GET}) {
                $list->{$model->{ID}}->{GET}->{$item->{OBJECT}} = $item;
            }
            foreach my $item ($model->{WALK}) {
                $list->{$model->{ID}}->{WALK}->{$item->{OBJECT}} = $item;
            }
        }
    }

    return $list;
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
        authpassword => $params->{authlist}->{AUTHPASSPHRASE},
        authprotocol => $params->{authlist}->{AUTHPROTOCOL},
        privpassword => $params->{authlist}->{PRIVPASSPHRASE},
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
            $self->{portsindex},
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
    my ($data, $device) = @_;

    if (exists $data->{macaddr}) {
        $device->{INFO}->{MAC} = $data->{macaddr};
        delete $data->{macaddr};
    }

    if (exists $data->{cpuuser}) {
        $device->{INFO}->{CPU} = $data->{'cpuuser'} + $data->{'cpusystem'};
        delete $data->{'cpuuser'};
        delete $data->{'cpusystem'};
    }

    foreach my $info (@infos) {
        putSimpleOid($data, $device, @$info)
    }

    if ($device->{INFO}->{TYPE} eq "PRINTER") {
        foreach my $info (@printer_simple_infos) {
            putSimpleOid($data, $device, @$info);
        }
        foreach my $info (@printer_percent_infos) {
            putPercentOid($data, $device, @$info);
        }
    }
}


sub constructDataDeviceMultiple {
    my ($data, $device, $index, $vtpVlanName_oid, $walkoid) = @_;

    my $port = $device->{PORTS}->{PORT};

    if (exists $data->{ipAdEntAddr}) {
        my $i = 0;
        while (my ($key, $value) = each %{$data->{ipAdEntAddr}}) {
            $device->{INFO}->{IPS}->{IP}->[$i] = $value;
            $i++;
        }
        delete $data->{ipAdEntAddr};
    }

    if (exists $data->{ifIndex}) {
        my $num = 0;
        while (my ($key, $value) = each %{$data->{ifIndex}}) {
            $index->{lastSplitObject($key)} = $num;
            $port->[$num]->{IFNUMBER} = $value;
            $num++;
        }
        delete $data->{ifIndex};
    }

    if (exists $data->{ifdescr}) {
        while (my ($key, $value) = each %{$data->{ifdescr}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFDESCR} = $value;
        }
        delete $data->{ifdescr};
    }

    if (exists $data->{ifName}) {
        while (my ($key, $value) = each %{$data->{ifName}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFNAME} = $value;
        }
        delete $data->{ifName};
    }

    if (exists $data->{ifType}) {
        while (my ($key, $value) = each %{$data->{ifType}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFTYPE} = $value;
        }
        delete $data->{ifType};
    }

    if (exists $data->{ifmtu}) {
        while (my ($key, $value) = each %{$data->{ifmtu}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFMTU} = $value;
        }
        delete $data->{ifmtu};
    }

    if (exists $data->{ifspeed}) {
        while (my ($key, $value) = each %{$data->{ifspeed}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFSPEED} = $value;
        }
        delete $data->{ifspeed};
    }

    if (exists $data->{ifstatus}) {
        while (my ($key, $value) = each %{$data->{ifstatus}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFSTATUS} = $value;
        }
        delete $data->{ifstatus};
    }

    if (exists $data->{ifinternalstatus}) {
        while (my ($key, $value) = each %{$data->{ifinternalstatus}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFINTERNALSTATUS} = $value;
        }
        delete $data->{ifinternalstatus};
    }

    if (exists $data->{iflastchange}) {
        while (my ($key, $value) = each %{$data->{iflastchange}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFLASTCHANGE} = $value;
        }
        delete $data->{iflastchange};
    }

    if (exists $data->{ifinoctets}) {
        while (my ($key, $value) = each %{$data->{ifinoctets}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFINOCTETS} = $value;
        }
        delete $data->{ifinoctets};
    }

    if (exists $data->{ifoutoctets}) {
        while (my ($key, $value) = each %{$data->{ifoutoctets}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFOUTOCTETS} = $value;
        }
        delete $data->{ifoutoctets};
    }

    if (exists $data->{ifinerrors}) {
        while (my ($key, $value) = each %{$data->{ifinerrors}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFINERRORS} = $value;
        }
        delete $data->{ifinerrors};
    }

    if (exists $data->{ifouterrors}) {
        while (my ($key, $value) = each %{$data->{ifouterrors}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFOUTERRORS} = $value;
        }
        delete $data->{ifouterrors};
    }

    if (exists $data->{ifPhysAddress}) {
        while (my ($key, $value) = each %{$data->{ifPhysAddress}}) {
            if ($data ne "") {
#            my @array = split(/(\S{2})/, $data);
#            $device->{PORTS}->{PORT}->[$self->{portsindex}->{lastSplitObject($object)}]->{MAC} = $array[3].":".$array[5].":".$array[7].":".$array[9].":".$array[11].":".$array[13];
                $port->[$index->{lastSplitObject($key)}]->{MAC} = $value;
            }
        }
        delete $data->{ifPhysAddress};
    }

    if (exists $data->{ifaddr}) {
        while (my ($key, $value) = each %{$data->{ifaddr}}) {
            if ($data ne "") {
                my $shortobject = $key;
                $shortobject =~ s/$walkoid->{ifaddr}->{OID}//;
                $shortobject =~ s/^.//;
                $port->[$index->{$value}]->{IP} = $shortobject;
            }
        }
        delete $data->{ifaddr};
    }

    if (exists $data->{portDuplex}) {
        while (my ($key, $value) = each %{$data->{portDuplex}}) {
            $port->[$index->{lastSplitObject($key)}]->{IFPORTDUPLEX} = $value;
        }
        delete $data->{portDuplex};
    }

    # Detect Trunk & CDP
    if (defined ($device->{INFO}->{COMMENTS})) {
        if ($device->{INFO}->{COMMENTS} =~ /Cisco/) {
            FusionInventory::Agent::Task::SNMPQuery::Cisco::TrunkPorts($data, $device, $index);
            FusionInventory::Agent::Task::SNMPQuery::Cisco::CDPPorts($data, $device, $walkoid, $index);
        } elsif ($device->{INFO}->{COMMENTS} =~ /ProCurve/) {
            FusionInventory::Agent::Task::SNMPQuery::Cisco::TrunkPorts($data, $device, $index);
            FusionInventory::Agent::Task::SNMPQuery::Procurve::CDPLLDPPorts($data, $device, $walkoid, $index);
        }
    }

    # Detect VLAN
    if (exists $data->{vmvlan}) {
        while (my ($key, $value) = each %{$data->{vmvlan}}) {
            $port->[$index->{lastSplitObject($key)}]->{VLANS}->{VLAN}->{NUMBER} = $value;
            $port->[$index->{lastSplitObject($key)}]->{VLANS}->{VLAN}->{NAME} = $data->{vtpVlanName}->{$vtpVlanName_oid.".".$value};
        }
        delete $data->{vmvlan};
    }
}

sub putSimpleOid {
    my ($data, $device, $element, $xmlelement1, $xmlelement2) = @_;

    return unless exists $data->{$element};
    
    NORMALISATION: {
        if ($element eq "name" || $element eq "otherserial") {
            # Rewrite hexa to string
            $data->{$element} = hexaToString($data->{$element});
            last NORMALISATION;
        }

        if ($element eq "ram" || $element eq "memory") {
            # End rewrite hexa to string
            $data->{$element} = int(( $data->{$element} / 1024 ) / 1024);
            last NORMALISATION;
        }

        if ($element eq "serial") {
            $data->{$element} =~ s/^\s+//;
            $data->{$element} =~ s/\s+$//;
            $data->{$element} =~ s/(\.{2,})*//g;
            last NORMALISATION;
        }
    }

    AFFECTATION: {
        if ($element eq "firmware1") {
            $device->{$xmlelement1}->{$xmlelement2} = 
                $data->{firmware1} . " " . $data->{firmware2};
            delete $data->{firmware2};
            last AFFECTATION;
        }
        
        if (
            $element eq "wastetoner"     ||
            $element eq "maintenancekit" ||
            $element =~ /^toner/         ||
            $element =~ /^cartridge/     ||
            $element =~ /^drum/
        ) {
            if ($data->{$element."-level"} eq "-3") {
                $device->{$xmlelement1}->{$xmlelement2} = 100;
            } else {
                putPercentOid(
                    $data,
                    $device,
                    $element . "-capacitytype",
                    $element . "-level",
                    $xmlelement1,
                    $xmlelement2
                );
            }
            last AFFECTATION;
        }

        # default
        $device->{$xmlelement1}->{$xmlelement2} = $data->{$element};
    }

    delete $data->{$element};
}

sub putPercentOid {
    my ($data, $device, $element1, $element2, $xmlelement1, $xmlelement2) = @_;

    return unless exists $data->{$element1};

    return unless
        isInteger($data->{$element2}) &&
        isInteger($data->{$element1}) &&
        $data->{$element1} ne '0';

    $device->{$xmlelement1}->{$xmlelement2} =
        int ((100 * $data->{$element2}) / $data->{$element1});

    delete $data->{$element2};
    delete $data->{$element1};
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
    return $_[0] =~ /^[+-]?\d+$/;
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
