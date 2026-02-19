//
//  LXSTErrors.swift
//  LXSTSwift
//
//  Error types for LXST protocol operations.
//

import Foundation

public enum LXSTError: Error, Sendable {
    case invalidWireFormat(String)
    case codecError(String)
    case callError(String)
    case notConnected
    case alreadyInCall
    case linkNotActive
    case identityRequired
    case callRejected
    case callBusy
    case ringTimeout
    case connectTimeout
}
