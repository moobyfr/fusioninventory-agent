package FusionInventory::Agent::Task::Inventory::AIX::Networks;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Unix;
use FusionInventory::Agent::Tools::Network;

sub isEnabled {
    my (%params) = @_;
    return 0 if $params{no_category}->{network};
    return canRun('lscfg');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $routes = getRoutingTable(command => 'netstat -nr', logger => $logger);
    my @interfaces = _getInterfaces(logger => $logger);

    foreach my $interface (@interfaces) {
        $interface->{IPGATEWAY} = $routes->{$interface->{IPSUBNET}}
            if $interface->{IPSUBNET};

        $inventory->addEntry(
            section => 'NETWORKS',
            entry   => $interface
        );
    }

    $inventory->setHardware({
        DEFAULTGATEWAY => $routes->{'0.0.0.0'}
    });
}

sub _getInterfaces {
    my (%params) = @_;

    my $logger = $params{logger};

    # get a list of interfaces from ifconfig
    my @interfaces =
        map { { DESCRIPTION => $_ } }
        split(/ /, getFirstLine(command => 'ifconfig -l'));

    # complete with hardware addresses, extracted from lscfg
    my %addresses = _parseLscfg(
        command => 'lscfg -v -l ent*',
        logger  => $logger
    );

    foreach my $interface (@interfaces) {
        next unless $addresses{$interface->{DESCRIPTION}};
        $interface->{TYPE}    = 'ethernet';
        $interface->{MACADDR} = $addresses{$interface->{DESCRIPTION}};
    }

    # complete with network information, extracted from lsattr
    foreach my $interface (@interfaces) {
        my $handle = getFileHandle(
            command => "lsattr -E -l $interface->{DESCRIPTION}",
            logger  => $logger
        );
        next unless $handle;

        while (my $line = <$handle>) {
            $interface->{IPADDRESS} = $1
                if $line =~ /^netaddr \s+ ($ip_address_pattern)/x;
            $interface->{IPMASK} = $1
                if $line =~ /^netmask \s+ ($ip_address_pattern)/x;
            $interface->{STATUS} = $1
                if $line =~ /^state \s+ (\w+)/x;
        }
        close $handle;
    }

    foreach my $interface (@interfaces) {
        $interface->{IPSUBNET} = getSubnetAddress(
            $interface->{IPADDRESS},
            $interface->{IPMASK},
        );

        $interface->{STATUS} = "Down" unless $interface->{IPADDRESS};
        $interface->{IPDHCP} = "No";

    }

    return @interfaces;
}

sub _parseLscfg {
    my $handle = getFileHandle(@_);
    return unless $handle;

    my %addresses;
    my $current_interface;
    while (my $line = <$handle>) {
        if ($line =~ /^\s+ ent(\d+) \s+ \S+ \s+/x) {
            $current_interface = "en$1";
        }
        if ($line =~ /Network Address\.+($alt_mac_address_pattern)/) {
            $addresses{$current_interface} = alt2canonical($1);
        }
    }
    close $handle;

    return %addresses;
}

1;
