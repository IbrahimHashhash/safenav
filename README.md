I have used push-to-talk instead of an activation phrase. It works as a simple toggle: tap once to start listening, and tap again to stop listening and receive a response.

While the assistant is speaking, tapping the screen will immediately stop the speech and return the assistant to the idle state.

---

## There are 3 states

The voice assistant is always in one of three states:

* **Idle** — waiting for user interaction
* **Listening** — listening for user commands
* **Speaking** — reading responses out loud

---

## The voice models

For speech-to-text, I used **Azure Cognitive Services**. I tried local models such as: Vosk and Flutter STT, but their accuracy was quite poor (also vosk was not native to flutter so harder integration).

For text-to-speech, I used **Flutter TTS** since we are prioritizing performance. The voice sounds somewhat robotic and unclear. 

---

## Three types of instructions

Not all instructions have the same priority:

* **Obstacle warnings** have the highest priority.
* **Navigation instructions** have the second-highest priority.
* **Assistant responses** have the lowest priority.

---
## Obstacle avoidance and mapbox services
In the Cubit, there are specialized `speak` methods for each type of instruction. These methods already handle the appropriate behavior and priority logic for their respective services, so use them instead of calling the generic speech functionality directly.

You may need to rewire the Mapbox service to integrate properly with this flow. However, for obstacle avoidance, you only need to modify the endpoint, as the rest of the handling logic is already implemented.

For navigation, the destination is already being extracted, and the locations have already been defined, so you only need to work with the extracted destination value.

---

## Priority queue for handling incoming instructions

If an assistant response is currently playing and a navigation instruction arrives, the navigation instruction will override it. The interrupted assistant response will be stored in a queue and resumed once the navigation instruction has finished.

Similarly, if an obstacle warning arrives, it will override both navigation instructions and assistant responses. Any interrupted instructions will be queued and resumed after the obstacle warning has finished.

---

Try running the program first, along with the mock avoidance instructions included in the Python code to see how it works. Do not merge your code unless you try it and rewire things. You may need to adjust the UI, but make sure the user can tap anywhere on the screen.
Final note: for the code, it is better if you read through it and understand it yourself. External sources may explain it better than I can :). The overall flow is not that difficult to grasp.
