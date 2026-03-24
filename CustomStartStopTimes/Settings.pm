#
# Custom Start Stop Times
# (c) 2022 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomStartStopTimes::Settings;

use strict;
use warnings;
use utf8;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log = logger('plugin.customstartstoptimes');
my $prefs = preferences('plugin.customstartstoptimes');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CUSTOMSTARTSTOPTIMES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/CustomStartStopTimes/settings/settings.html');
}

sub prefs {
	return ($prefs, qw(showdecimals globaltimecorr tmpignoreperiod));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

1;
