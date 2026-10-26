# Camera Control Test

A tiny diagnostic app for iPhone models with Camera Control. It answers one question: does an app that is not a camera app receive Camera Control button events while a camera session runs without a preview?

It uses `AVCaptureEventInteraction` and `AVCaptureSession` controls. Nothing is recorded, saved or sent. The camera permission is requested only when you pick a camera mode.

The app shows camera permission, session state, a counter and a timestamped log of every received event, so the result is visible on screen.

Note: events from Camera Control, the volume-down button and the Action button all arrive in the same handler and cannot be told apart by the event itself. The app also logs light presses and swipes through the session controls, which only Camera Control produces.

Builds are unsigned. Sign and install with your own tool.
