# Robin

`robin` is a macOS menu-bar push-to-talk transcription app. It appears as Robin in macOS permission prompts and notifications. Use the menu bar Settings item to set the hotkey, Cohere API key, model slug, history folder, insert mode, and language.

Default hotkey:

```text
control+]
```

Transcripts are saved as text files in:

```text
~/Library/Application Support/Robin/History
```

Runtime logs are written to:

```text
~/Library/Application Support/Robin/Robin.log
```

Build and launch:

```bash
./scripts/build_and_run.sh
```

The app records WAV audio while the hotkey is held, sends it to Cohere, saves the transcript, and inserts the latest transcript into the focused text field. Change Insert mode in Settings to copy the finished transcription to the clipboard instead.
