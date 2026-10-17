# AV settings (stream audio/video sync)

Operational notes for keeping **audio aligned with video** on the live YouTube stream. SceneSlider only switches OBS scenes from PowerPoint; it does **not** change stream latency or A/V delay. Sync is configured in **OBS** and **YouTube Live**.

## Verified baseline

These values were tested on YouTube with **Normal** latency. Lip and movement matched the heard audio on the stream.

| Setting | Value |
|--------|--------|
| YouTube stream latency | **Normal** |
| OBS audio sync offset (positive) | **+1700 ms** |

In OBS, the offset is **Sync Offset (ms)** under **Mixer → gear icon → Advanced Audio Properties**. Apply it to the mixer source that carries **program speech / room audio** (typically **Mic/Aux**). Positive values delay that audio so it lines up with video in the **encoded stream and recordings**.

**Important:** Sync offset affects what viewers hear on the stream and what recordings contain. It does **not** fix what you hear in local OBS monitoring or what the mixer meters show—always verify on **YouTube live or VOD**, not only in the OBS preview.

## YouTube

Latency mode is a tradeoff between **how fast viewers see the stream** and **which resolutions YouTube will deliver**. Our A/V sync baseline was verified with **Normal** latency.

| Latency mode | Typical viewer delay | Max stream quality (observed / YouTube) |
|--------------|----------------------|-------------------------------------------|
| **Normal** | Higher (more buffering for viewers) | **All resolutions**, including 4K; full live feature set |
| **Low** | Usually under ~10 seconds | **Up to 1440p** — **4K is not supported** in this mode |
| **Ultra-low** | Usually under ~5 seconds | **1080p and below** (no 1440p / 4K) |

If you need **4K** (2160p) on the live stream, use **Normal** latency. **Low** latency is appropriate when you want faster interaction but can accept a **1440p ceiling** (and no 4K).

1. Open **YouTube Studio** for the live stream.
2. Choose latency under stream settings (we use **Normal** for the verified sync values in this doc).
3. If you change latency mode or output resolution, re-check lip sync on a short live segment or replay and confirm the quality tier viewers actually get.

Official reference: [YouTube live streaming latency](https://support.google.com/youtube/answer/7444635).

## OBS — audio delay (match audio to video)

Use this when **video is behind** the audio viewers hear (mouth moves before the sound).

1. In OBS, find the **Audio Mixer**.
2. Click the **gear** on the program audio source → **Advanced Audio Properties**.
3. In **Sync Offset (ms)**, enter **1700** (milliseconds = 1 second; 1700 ms = 1.7 s).
4. Close the dialog. OBS remembers the value for future sessions.

Tune only the source that should stay locked to the main video. Other mixer channels (e.g. desktop audio) usually stay at **0** unless they have their own delay path.

## Physical audio path (PC capture)

Program audio into the streaming PC follows this chain:

```text
PIMA (stereo output, rear) → cable → Behringer UCA202 (line in) → USB → PC → OBS
```

The **Behringer UCA202** is the USB interface OBS sees as the capture device for this feed. Sync offset (+1700 ms) applies to this path in the mixer once it is in OBS.

## Whine on the PIMA → UCA202 feed (open issue)

A **whine** (high-pitched noise) is audible on the stream when this feed is connected. Isolation so far:

| Observation | Implication |
|-------------|-------------|
| Disconnecting the cable **from the Behringer** (PIMA side or interface input) | Whine **stops** |
| UCA202 with **no cable** plugged in | Interface is **silent** — noise is not coming from the box itself |
| Cable / PIMA end wiring | **Likely source** — needs a proper look |

**Wiring note (PIMA end):** The run uses **two conductors**. Before they enter the PIMA, the **copper of one is wrapped around the other**, then both go into the PIMA rear stereo connection. That is non-standard for a typical balanced or simple stereo pair; document photos or a sketch before changing anything, then verify whether the PIMA expects TS, TRS, RCA, or speaker-level taps.

**Things to check when investigating** (update this list as you learn more):

- Whether the PIMA output is **line level** vs **speaker** output — speaker taps into a line input can cause distortion, hum, or whine.
- **Ground loops**: try same power outlet vs isolated ground, short cable run, and whether a **ground-lift** or **DI box** is appropriate (only if you understand safety — never lift earth on mains-powered gear recklessly).
- Replace or re-terminate the cable with a proper **stereo pair** (or balanced run if the PIMA supports it) instead of the wrapped-conductor hack.
- Confirm **input gain** on the UCA202 (rear switch) matches the PIMA output level.

Until the whine is fixed in hardware, OBS noise suppression may mask it slightly but will not fix the root cause.

## OBS — video delay (reference)

If delaying audio is not appropriate for a source, you can delay **video** instead:

1. Right-click the delayed **video** source → **Filters**.
2. Add **Render Delay** and set delay in milliseconds.

A single Render Delay filter is limited (often 500 ms in OBS). Larger video delays may require stacked filters or scene-level delays. Our current setup uses **+1700 ms on audio**, not video render delay.

## How to verify

1. Start or use a test stream with YouTube **Normal** latency and OBS **Sync Offset +1700 ms** on program audio.
2. Watch playback on **YouTube** (another device or logged-in replay). Confirm speech and mouth movement stay aligned.
3. Optional **clap test:** record a short segment while clapping; in an editor, count frames between the visual clap and the audio spike, convert to milliseconds, and adjust Sync Offset in small steps (e.g. 50–100 ms) around **1700** if needed.

## When to re-tune

Re-check sync after any of these change:

- Camera, capture card, or HDMI/USB video path
- Microphone, audio interface, wireless mic, or **PIMA → UCA202** wiring
- OBS major upgrade or new audio/video plugins
- YouTube latency mode or max resolution (e.g. moving between Normal and Low changes both delay and whether 4K is available)
- Heavy load causing skipped or lagged frames (see OBS **Stats**)

Prefer **48 kHz** sample rate consistently across Windows sound devices and OBS when possible. If audio drifts or stays wrong despite offset, review OBS logs/analyzer and source settings (e.g. device timestamps on audio sources).

## Maintenance

- Update the **Verified baseline** table whenever you change latency mode or sync offset after a successful test on YouTube.
- Update **Whine on the PIMA → UCA202 feed** when the cable, PIMA output type, or interface path changes.
