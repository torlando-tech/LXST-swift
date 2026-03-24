# LXSTSwift

A Swift implementation of LXST (Lightweight Extensible Streaming Transport) for real-time voice calls over [Reticulum](https://reticulum.network) networks.

Copyright (c) 2026 Torlando Tech LLC

## Requirements

- Swift 5.9+
- macOS 13+ / iOS 16+
- [ReticulumSwift](https://github.com/torlando-tech/reticulum-swift)

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/torlando-tech/LXST-swift.git", from: "0.1.0"),
]
```

## Overview

- **Telephone** — Call session management with signaling over Reticulum links
- **Audio** — Capture, playback, jitter buffering, and noise filtering via CoreAudio
- **Codec** — Opus and Codec2 voice encoding compiled from source (no external binary dependencies)

## Acknowledgements
- This work was partially funded by the [Solarkpunk Pioneers Fund](https://solarpunk-pioneers.org)
- [Reticulum](https://reticulum.network), [LXMF](https://github.com/markqvist/LXMF) and [LXST](https://github.com/markqvist/LXST) by Mark Qvist
## License

[MPL-2.0](LICENSE)
