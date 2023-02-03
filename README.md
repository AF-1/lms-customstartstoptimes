Custom Start Stop Times
====

**Custom Start Stop Times**[^1] allows you to start and stop tracks at a specified playback/song time.<br>Just add custom start and stop times to a track's comments tag and, with the help of this plugin, the song will start[^2] and end, i.e. skip to the next one, when you want it to. No more annoying song intros or minutes of silence at the end.
<br><br>
[⬅️ **Back to the list of all plugins**](https://github.com/AF-1/)
<br><br><br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br><br>

[^1]:If you want localized strings in your language, read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>.
[^2]:As the LMS source code states: a "jump to a particular time in the current song should be dead-on for CBR, approximate for VBR".

## Comments tag patterns

For this plugin to work, you need to add your custom start and stop times to the **comments tag** of the tracks you wish to start and stop at custom times. For a larger number of songs it probably makes sense to use a script (see macOS Music app example below).<br>
Please use the simple **patterns** described below. They are **case-sensitive** (use upper case) but it doesn't matter whether your time value uses a **comma** or a decimal **point**.<br>

### Start time
- The pattern is: `STARTTIME:{time}STARTEND` where {time} is your start time
- Example: `STARTTIME:5,3462STARTEND` will make your song start at 5.3462 seconds.

### Stop time
- The pattern is: `STOPTIME:{time}STOPEND` where {time} is your stop time, i.e. when LMS skips to the next song.
- Example: `STOPTIME:248,32STOPEND` will make LMS skip to the next song after 248.32 seconds.
<br><br>

### Music app (macOS)
If you use the **Music** app on **macOS**, take a look at the simple **Applescript** included in this repository:<br>
- it can gather songs for which you have set start or stop times in the Music app in a playlist and
- write those start and stop times to the comments tag of those tracks.

Works for me but use at your own risk :-)<br>
If you want to run the script on a large number of tracks, consider *exporting* the script as an *app*.[^3]
<br><br><br>

[^3]: If you want the Music app to list your apps and Applescripts in the Scripts menu, you have to place them in `~/Library/Music/Scripts`.

## Installation

You should be able to install **Custom Start Stop Times** from the LMS main repository (LMS plugin library):<br>**LMS > Settings > Plugins**.<br>

If you want to test a new patch that hasn't made it into a release version yet or you need to install a previous version you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).

It usually takes a few hours for a *new* release to be listed on the LMS plugin page.
<br><br><br>


## Reporting a bug

If you think that you've found a bug, open an [**issue here on GitHub**](https://github.com/AF-1/lms-customstartstoptimes/issues) and fill out the ***Bug report* issue template**. Please post bug reports on **GitHub only**.
<br><br><br><br>
