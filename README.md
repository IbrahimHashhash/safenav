
  # What's New

  A plain-language summary of the most recent round of improvements. Most of these
  changes are about making the app easier to hear, talk to, and trust.

  ## New features

  ### A spoken welcome when the app opens
  The app now greets the user on launch and briefly explains how to use it — how to
  talk to the assistant and what they can ask for. The same explanation can be
  heard anytime by saying "more info." The wording is short, friendly, and easy to
  remember by ear.

  ### "Change my name" command
  Previously, once the assistant learned the user's name it could not be changed.
  Users can now say "change my name" (or "rename me" / "update my name") and the
  assistant will ask for the new name and save it.

  ### "Repeat" now repeats anything
  Saying "repeat" used to only replay the assistant's last spoken response. It now
  replays the last thing the user actually heard — whether that was a navigation
  instruction, an obstacle warning, or an assistant reply.

  ## Fixes and improvements

  ### The whole screen responds to a tap
  Tapping anywhere on the screen now works to start talking. The on-screen text
  captions no longer block taps, so the user doesn't have to find a specific spot.

  ### Simpler, more predictable tap behavior
  There is now one consistent rule: tap to talk; if the assistant is speaking, a
  tap interrupts it and starts listening; tap again while listening to cancel.

  ### The first word is no longer cut off
  When users tapped and immediately spoke, the first word (for example "start" in
  "start navigation") was often lost while the microphone was still connecting. The
  app now begins capturing audio the moment the user taps, so nothing is missed.

  ### Cue sounds are reliable again
  addded a stop sound so the user knows when the state changes back to listening or idle 
  
  ### Obstacle warnings stop repeating ("spamming")
  Warnings like "path likely blocked" or "chair 3 meters ahead" were being
  announced over and over. The app now announces a given warning once and then
  stays quiet for a cooldown period — even when only the distance changes (e.g.
  "chair 3 meters ahead" then "chair 2 meters ahead" is treated as the same
  warning). Genuinely different warnings (a different obstacle, or a different
  direction) are still announced right away.

  ### Voice commands are understood more reliably
  - Commands are recognized even when slightly misheard (for example a small
    mispronunciation of "detection" still works).
  - Random or unrelated speech no longer triggers commands by accident.
  - When speech is genuinely unclear or could mean two different commands, the
    assistant asks the user to repeat instead of guessing and doing the wrong
    thing — important for a safety app.

  ### Cleaner, less distracting on-screen captions
  The "You said" and "Assistant" text boxes are more subtle and blend with the
  background. They appear only while the user is speaking or the assistant is
  replying (fading in and out) rather than sitting on screen permanently, and long
  messages are trimmed neatly. The assistant's caption now also appears
  consistently, including for the welcome message.

  ## Quality
  All automated tests pass (141 tests), including new tests covering the obstacle
  warning cooldown and the improved command understanding.
