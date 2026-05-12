# Robin

`robin` is a macOS menu-bar push-to-talk transcription app. It appears as Robin in macOS permission prompts and notifications. It has no settings UI; edit:

```text
~/Library/Application Support/Robin/config.toml
```

Default hotkey:

```toml
hotkey = "control+]"
delivery_mode = "insert"
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

The app records WAV audio while the hotkey is held, sends it to Cohere, saves the transcript, and inserts the latest transcript into the focused text field. Set `delivery_mode = "clipboard"` to copy the finished transcription instead.
