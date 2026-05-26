// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  Telephone.swift
//  LXSTSwift
//
//  Main telephony actor matching Python LXST Primitives/Telephony.py.
//  Owns the call STATE MACHINE and SIGNALLING; reaches the network only
//  through `NetworkTransport`. All link lifecycle, encryption, packetization,
//  identify, path resolution, and incoming-link detection live in the host
//  app's transport implementation — no Reticulum types appear here. Peers are
//  `Data` hashes, signals are `Int`, payloads are `Data` (packed by
//  `LXSTWireFormat`). Mirrors LXST-kt's `Telephone` + `NetworkTransport`.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lxst.swift", category: "Telephone")

/// Telephony actor for LXST voice calls.
///
/// Manages the full call lifecycle: incoming/outgoing call setup, signal
/// exchange, and teardown, plus the audio pipeline. The network is abstracted
/// behind `NetworkTransport`, which the host app injects.
public actor Telephone {

    // MARK: - Dependencies

    /// Network transport (host-provided). Owns identity, destination
    /// registration, link lifecycle, encryption, and packetization.
    private let transport: any NetworkTransport

    // MARK: - Call State

    /// Current call state.
    public private(set) var callState: CallState = .idle

    /// Whether a call link is currently active (mirrors the transport's link).
    private var inCall: Bool = false

    /// Whether this is an incoming or outgoing call.
    private var isIncoming: Bool = false

    /// Active telephony profile for the current call.
    private var activeProfile: TelephonyProfile?

    /// Remote peer's identity hash (after identification, or the dialled hash).
    private var remoteIdentityHash: Data?

    // MARK: - Audio Pipeline

    /// Audio processing pipeline for encoding/decoding audio frames.
    private var audioPipeline: AudioPipeline?

    /// Link source for receiving remote audio frames.
    private var linkSource: LinkSource?

    /// Active codec for the current call.
    private var codec: (any AudioCodec)?

    /// Callback for delivering decoded PCM audio to the UI layer.
    private var decodedAudioCallback: (@Sendable ([Float], Int, Int) async -> Void)?

    /// Callback fired when the remote peer's preferred profile is negotiated.
    private var profileNegotiatedCallback: (@Sendable (TelephonyProfile) async -> Void)?

    /// Frame send counter for diagnostics.
    private var sentFrameCount: Int = 0

    /// Frame receive counter for diagnostics.
    private var receivedFrameCount: Int = 0

    // MARK: - Configuration

    /// Caller filtering. Python Telephony.py:123-124
    public var allowed: CallerFilter = .allowAll

    /// Ring timeout duration. Python Telephony.py:115
    public var ringTime: TimeInterval = TelephonyConstants.ringTime

    /// Outgoing call wait timeout. Python Telephony.py:116
    public var waitTime: TimeInterval = TelephonyConstants.waitTime

    /// Connect timeout. Python Telephony.py:117
    public var connectTimeout: TimeInterval = TelephonyConstants.connectTime

    // MARK: - Callbacks

    /// Called when an incoming call starts ringing. Carries the caller's identity hash.
    private var ringingCallback: (@Sendable (Data) async -> Void)?

    /// Called when a call is established. Carries the remote identity hash.
    private var establishedCallback: (@Sendable (Data) async -> Void)?

    /// Called when a call ends. Carries the remote identity hash (if known) + reason.
    private var endedCallback: (@Sendable (Data?, CallEndReason) async -> Void)?

    /// Diagnostic logging callback (set by app layer).
    public var onDiagnostic: (@Sendable (String) -> Void)?

    // MARK: - Timers

    private var ringTimeoutTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?

    /// If true, answer() was called before the Telephone reached .ringing state.
    private var pendingAnswer: Bool = false

    // MARK: - Initialization

    /// Create a new Telephone endpoint over the given transport.
    ///
    /// The transport owns the local identity + telephony-destination
    /// registration; `Telephone` wires its inbound handlers and drives
    /// signalling. Construct via `Telephone.make(transport:)` so handler setup
    /// (which is async) completes before use.
    public init(transport: any NetworkTransport) {
        self.transport = transport
    }

    /// Create and fully wire a Telephone (registers inbound handlers on the
    /// transport). Prefer this over the bare initializer.
    public static func make(transport: any NetworkTransport) async -> Telephone {
        let phone = Telephone(transport: transport)
        await phone.installTransportHandlers()
        return phone
    }

    /// Wire the transport's inbound handlers to this actor. Idempotent.
    public func installTransportHandlers() async {
        await transport.setIncomingCallHandler { [weak self] in
            await self?.handleIncomingCall()
        }
        await transport.setRemoteIdentifiedHandler { [weak self] hash in
            await self?.handleCallerIdentified(hash)
        }
        await transport.setReceiveHandler { [weak self] data in
            await self?.handlePacket(data: data)
        }
        await transport.setClosedHandler { [weak self] reason in
            await self?.handleLinkClosed(reason: reason)
        }
        logger.error("[TELEPHONE] Transport handlers installed")
    }

    // MARK: - Callback Setters

    public func setRingingCallback(_ callback: @escaping @Sendable (Data) async -> Void) {
        self.ringingCallback = callback
    }

    public func setEstablishedCallback(_ callback: @escaping @Sendable (Data) async -> Void) {
        self.establishedCallback = callback
    }

    public func setEndedCallback(_ callback: @escaping @Sendable (Data?, CallEndReason) async -> Void) {
        self.endedCallback = callback
    }

    /// Set callback fired when the remote sends a preferred profile signal.
    public func setProfileNegotiatedCallback(
        _ callback: (@Sendable (TelephonyProfile) async -> Void)?
    ) {
        self.profileNegotiatedCallback = callback
    }

    /// Set callback for receiving decoded PCM audio frames from the remote peer.
    public func setDecodedAudioCallback(
        _ callback: @escaping @Sendable ([Float], Int, Int) async -> Void
    ) {
        self.decodedAudioCallback = callback
    }

    /// Set diagnostic logging callback.
    public func setDiagnostic(_ callback: @escaping @Sendable (String) -> Void) {
        self.onDiagnostic = callback
    }

    // MARK: - Audio Frame Send

    /// Send captured audio samples to the remote peer.
    public func sendAudioFrame(_ samples: [Float]) async {
        guard callState == .established,
              inCall,
              let pipeline = audioPipeline,
              let codec = codec else {
            if sentFrameCount == 0 {
                onDiagnostic?("[TEL] sendAudioFrame DROPPED: state=\(String(describing: callState)), inCall=\(inCall), pipeline=\(audioPipeline != nil), codec=\(codec != nil)")
            }
            return
        }

        sentFrameCount += 1
        if sentFrameCount == 1 || sentFrameCount % 50 == 0 {
            onDiagnostic?("[TEL] TX frame #\(sentFrameCount): \(samples.count) samples")
        }
        await pipeline.processCapture(samples, codec: codec)
    }

    // MARK: - Incoming Call Handling

    /// Handle an incoming call link (transport has accepted the link and wired
    /// its inbound handlers to us). If busy, signal BUSY and tear down;
    /// otherwise signal AVAILABLE and await identification.
    private func handleIncomingCall() async {
        if inCall || callState != .idle {
            logger.error("[TELEPHONE] Incoming call, but line busy — signalling BUSY")
            await sendSignal(.busy)
            await transport.closeCall()
            return
        }

        isIncoming = true
        inCall = true
        transitionState(to: .available)
        await sendSignal(.available)
        logger.error("[TELEPHONE] Sent AVAILABLE to incoming link")
    }

    /// Handle caller identification (transport surfaced the verified caller hash).
    func handleCallerIdentified(_ remoteHash: Data) async {
        guard inCall else { return }

        if !isAllowed(remoteHash) {
            logger.error("[TELEPHONE] Caller not allowed, BUSY")
            await sendSignal(.busy)
            await transport.closeCall()
            resetCallState()
            return
        }

        remoteIdentityHash = remoteHash
        transitionState(to: .ringing)
        await sendSignal(.ringing)
        logger.error("[TELEPHONE] Sent RINGING")

        if pendingAnswer {
            pendingAnswer = false
            logger.error("[TELEPHONE] Pending answer detected, auto-answering")
            await answer()
            return
        }

        await ringingCallback?(remoteHash)
        startRingTimeout()
    }

    // MARK: - Answer / Hangup

    /// Answer an incoming ringing call.
    public func answer() async {
        if callState != .ringing && isIncoming && inCall {
            logger.error("[TELEPHONE] answer() called in state \(String(describing: self.callState)), deferring until .ringing")
            pendingAnswer = true
            return
        }

        guard callState == .ringing, inCall, isIncoming else {
            logger.warning("[TELEPHONE] Cannot answer: state=\(String(describing: self.callState))")
            return
        }

        cancelTimers()
        onDiagnostic?("[TEL] answer(): sending CONNECTING, profile=\(String(describing: activeProfile?.displayName))")
        transitionState(to: .connecting)
        await sendSignal(.connecting)

        await startAudioPipeline()
        onDiagnostic?("[TEL] answer(): pipeline started, linkSource=\(linkSource != nil), codec=\(String(describing: codec?.codecType))")

        transitionState(to: .established)
        await sendSignal(.established)
        onDiagnostic?("[TEL] answer(): sent ESTABLISHED, calling establishedCallback")
        logger.info("[TELEPHONE] Call ESTABLISHED (incoming)")

        if let remote = remoteIdentityHash {
            await establishedCallback?(remote)
            onDiagnostic?("[TEL] answer(): establishedCallback done")
        }
    }

    /// Hang up the active call.
    public func hangup() async {
        guard inCall else { return }
        onDiagnostic?("[TEL] hangup(): callState=\(String(describing: callState)), frames=\(receivedFrameCount)")

        cancelTimers()
        await stopAudioPipeline()

        // If ringing and incoming, send REJECTED before tearing down.
        if isIncoming && callState == .ringing {
            await sendSignal(.rejected)
        }

        await transport.closeCall()

        let reason: CallEndReason = .localHangup
        let remote = remoteIdentityHash
        resetCallState()
        transitionState(to: .ended(reason))
        await endedCallback?(remote, reason)
        transitionState(to: .idle)
    }

    // MARK: - Outgoing Call

    /// Initiate an outgoing call to a peer's telephony destination hash.
    ///
    /// - Parameters:
    ///   - destinationHash: The peer's lxst.telephony destination hash.
    ///   - profile: Preferred telephony profile (default: QUALITY_MEDIUM).
    public func call(destinationHash: Data, profile: TelephonyProfile = .qualityMedium) async throws {
        guard callState == .idle, !inCall else {
            throw LXSTError.alreadyInCall
        }

        isIncoming = false
        activeProfile = profile
        remoteIdentityHash = destinationHash
        transitionState(to: .calling)
        logger.error("[TELEPHONE] call() entered")

        // Transport handles path resolution + link establishment + wiring.
        let opened = await transport.openOutboundCall(to: destinationHash)
        guard opened else {
            logger.error("[TELEPHONE] openOutboundCall failed")
            resetCallState()
            transitionState(to: .ended(.connectTimeout))
            await endedCallback?(destinationHash, .connectTimeout)
            transitionState(to: .idle)
            throw LXSTError.callError("Outbound link establishment failed")
        }
        inCall = true
        logger.error("[TELEPHONE] Outbound link established")

        // Start connect timeout — we now wait for AVAILABLE → identify → RINGING.
        startConnectTimeout()
    }

    // MARK: - Signal Handling

    /// Handle a received (decrypted) LXST payload from the transport.
    private func handlePacket(data: Data) async {
        let first4 = data.prefix(4).map { String(format: "%02x", $0) }.joined()
        if receivedFrameCount == 0 {
            onDiagnostic?("[TEL] handlePacket first: \(data.count) bytes, first4=\(first4)")
        }
        guard let parsed = try? LXSTWireFormat.unpack(data) else {
            onDiagnostic?("[TEL] unpack FAILED: \(data.count) bytes, first4=\(first4)")
            return
        }

        switch parsed {
        case .signals(let signals):
            for signal in signals {
                await handleSignal(signal)
            }
        case .mixed(let signals, _, _):
            for signal in signals {
                await handleSignal(signal)
            }
            await routeAudioFrame(data: data)
        case .frame:
            await routeAudioFrame(data: data)
        }
    }

    /// Route an audio frame payload to the link source for decoding.
    private func routeAudioFrame(data: Data) async {
        receivedFrameCount += 1
        if receivedFrameCount == 1 || receivedFrameCount % 100 == 0 {
            onDiagnostic?("[TEL] audioFrame #\(receivedFrameCount): \(data.count)B, linkSource=\(linkSource != nil)")
        }
        if linkSource == nil {
            guard callState != .idle else {
                logger.error("[TELEPHONE] Dropping stray audio frame received after hangup (callState=idle)")
                return
            }
            logger.error("[TELEPHONE] Auto-starting audio pipeline on first frame (CONNECTING not received)")
            await startAudioPipeline()
            cancelTimers()
            transitionState(to: .established)
            if let remote = remoteIdentityHash {
                await establishedCallback?(remote)
            }
        }
        if let source = linkSource {
            await source.handlePacket(data: data)
        } else {
            logger.error("[TELEPHONE] Received audio frame but linkSource still nil after auto-start!")
        }
    }

    /// Handle a single signal value.
    private func handleSignal(_ signal: UInt) async {
        guard inCall else { return }

        if let profile = LXSTWireFormat.extractPreferredProfile(from: signal) {
            activeProfile = profile
            onDiagnostic?("[TEL] PREFERRED_PROFILE: \(profile.displayName)")
            await profileNegotiatedCallback?(profile)
            return
        }

        guard let signalCode = LXSTWireFormat.extractSignal(from: signal) else { return }

        switch signalCode {
        case .busy:
            onDiagnostic?("[TEL] signal: BUSY")
            cancelTimers()
            let remote = remoteIdentityHash
            await transport.closeCall()
            resetCallState()
            transitionState(to: .ended(.busy))
            await endedCallback?(remote, .busy)
            transitionState(to: .idle)

        case .rejected:
            onDiagnostic?("[TEL] signal: REJECTED")
            cancelTimers()
            let remote = remoteIdentityHash
            await transport.closeCall()
            resetCallState()
            transitionState(to: .ended(.rejected))
            await endedCallback?(remote, .rejected)
            transitionState(to: .idle)

        case .available:
            // Callee is available — identify ourselves over the link.
            logger.error("[TELEPHONE] Remote AVAILABLE, identifying...")
            transitionState(to: .available)
            await transport.identifySelf()

        case .ringing:
            logger.error("[TELEPHONE] Remote is RINGING")
            transitionState(to: .ringing)
            if let profile = activeProfile {
                await sendPreferredProfile(profile)
            }
            if let remote = remoteIdentityHash {
                await ringingCallback?(remote)
            }

        case .connecting:
            logger.error("[TELEPHONE] Remote CONNECTING")
            transitionState(to: .connecting)
            cancelTimers()
            await startAudioPipeline()

        case .established:
            if !isIncoming {
                logger.error("[TELEPHONE] Call ESTABLISHED (outgoing)")
                transitionState(to: .established)
                cancelTimers()
                if let remote = remoteIdentityHash {
                    await establishedCallback?(remote)
                }
            }

        case .calling:
            break
        }
    }

    // MARK: - Signal Sending

    private func sendSignal(_ signal: LXSTSignal) async {
        await send(LXSTWireFormat.packSignal(signal))
    }

    private func sendPreferredProfile(_ profile: TelephonyProfile) async {
        await send(LXSTWireFormat.packPreferredProfile(profile))
    }

    /// Send an LXST-wire payload over the transport (which encrypts + packetizes).
    private var sendDataCount: Int = 0
    private func send(_ data: Data) async {
        sendDataCount += 1
        await transport.send(data)
        if sendDataCount <= 3 || sendDataCount % 50 == 0 {
            onDiagnostic?("[TEL] send #\(sendDataCount): \(data.count)B")
        }
    }

    // MARK: - Link Closed Handler

    /// Handle link closure surfaced by the transport (remote hangup / failure).
    func handleLinkClosed(reason: TransportCloseReason) async {
        guard inCall else { return }
        onDiagnostic?("[TEL] handleLinkClosed: reason=\(reason), callState=\(String(describing: callState)), frames=\(receivedFrameCount)")

        cancelTimers()
        await stopAudioPipeline()
        let remote = remoteIdentityHash
        let endReason: CallEndReason = (reason == .remoteClosed) ? .remoteHangup : .linkClosed
        resetCallState()
        transitionState(to: .ended(endReason))
        await endedCallback?(remote, endReason)
        transitionState(to: .idle)
    }

    // MARK: - Audio Pipeline Management

    private func startAudioPipeline() async {
        let profile = activeProfile ?? .qualityMedium

        let activeCodec: any AudioCodec
        switch profile.codecType {
        case .opus:
            if let opusProfile = profile.opusProfile,
               let opus = try? OpusCodec(profile: opusProfile) {
                activeCodec = opus
                logger.error("[TELEPHONE] Using OpusCodec: \(opusProfile.sampleRate)Hz, \(opusProfile.channels)ch, \(profile.frameTimeMs)ms")
            } else {
                activeCodec = NullCodec()
                logger.error("[TELEPHONE] OpusCodec creation FAILED — falling back to NullCodec")
            }
        case .codec2:
            if let c2Mode = profile.codec2Mode,
               let c2 = try? Codec2Codec(mode: c2Mode) {
                activeCodec = c2
                logger.error("[TELEPHONE] Using Codec2Codec: mode=\(String(describing: c2Mode))")
            } else {
                activeCodec = NullCodec()
                logger.error("[TELEPHONE] Codec2Codec creation FAILED — falling back to NullCodec")
            }
        default:
            activeCodec = NullCodec()
            logger.error("[TELEPHONE] Using NullCodec for profile \(profile.displayName)")
        }
        self.codec = activeCodec

        let pipelineConfig = AudioPipeline.Config(profile: profile)
        let pipeline = AudioPipeline(config: pipelineConfig)
        self.audioPipeline = pipeline

        let source = LinkSource()
        self.linkSource = source

        let codecRef = activeCodec
        await source.setFrameCallback { [weak pipeline] _, audioData in
            guard let pipeline = pipeline else { return }
            await pipeline.processReceived(audioData, codec: codecRef)
        }

        await pipeline.setEncodedFrameCallback { [weak self] codecType, encodedData in
            guard let self = self else { return }
            let packed = LXSTWireFormat.packFrame(codecType: codecType, encodedAudio: encodedData)
            await self.send(packed)
        }

        await pipeline.setDecodedSamplesCallback { [weak self] samples, rate, channels in
            guard let self = self else { return }
            await self.decodedAudioCallback?(samples, rate, channels)
        }

        await pipeline.start(codec: activeCodec)
        await source.start()

        logger.error("[TELEPHONE] Audio pipeline started: codec=\(String(describing: activeCodec.codecType)), profile=\(profile.displayName)")
    }

    private func stopAudioPipeline() async {
        await audioPipeline?.stop()
        await linkSource?.stop()
        audioPipeline = nil
        linkSource = nil
        codec = nil
    }

    // MARK: - State Management

    private func transitionState(to newState: CallState) {
        callState = newState
    }

    private func resetCallState() {
        inCall = false
        remoteIdentityHash = nil
        isIncoming = false
        activeProfile = nil
        pendingAnswer = false
        sentFrameCount = 0
        receivedFrameCount = 0
    }

    // MARK: - Caller Filtering

    private func isAllowed(_ remoteHash: Data) -> Bool {
        switch allowed {
        case .allowAll:
            return true
        case .allowNone:
            return false
        case .allowList(let hashes):
            return hashes.contains(remoteHash)
        }
    }

    // MARK: - Timers

    private func startRingTimeout() {
        ringTimeoutTask?.cancel()
        ringTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.ringTime ?? 60))
            guard !Task.isCancelled else { return }
            await self?.handleRingTimeout()
        }
    }

    private func startConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.waitTime ?? 70))
            guard !Task.isCancelled else { return }
            await self?.handleConnectTimeout()
        }
    }

    private func cancelTimers() {
        ringTimeoutTask?.cancel()
        ringTimeoutTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
    }

    private func handleRingTimeout() async {
        guard callState == .ringing else { return }
        logger.error("[TELEPHONE] Ring timeout")
        let remote = remoteIdentityHash
        await transport.closeCall()
        resetCallState()
        transitionState(to: .ended(.ringTimeout))
        await endedCallback?(remote, .ringTimeout)
        transitionState(to: .idle)
    }

    private func handleConnectTimeout() async {
        guard callState == .calling || callState == .available else { return }
        logger.error("[TELEPHONE] Connect timeout")
        let remote = remoteIdentityHash
        await transport.closeCall()
        resetCallState()
        transitionState(to: .ended(.connectTimeout))
        await endedCallback?(remote, .connectTimeout)
        transitionState(to: .idle)
    }
}

// MARK: - Caller Filter

/// Caller filtering configuration (by identity hash).
public enum CallerFilter: Sendable {
    /// Allow all callers. Python Telephony.py:123
    case allowAll
    /// Allow no callers. Python Telephony.py:124
    case allowNone
    /// Allow only specific identity hashes.
    case allowList([Data])
}
