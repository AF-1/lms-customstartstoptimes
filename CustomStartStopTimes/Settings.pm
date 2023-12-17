#
# Custom Start Stop Times
#
# (c) 2022 AF-1
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
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
