// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
// LXSTSwift is transport-agnostic: it owns the call state machine, LXST wire
// format, codecs, and audio pipeline, and reaches the network only through the
// `NetworkTransport` protocol (implemented by the host app). It has no
// dependency on any Reticulum stack — the host injects the transport. (Was
// `@_exported import ReticulumSwift`; the RNS coupling now lives entirely
// behind NetworkTransport.)
import Foundation
