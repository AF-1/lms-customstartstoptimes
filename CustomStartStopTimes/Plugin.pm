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

package Plugins::CustomStartStopTimes::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;
use Slim::Utils::Text;
use Slim::Utils::Unicode;
use Slim::Schema;
use Data::Dumper;
use POSIX;
use Time::HiRes qw(time);
use Path::Class;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

use Plugins::CustomStartStopTimes::Settings;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.customstartstoptimes',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_CUSTOMSTARTSTOPTIMES',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.customstartstoptimes');

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (!$::noweb) {
		require Plugins::CustomStartStopTimes::Settings;
		Plugins::CustomStartStopTimes::Settings->new($class);
	}

	$prefs->init({
		startcorr => 0,
		stopcorr => 0,
		tmpignoreperiod => 5
	});
	$prefs->setValidate({'validator' => 'intlimit', 'low' => -2000, 'high' => 2000}, 'startcorr');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => -2000, 'high' => 2000}, 'stopcorr');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 15}, 'tmpignoreperiod');

	Slim::Menu::TrackInfo->registerInfoProvider(csststarttime => (
		above => 'favorites',
		func => sub { return trackInfoHandler('starttime', @_); }
	));
	Slim::Menu::TrackInfo->registerInfoProvider(csststoptime => (
		above => 'favorites',
		after => 'csststarttime',
		func => sub { return trackInfoHandler('stoptime', @_); }
	));
	Slim::Menu::TrackInfo->registerInfoProvider(cssttempignorestartstoptimes => (
		above => 'favorites',
		after => 'csststoptime',
		func => sub { return tempIgnoreStartStopTimes(@_); }
	));

	Slim::Web::Pages->addPageFunction('tmpignorecsst', \&_tempIgnoreCSST_web);
	Slim::Control::Request::subscribe(\&_CSSTcommandCB,[['mode', 'play', 'stop', 'pause', 'playlist']]);
	Slim::Control::Request::addDispatch(['customstartstoptimes','tmpignorecsst','_trackid'], [1, 0, 1, \&_tempIgnoreCSST_jive]);
}

sub _CSSTcommandCB {
	my $request = shift;
	my $client = $request->client();

	if (!defined $client) {
		$log->debug('No client. Exiting CSSTcommandCB');
		return;
	}

	my $clientID = $client->id();
	$log->debug('Received command "'.$request->getRequestString().'" from client "'.$clientID.'"');
	my $track = $::VERSION lt '8.2' ? Slim::Player::Playlist::song($client) : Slim::Player::Playlist::track($client);

	if (defined $track) {
		if (defined $track && !defined($track->url)) {
			$log->warn('No track url. Exiting.');
			return;
		}

		my $currentComment = $track->comment;
		if ($currentComment && $currentComment ne '') {
			$log->debug("Current track's comment on client '".$clientID."' is ".$currentComment);

			my $hasStartTime = $currentComment =~ /STARTTIME:/;
			my $hasStopTime = $currentComment =~ /STOPTIME:/;

			if ($hasStartTime || $hasStopTime) {
				## newsong
				if ($request->isCommand([['playlist'],['newsong']])) {
					$log->debug('Received "newsong" cb.');
					# stop old timer for this client
					Slim::Utils::Timers::killTimers($client, \&nextTrack);
					jumpToStartTime($client, $track) if $hasStartTime;
					customStopTimer($client, $track) if $hasStopTime;;
				}

				## play
				if (($request->isCommand([['playlist'],['play']])) || ($request->isCommand([['mode','play']]))) {
					$log->debug('Received "play" or "mode play" cb.');
					jumpToStartTime($client, $track) if $hasStartTime;
					customStopTimer($client, $track) if $hasStopTime;
				}

				## pause
				if ($request->isCommand([['pause']]) || $request->isCommand([['mode'],['pause']])) {
					$log->debug('Received "pause" or "mode pause" cb.');
					my $playmode = Slim::Player::Source::playmode($client);
					$log->debug('playmode = '.$playmode);

					if ($playmode eq 'pause') {
						Slim::Utils::Timers::killTimers($client, \&nextTrack);
					} elsif ($playmode eq 'play') {
						customStopTimer($client, $track) if $hasStopTime;
					}
				}

				## stop
				if ($request->isCommand([["stop"]]) || $request->isCommand([['mode'],['stop']]) || $request->isCommand([['playlist'],['stop']]) || $request->isCommand([['playlist'],['sync']]) || $request->isCommand([['playlist'],['clear']]) || $request->isCommand([['power']])) {
					$log->debug('Received "stop", "clear", "power" or "sync" cb.');
					Slim::Utils::Timers::killTimers($client, \&nextTrack);
				}
			}
		}
	}
}

sub jumpToStartTime {
	my ($client, $track) = @_;

	# don't jump if track's custom start/stop times are temp. ignored
	$log->debug('client pluginData = '.Dumper($client->pluginData('CSSTignoreThisTrackURL')));
	return if ($client->pluginData('CSSTignoreThisTrackURL') && $client->pluginData('CSSTignoreThisTrackURL') eq $track->url);

	# get custom start time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /STARTTIME:/;
	$currentComment =~ /STARTTIME:([0-9]+[.|,][0-9]+)STARTEND?/;
	my $startTime = $1;
	$startTime =~ s/,/./g;
	my $startTimeCorrection = $prefs->get('startcorr') / 1000;

	# only jump if current song time < custom start time (don't if rew or relative jump)
	if (($startTime + $startTimeCorrection) > 0 && Slim::Player::Source::songTime($client) < ($startTime + $startTimeCorrection) && ($startTime + $startTimeCorrection) < $track->secs) {
		$client->execute(['time', $startTime + $startTimeCorrection]);
	}
}

sub customStopTimer {
	my ($client, $track) = @_;

	# get custom stop time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /STOPTIME:/;
	$currentComment =~ /STOPTIME:([0-9]+[.|,][0-9]+)STOPEND?/;
	my $stopTime = $1;
	$stopTime =~ s/,/./g;
	my $songDuration = $track->secs;
	my $stopTimeCorrection = $prefs->get('stopcorr') / 1000;
	my $currentSongTime = Slim::Player::Source::songTime($client);
	if (($stopTime + $stopTimeCorrection) < $songDuration && $currentSongTime >= ($stopTime + $stopTimeCorrection)) {
		$log->debug('Current song time >= custom stop time. Play next track.');
		nextTrack($client);
	} else {
		my $remainingTime = ($stopTime + $stopTimeCorrection) - $currentSongTime;
		$log->debug('Current song time = '.$currentSongTime.' seconds -- custom stop time = '.$stopTime.' seconds -- global stop time correction = '.$stopTimeCorrection.' seconds -- remaining time = '.$remainingTime.' seconds');

		# Start timer for new song
		Slim::Utils::Timers::setTimer($client, time() + $remainingTime, \&nextTrack);
	}
}

sub nextTrack {
	my $client = shift;
	$log->debug('Custom stop time reached. Play next track.');
	$client->execute(['playlist', 'index', '+1']);
}

sub trackInfoHandler {
	my ($infoItem, $client, $url, $track, $remoteMeta, $tags, $filter) = @_;
	my $returnVal = 0;
	my $infoItemName = '';
	my $currentComment = $track->comment;

	return unless $currentComment && $currentComment ne '';
	$log->debug("Current track's comment on client '".$client->id."' is ".$currentComment);

	my $hasStartTime = $currentComment =~ /STARTTIME:/;
	my $hasStopTime = $currentComment =~ /STOPTIME:/;

	return unless ($hasStartTime || $hasStopTime);
	if ($infoItem eq 'starttime') {
		return unless $hasStartTime;
		$currentComment =~ /STARTTIME:([0-9]+[.|,][0-9]+)STARTEND?/;
		my $startTime = $1;
		$startTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSTARTTIME');
		$returnVal = formatTime($startTime);
	}

	if ($infoItem eq 'stoptime') {
		return unless $hasStopTime;
		$currentComment =~ /STOPTIME:([0-9]+[.|,][0-9]+)STOPEND?/;
		my $stopTime = $1;
		$stopTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSTOPTIME');
		$returnVal = formatTime($stopTime);
	}

	my $displayText = $infoItemName.': '.$returnVal;

	return {
		type => 'text',
		name => $displayText,
	};
}

sub tempIgnoreStartStopTimes {
	my ($client, $url, $track, $remoteMeta, $tags, $filter) = @_;
	my $tmpIgnorePeriod = $prefs->get('tmpignoreperiod');
	my $displayText = string('PLUGIN_CUSTOMSTARTSTOPTIMES_TEMPIGNORECSSTIMES').' '.$tmpIgnorePeriod.' '.string('SETTINGS_PLUGIN_CUSTOMSTARTSTOPTIMES_TIMEMINS');
	if ($tags->{menuMode}) {
		my $jive = {};
		my $actions = {
			go => {
				player => 0,
				cmd => ['customstartstoptimes', 'tmpignorecsst', $track->id],
				nextWindow => 'parent',
			},
		};
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};
		$jive->{'actions'} = $actions;

		return {
			type => 'text',
			jive => $jive,
			name => $displayText,
			favorites => 0,
		};

	} else {
		my $item = {
			type => 'redirect',
			name => $displayText,
			favorites => 0,
			web => {
				url => 'plugins/CustomStartStopTimes/tmpignorecsst?trackid='.$track->id.'&tmpIgnorePeriod='.$tmpIgnorePeriod
			},
		};

		delete $item->{type};
		$item->{passthrough} = [$track->id];

		my @items = ();
		push(@items, {
			name => string('PLUGIN_CUSTOMSTARTSTOPTIMES_TEMPIGNORECSSTIMES_HEADER'),
			url => \&_tempIgnoreCSST_VFD,
			passthrough => [$track->id],
		});
		$item->{items} = \@items;
		return $item;
	}

}

sub _tempIgnoreCSST_web {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	my $trackID = $params->{'trackid'};
	$log->debug('trackID = '.$trackID);

	_tempIgnoreCSST($client, $trackID);
	return Slim::Web::HTTP::filltemplatefile('plugins/CustomStartStopTimes/html/tmpignorecsst.html', $params);
}

sub _tempIgnoreCSST_jive {
	my $request = shift;
	my $client = $request->client();

	if (!$request->isCommand([['customstartstoptimes'],['tmpignorecsst']])) {
		$log->warn('incorrect command');
		$request->setStatusBadDispatch();
		return;
	}
	if (!defined $client) {
		$log->warn('client required!');
		$request->setStatusNeedsClient();
		return;
	}
	my $trackID = $request->getParam('_trackid');
	if (!defined $trackID) {
		$log->warn('trackID required!');
		return;
	}

	_tempIgnoreCSST($client, $trackID);

	my $tmpIgnorePeriod = $prefs->get('tmpignoreperiod') + 0;
	my $cbMsg = string('PLUGIN_CUSTOMSTARTSTOPTIMES_TEMPIGNORECSSTIMES_DONE').' '.$tmpIgnorePeriod.' '.string('SETTINGS_PLUGIN_CUSTOMSTARTSTOPTIMES_TIMEMINS');
	if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
		$client->showBriefly({'line' => [string('PLUGIN_CUSTOMSTARTSTOPTIMES'), $cbMsg]}, 4);
	}
	$request->setStatusDone();
}

sub _tempIgnoreCSST_VFD {
	my ($client, $callback, $params, $trackID) = @_;
	$log->debug('trackID = '.$trackID);
	my $tmpIgnorePeriod = $prefs->get('tmpignoreperiod') + 0;
	my $cbMsg = string('PLUGIN_CUSTOMSTARTSTOPTIMES_TEMPIGNORECSSTIMES_DONE_SHORT').' '.$tmpIgnorePeriod.' '.string('SETTINGS_PLUGIN_CUSTOMSTARTSTOPTIMES_TIMEMINS');

	_tempIgnoreCSST($client, $trackID);

	$callback->([{
		type => 'text',
		name => $cbMsg,
		showBriefly => 1, popback => 3,
		favorites => 0, refresh => 1,
	}]);
}

sub _tempIgnoreCSST {
	my ($client, $trackID) = @_;
	return if (!$client || !$trackID);

	my $track = Slim::Schema->resultset('Track')->find($trackID);
	if (!defined $track) {
		$log->warn("Couldn't find track for trackID '$trackID'");
		return;
	}

	my $tmpIgnorePeriod = $prefs->get('tmpignoreperiod') + 0;
	Slim::Utils::Timers::killTimers($client, \&tempIgnoreEndTimer);
	$client->pluginData('CSSTignoreThisTrackURL' => $track->url);
	Slim::Utils::Timers::setTimer($client, time() + ($tmpIgnorePeriod * 60), \&tempIgnoreEndTimer, $client);

	$log->debug("Will ignore start/stop times for track '".$track->title."' with ID $trackID for $tmpIgnorePeriod min on client with ID '".$client->id."'");
}

sub tempIgnoreEndTimer {
	my $client = shift;
	$client->pluginData('CSSTignoreThisTrackURL' => 'nourl');
	$log->debug('Ignore period expired.')
}

sub formatTime {
	my $timeinseconds = shift;
	my $seconds = ((int($timeinseconds)) % 60);
	if ($prefs->get('showdecimals')) {
		my $decimals = sprintf("%.2f", ($timeinseconds - int($timeinseconds)));
		$seconds = $seconds + $decimals;
	}
	my $minutes = (int($timeinseconds / (60))) % 60;
	my $formattedTime = ($minutes > 0 ? $minutes : '0').':'.($seconds > 0 ? ($seconds < 10 ? '0'.$seconds : $seconds) : '00');
	return $formattedTime;
}

1;
