Custom Start Stop Times
====

**Custom Start Stop Times** allows you to start and stop tracks at a specified playback/song time.<br>Just add custom start and stop times to a track's comments tag and, with the help of this plugin, the song will start[^1] and end, i.e. skip to the next one, when you want it to. No more annoying song intros or minutes of silence at the end.
<br><br><br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br><br>

[^1]:As the LMS source code states: a "jump to a particular time in the current song should be dead-on for CBR, approximate for VBR".

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
If you want to run the script on a large number of tracks, consider *exporting* the script as an *app*.[^2]
<br><br><br>

[^2]: If you want the Music app to list your apps and Applescripts in the Scripts menu, you have to place them in `~/Library/Music/Scripts`.

## Installation

### Using the repository URL

- Add the repository URL below at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply*:
[https://raw.githubusercontent.com/AF-1/lms-customstartstoptimes/main/public.xml](https://raw.githubusercontent.com/AF-1/lms-customstartstoptimes/main/public.xml)

- Install the new version
<br>

### Manual Install

Please read notes on how to [install a plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).
<br><br><br>


## Translation
The [**strings.txt**](https://github.com/AF-1/lms-customstartstoptimes/blob/main/CustomStartStopTimes/strings.txt) file contains all localizable strings. Once you're done **testing** the plugin with your translated strings, just create a pull request on GitHub.<br>
* Please try not to use the [**single**](https://www.fileformat.info/info/unicode/char/27/index.htm) quote character (apostrophe) or the [**double**](https://www.fileformat.info/info/unicode/char/0022/index.htm) quote character (quotation mark) in your translated strings. They could cause problems. You can use the [*right single quotation mark*](https://www.fileformat.info/info/unicode/char/2019/index.htm) or the [*double quotation mark*](https://www.fileformat.info/info/unicode/char/201d/index.htm) instead. And if possible, avoid (special) characters that are used as [**metacharacters**](https://en.wikipedia.org/wiki/Metacharacter) in programming languages (Perl), regex or SQLite.
* It's probably not a bad idea to keep the translated strings roughly as long as the original ones.<br>
* Some of these strings are supposed to be used with different UIs: my tests usually cover the LMS *default* skin, *Material* skin, *piCorePlayer* (or any other jivelite player like *SqueezePlay*) and maybe some ip3k player like *Boom* if applicable.
* Please leave *(multiple) blank lines* (used to visually delineate different parts) as they are.
<br>
