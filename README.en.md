# Knock

The desk next to your Mac becomes a switch panel. [Italiano](README.md)

Tap the desk two or three times in one of the four corners around your MacBook: Knock knows **where** (top or bottom,
left or right) and **how many times**. That's 8 extra switches, with no accessory. It lives in the menu bar as a small
2x2 grid: the square of the zone you tapped lights up for a moment, with the number of taps next to it.

## Actions

Each switch can press a key, open an app or an address, run a Shortcut, mute the system microphone, turn off Knock's
microphone or all the sensors. Actions change with the frontmost app:

| Profile | Double right | Double left |
|---|---|---|
| Claude (app and Terminal) | Return: approve | Esc: reject |
| Keynote, PowerPoint | next slide | previous slide |

In "Always", for every other app: triple top left turns off all sensors, triple bottom right mutes or unmutes the
microphone, triple bottom left turns Knock's microphone off or on. Everything can be changed in Settings › Actions;
actions that press a key ask for the Accessibility permission.

## Listening modes

- **Microphone and sensors** (default): the most accurate.
- **Sensors only** (experimental, MacBook M2 and later): no microphone and no orange dot. In the test 77% of groups
  and 86% of zones right: taps near the hinge are heard less well. Knock switches to it by itself when you turn off its
  microphone or mute the system, so a tap can turn it back on.
- **Microphone only**: for Macs without the sensor.

## How it works

The Mac's microphone reaches macOS as a single channel, so a tap can't be "triangulated". Knock uses each spot's
signature instead: the tap reaches the Mac through the air and through the desk, and the sound (spectrum, decay) and the
vibration change with the spot. On Apple silicon MacBooks (M2 and later) Knock also reads the built-in accelerometer and
gyroscope, which tell left from right better.

- **Detection.** A tap is a sharp jump in energy above the background; the fading tail doesn't count as a new tap.
  Taps less than 450 ms apart form a group: 2 = double, 3 = triple.
- **Zone.** A guided calibration (24 groups, about a minute and a half) collects samples for each zone; a nearest
  neighbors classifier then recognizes the zone and discards groups that don't look like anything.
- **No false alarms while typing.** Taps don't count until a second after the last key or trackpad movement.

Feasibility test on a 13" MacBook Air M2 (64 guided groups, `tools/` folder): double or triple recognized 89% of the
time, zone 96% (100% top/bottom). Measured with calibration and test in the same session: in real use the desk and the
Mac's position need to stay put, and a new calibration is needed when they change.

## Privacy

Sound stays in memory for less than two seconds and is never recorded, saved or sent. Calibration saves only numbers
(tap features) in `~/Library/Application Support/Knock/`. While Knock listens, macOS shows the orange microphone dot:
that's expected. When paused it uses neither microphone nor sensors.

## Install

```sh
brew install --cask gguidotz/tap/knock
```

Homebrew downloads the DMG from the release, copies the app to Applications and removes the quarantine (the app isn't
notarized). On first launch a short guide asks for microphone permission and leads to calibration.
Update: `brew update && brew upgrade --cask knock`.

From source (needs Xcode or the command line tools):

```sh
git clone https://github.com/GGuidotz/knock.git ~/Developer/knock
cd ~/Developer/knock && ./build.sh --install
```

Requirements: macOS 14 or later. The motion sensor is on MacBooks with M2 and later; without it, Knock uses the
microphone only.

## License

MIT. Feedback and ideas: [Issues](https://github.com/GGuidotz/knock/issues), or from Settings › Feedback.
