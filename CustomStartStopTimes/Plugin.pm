#
# Custom Start Stop Times
#
# (c) 2022 AF
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
use POSIX;
use Time::HiRes qw(time);
use Path::Class;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.customstartstoptimes',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_CUSTOMSTARTSTOPTIMES',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.customstartstoptimes');

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (main::WEBUI) {
		require Plugins::CustomStartStopTimes::Settings;
		Plugins::CustomStartStopTimes::Settings->new($class);
	}

	$prefs->init({
		globaltimecorr => 0,
		tmpignoreperiod => 5
	});
	$prefs->setValidate({'validator' => 'intlimit', 'low' => -2000, 'high' => 2000}, 'globaltimecorr');
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
	Slim::Menu::TrackInfo->registerInfoProvider(csstskipstarttime => (
		above => 'favorites',
		after => 'csststoptime',
		func => sub { return trackInfoHandler('skipstarttime', @_); }
	));
	Slim::Menu::TrackInfo->registerInfoProvider(csstskipstoptime => (
		above => 'favorites',
		after => 'csstskipstarttime',
		func => sub { return trackInfoHandler('skipstoptime', @_); }
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
		main::DEBUGLOG && $log->is_debug && $log->debug('No client. Exiting CSSTcommandCB');
		return;
	}

	my $clientID = $client->id();
	main::DEBUGLOG && $log->is_debug && $log->debug('Received command "'.$request->getRequestString().'" from client "'.$clientID.'"');
	my $track = Slim::Player::Playlist::track($client);

	if (defined $track && $track->remote == 0) {
		my $currentComment = $track->comment;
		if ($currentComment && $currentComment ne '') {
			main::DEBUGLOG && $log->is_debug && $log->debug("Current track's comment on client '".$clientID."' = ".$currentComment);

			my $hasStartTime = $currentComment =~ /STARTTIME:/;
			my $hasStopTime = $currentComment =~ /STOPTIME:/;
			my $hasSkipStartTime = $currentComment =~ /SKIPSTART:/;
			my $hasSkipStopTime = $currentComment =~ /SKIPSTOP:/;

			if ($hasStartTime || $hasStopTime || ($hasSkipStartTime && $hasSkipStopTime)) {
				## newsong
				if ($request->isCommand([['playlist'],['newsong']])) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Received "newsong" cb.');
					# stop old timers for this client
					Slim::Utils::Timers::killTimers($client, \&nextTrack);
					Slim::Utils::Timers::killTimers($client, \&skipPart);
					jumpToStartTime($client, $track) if $hasStartTime;
					customStopTimer($client, $track) if $hasStopTime;;
					$client->pluginData('CSSTskippedTrackID' => '') if ($client->pluginData('CSSTskippedTrackID') && $client->pluginData('CSSTskippedTrackID') ne $track->id);
					customSkipTimer($client, $track) if ($hasSkipStartTime && $hasSkipStopTime);
				}

				## play
				if (($request->isCommand([['playlist'],['play']])) || ($request->isCommand([['mode','play']]))) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Received "play" or "mode play" cb.');
					jumpToStartTime($client, $track) if $hasStartTime;
					customStopTimer($client, $track) if $hasStopTime;
					customSkipTimer($client, $track) if ($hasSkipStartTime && $hasSkipStopTime);
				}

				## pause
				if ($request->isCommand([['pause']]) || $request->isCommand([['mode'],['pause']])) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Received "pause" or "mode pause" cb.');
					my $playmode = Slim::Player::Source::playmode($client);
					main::DEBUGLOG && $log->is_debug && $log->debug('playmode = '.$playmode);

					if ($playmode eq 'pause') {
						Slim::Utils::Timers::killTimers($client, \&nextTrack);
						Slim::Utils::Timers::killTimers($client, \&skipPart);
					} elsif ($playmode eq 'play') {
						customStopTimer($client, $track) if $hasStopTime;
						customSkipTimer($client, $track) if ($hasSkipStartTime && $hasSkipStopTime);
					}
				}

				## stop
				if ($request->isCommand([["stop"]]) || $request->isCommand([['mode'],['stop']]) || $request->isCommand([['playlist'],['stop']]) || $request->isCommand([['playlist'],['sync']]) || $request->isCommand([['playlist'],['clear']]) || $request->isCommand([['power']])) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Received "stop", "clear", "power" or "sync" cb.');
					Slim::Utils::Timers::killTimers($client, \&nextTrack);
					Slim::Utils::Timers::killTimers($client, \&skipPart);
					$client->pluginData('CSSTskippedTrackID' => '');
				}
			}
		}
	}
}

sub jumpToStartTime {
	my ($client, $track) = @_;

	# don't jump if track's custom start time is temp. ignored
	if ($client->pluginData('CSSTignoreThisTrackID') && $client->pluginData('CSSTignoreThisTrackID') eq $track->id) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Custom start time temporarily ignored for track "'.$track->title.'" with ID = '.Data::Dump::dump($client->pluginData('CSSTignoreThisTrackID')));
		return;
	}

	# get custom start time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /STARTTIME:/;
	$currentComment =~ /STARTTIME:([0-9]+([.|,][0-9]+)*)STARTEND?/;
	my $startTime = $1;
	$startTime =~ s/,/./g;
	my $songDuration = $track->secs;
	my $globalTimeCorrection = $prefs->get('globaltimecorr') / 1000;
	if (($startTime + $globalTimeCorrection) >= $songDuration) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Start time >= song duration. Not jumping.');
		return;
	}

	# only jump if current song time < custom start time (don't if rew or relative jump)
	if (($startTime + $globalTimeCorrection) > 0 && Slim::Player::Source::songTime($client) < ($startTime + $globalTimeCorrection) && ($startTime + $globalTimeCorrection) < $track->secs) {
		main::INFOLOG && $log->is_info && $log->info('Jumping to custom start time.');
		$client->execute(['time', $startTime + $globalTimeCorrection]);
	}
}

sub customStopTimer {
	my ($client, $track) = @_;

	# check if track's custom stop time is temp. ignored
	if ($client->pluginData('CSSTignoreThisTrackID') && $client->pluginData('CSSTignoreThisTrackID') eq $track->id) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Custom stop time temporarily ignored for track "'.$track->title.'" with ID = '.Data::Dump::dump($client->pluginData('CSSTignoreThisTrackID')));
		return;
	}

	# get custom stop time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /STOPTIME:/;
	$currentComment =~ /STOPTIME:([0-9]+([.|,][0-9]+)*)STOPEND?/;
	my $stopTime = $1;
	$stopTime =~ s/,/./g;
	my $songDuration = $track->secs;
	my $globalTimeCorrection = $prefs->get('globaltimecorr') / 1000;
	if (($stopTime + $globalTimeCorrection) >= $songDuration) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Stop time >= song duration. Not skipping to next song.');
		return;
	}

	my $currentSongTime = Slim::Player::Source::songTime($client);
	if (($stopTime + $globalTimeCorrection) < $songDuration && $currentSongTime >= ($stopTime + $globalTimeCorrection)) {
		main::INFOLOG && $log->is_info && $log->info('Current song time >= custom stop time. Play next track.');
		nextTrack($client);
	} else {
		my $remainingTime = ($stopTime + $globalTimeCorrection) - $currentSongTime;
		main::DEBUGLOG && $log->is_debug && $log->debug('Current song time = '.$currentSongTime.' seconds -- custom stop time = '.$stopTime.' seconds -- global time correction = '.$globalTimeCorrection.' seconds -- remaining time = '.$remainingTime.' seconds');

		# Start timer for new song
		Slim::Utils::Timers::setTimer($client, time() + $remainingTime, \&nextTrack);
	}
}

sub customSkipTimer {
	my ($client, $track) = @_;

	# check if track's custom skip time is temp. ignored
	if ($client->pluginData('CSSTignoreThisTrackID') && $client->pluginData('CSSTignoreThisTrackID') eq $track->id) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Custom skip time temporarily ignored for track "'.$track->title.'" with ID = '.Data::Dump::dump($client->pluginData('CSSTignoreThisTrackID')));
		return;
	}

	# only skip specific part in currently playing song once
	if ($client->pluginData('CSSTskippedTrackID') && $client->pluginData('CSSTskippedTrackID') eq $track->id) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Have already skipped specified part in currently playing track "'.$track->title.'" with ID = '.$client->pluginData('CSSTskippedTrackID'));
		return;
	}

	# get custom skip start time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /SKIPSTART:/;
	$currentComment =~ /SKIPSTART:([0-9]+([.|,][0-9]+)*)SKIPSTARTXXX?/;
	my $skipStartTime = $1;
	$skipStartTime =~ s/,/./g;
	my $songDuration = $track->secs;
	my $globalTimeCorrection = $prefs->get('globaltimecorr') / 1000;
	if (($skipStartTime + $globalTimeCorrection) >= $songDuration) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Skip start time >= song duration. Not skipping.');
		return;
	}

	my $currentSongTime = Slim::Player::Source::songTime($client);
	if (($skipStartTime + $globalTimeCorrection) < $songDuration && $currentSongTime >= ($skipStartTime + $globalTimeCorrection) && ($currentSongTime - ($skipStartTime + $globalTimeCorrection) <= 10)) { # do not skip after manual jump to a position > 10 secs beyond the skip start time
		main::INFOLOG && $log->is_info && $log->info('Current song time within custom skip start margin (= skip start point + 10 secs). Jump to skip stop time.');
		skipPart($client, $track);
	} else {
		my $remainingTime = ($skipStartTime + $globalTimeCorrection) - $currentSongTime;
		main::DEBUGLOG && $log->is_debug && $log->debug('Current song time = '.$currentSongTime.' seconds -- custom skip start time = '.$skipStartTime.' seconds -- global time correction = '.$globalTimeCorrection.' seconds -- remaining time = '.$remainingTime.' seconds');
		if ($remainingTime < 0) {
			main::INFOLOG && $log->is_info && $log->info('**Manual** jump beyond skip start margin (skip start point + 10 secs). Killing skip timers.');
			Slim::Utils::Timers::killTimers($client, \&skipPart);
			return;
		}

		# Start timer for new song
		Slim::Utils::Timers::setTimer($client, time() + $remainingTime, \&skipPart, $track);
	}
}

sub nextTrack {
	my $client = shift;
	main::INFOLOG && $log->is_info && $log->info('Custom stop time reached. Play next track.');
	$client->execute(['playlist', 'index', '+1']);
}

sub skipPart {
	my ($client, $track) = @_;
	main::INFOLOG && $log->is_info && $log->info('Skipping to custom skip stop time in current track.');

	# get custom skip stop time
	my $currentComment = $track->comment;
	return unless $currentComment =~ /SKIPSTOP:/;
	$currentComment =~ /SKIPSTOP:([0-9]+([.|,][0-9]+)*)SKIPSTOPXXX?/;
	my $skipStopTime = $1;
	$skipStopTime =~ s/,/./g;
	my $globalTimeCorrection = $prefs->get('globaltimecorr') / 1000;
	my $songDuration = $track->secs;
	if (($skipStopTime + $globalTimeCorrection) >= $songDuration) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Skip stop time >= song duration. Not skipping.');
		return;
	}
	my $currentSongTime = Slim::Player::Source::songTime($client);

	$client->execute(['time', $skipStopTime + $globalTimeCorrection]);
	$client->pluginData('CSSTskippedTrackID' => $track->id);
	Slim::Utils::Timers::killTimers($client, \&skipPart);
}

sub trackInfoHandler {
	my ($infoItem, $client, $url, $track, $remoteMeta, $tags, $filter) = @_;
	my $returnVal = 0;
	my $infoItemName = '';
	my $currentComment = $track->comment;

	return unless $currentComment && $currentComment ne '';
	main::DEBUGLOG && $log->is_debug && $log->debug("Current track's comment on client '".$client->id."' = ".$currentComment);

	my $hasStartTime = $currentComment =~ /STARTTIME:/;
	my $hasStopTime = $currentComment =~ /STOPTIME:/;
	my $hasSkipStartTime = $currentComment =~ /SKIPSTART:/;
	my $hasSkipStopTime = $currentComment =~ /SKIPSTOP:/;

	return unless ($hasStartTime || $hasStopTime || ($hasSkipStartTime && $hasSkipStopTime));
	if ($infoItem eq 'starttime') {
		return unless $hasStartTime;
		$currentComment =~ /STARTTIME:([0-9]+([.|,][0-9]+)*)STARTEND?/;
		my $startTime = $1;
		$startTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSTARTTIME');
		$returnVal = formatTime($startTime);
	}

	if ($infoItem eq 'stoptime') {
		return unless $hasStopTime;
		$currentComment =~ /STOPTIME:([0-9]+([.|,][0-9]+)*)STOPEND?/;
		my $stopTime = $1;
		$stopTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSTOPTIME');
		$returnVal = formatTime($stopTime);
	}

	if ($infoItem eq 'skipstarttime') {
		return unless $hasSkipStartTime;
		$currentComment =~ /SKIPSTART:([0-9]+([.|,][0-9]+)*)SKIPSTARTXXX?/;
		my $skipStartTime = $1;
		$skipStartTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSKIPSTARTTIME');
		$returnVal = formatTime($skipStartTime);
	}

	if ($infoItem eq 'skipstoptime') {
		return unless $hasSkipStopTime;
		$currentComment =~ /SKIPSTOP:([0-9]+([.|,][0-9]+)*)SKIPSTOPXXX?/;
		my $skipStopTime = $1;
		$skipStopTime =~ s/,/./g;

		$infoItemName = string('PLUGIN_CUSTOMSTARTSTOPTIMES_CUSTOMSKIPSTOPTIME');
		$returnVal = formatTime($skipStopTime);
	}

	my $displayText = $infoItemName.': '.$returnVal;

	return {
		type => 'text',
		name => $displayText,
	};
}

sub tempIgnoreStartStopTimes {
	my ($client, $url, $track, $remoteMeta, $tags, $filter) = @_;

	my $currentComment = $track->comment;
	return unless $currentComment && $currentComment ne '';
	main::DEBUGLOG && $log->is_debug && $log->debug("Current track's comment on client '".$client->id."' = ".$currentComment);

	my $hasStartTime = $currentComment =~ /STARTTIME:/;
	my $hasStopTime = $currentComment =~ /STOPTIME:/;
	my $hasSkipStartTime = $currentComment =~ /SKIPSTART:/;
	my $hasSkipStopTime = $currentComment =~ /SKIPSTOP:/;

	return unless ($hasStartTime || $hasStopTime || ($hasSkipStartTime && $hasSkipStopTime));

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
	main::DEBUGLOG && $log->is_debug && $log->debug('trackID = '.$trackID);

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
	if (Slim::Utils::PluginManager->isEnabled('Plugins::MaterialSkin::Plugin')) {
		Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$cbMsg, 'client:'.$client->id, 'timeout:4']);
	}
	$request->setStatusDone();
}

sub _tempIgnoreCSST_VFD {
	my ($client, $callback, $params, $trackID) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('trackID = '.$trackID);
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
	$client->pluginData('CSSTignoreThisTrackID' => $track->id);
	Slim::Utils::Timers::setTimer($client, time() + ($tmpIgnorePeriod * 60), \&tempIgnoreEndTimer, $client);

	main::DEBUGLOG && $log->is_debug && $log->debug("Will ignore start/stop times for track '".$track->title."' with ID $trackID for $tmpIgnorePeriod min on client with ID '".$client->id."'");
}

sub tempIgnoreEndTimer {
	my $client = shift;
	$client->pluginData('CSSTignoreThisTrackID' => 'no_id');
	main::DEBUGLOG && $log->is_debug && $log->debug('Ignore period expired.')
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
