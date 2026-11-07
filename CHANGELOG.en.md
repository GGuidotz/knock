# What's new in Knock

## 0.2.0 · 2026-11-07
First public version: the 8 switches do something, and Knock can listen without the microphone too.

### New features
- **Actions on the switches.** Each double or triple tap can press a key, open an app or an address, run a Shortcut, mute the system microphone, turn off Knock's microphone or all the sensors.
- **Per-app profiles.** Actions can change with the frontmost app: ready-made ones for Claude and Terminal (double right approves, double left rejects) and for Keynote and PowerPoint (next and previous slide), plus "Always" for every other app.
- **Sensors only (experimental).** On Apple silicon MacBooks (M2 and later) Knock can listen with the motion sensor alone: no microphone and no orange dot. When you turn off Knock's microphone or mute the system, it switches by itself, so a tap can turn it back on.
- **Turn off all sensors.** A switch that turns off microphone and sensors to save battery; turn it back on from the menu.
- **Calibration per mode.** Calibrating with microphone and sensors also prepares the microphone-only and sensors-only modes.
- **Short sound**, optional, when a switch triggers.

### Improvements
- **Permissions page with Accessibility**, needed by actions that press a key.

## 0.1.0 · 2026-11-07
First version: taps on the desk next to your Mac become 8 switches.

### New features
- **Eight switches on your desk.** Double or triple tap in one of the four corners around the Mac: Knock knows where and how many times.
- **Microphone and motion sensor.** On Apple silicon MacBooks (M2 and later) Knock also uses the built-in accelerometer, which tells left from right better.
- **Guided calibration.** A map of the desk tells you where to tap and how many times; in a minute and a half Knock learns your desk and tells you how accurate it is.
- **Permissions page.** At launch, if something is missing, Knock shows what it needs, asks for it and checks live that the microphone really hears and the sensor responds; if the microphone stays blocked, Reset clears macOS's decision and the request starts over.
- **Grid in the menu bar.** The square of the zone you tapped lights up with the number of taps; when paused the grid is dimmed.
- **No false alarms while typing.** Taps don't count until a second after the last key.
- **Privacy.** Sound stays in memory for less than two seconds and is never saved or sent.
