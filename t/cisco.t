#!/usr/bin/perl

use strict;

use Test::More;
use FusionInventory::Agent::Task::SNMPQuery::Cisco;
plan tests => 3;

my $walk = {
    dot1dBasePortIfIndex => {
        OID => '.1.3.6.1.2.17.1.4.1.2'
    },
    dot1dTpFdbAddress => {
        OID => '.1.3.6.1.2.1.17.4.3.1.1'
    },
    dot1dTpFdbPort => {
        OID => '.1.3.6.1.2.1.17.4.3.1.2'
    },
};

my $index = {
    306 => 0,
};

my $data = {
    VLAN => {
        1 => {
            dot1dTpFdbPort => {
                '.1.3.6.1.2.1.17.4.3.1.2.0.28.246.197.100.25' => 2307,
            },
            dot1dTpFdbAddress => {
                '.1.3.6.1.2.1.17.4.3.1.1.0.28.246.197.100.25' => '00 1C F6 C5 64 19',
            },
            dot1dBasePortIfIndex => {
                '.1.3.6.1.2.17.1.4.1.2.2307' => 306,
            }
        }
    }
};

my ($device, $expected);

$device = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                    ]
                },
                MAC => 'X',
            }
        ]
    }
};

$expected = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                        { MAC => '00 1C F6 C5 64 19' }
                    ]
                },
                MAC => 'X',
            }
        ]
    }
};


FusionInventory::Agent::Task::SNMPQuery::Cisco::GetMAC(
    $data, $device, 1, $index, $walk
);

is_deeply(
    $device,
    $expected,
    'connection mac address retrieval'
);

$device = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                    ],
                    CDP => undef,
                },
                MAC => 'X',
            }
        ]
    }
};

$expected = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                    ],
                    CDP => undef,
                },
                MAC => 'X',
            }
        ]
    }
};

FusionInventory::Agent::Task::SNMPQuery::Cisco::GetMAC(
    $data, $device, 1, $index, $walk
);

is_deeply(
    $device,
    $expected,
    'connection mac address retrieval, connection has CDP'
);

$device = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                    ],
                },
                MAC => '00 1C F6 C5 64 19',
            }
        ]
    }
};

$expected = {
    PORTS => {
        PORT => [
            {
                CONNECTIONS => {
                    CONNECTION => [
                    ],
                },
                MAC => '00 1C F6 C5 64 19',
            }
        ]
    }
};

FusionInventory::Agent::Task::SNMPQuery::Cisco::GetMAC(
    $data, $device, 1, $index, $walk
);

is_deeply(
    $device,
    $expected,
    'connection mac address retrieval, same mac address as the port'
);
