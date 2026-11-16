//
//  SwiftyTubeLog.swift
//  SwiftyTube
//
//  Created by 686udjie on 03/10/2026.
//

import Foundation
import os

/// Library logging. Set `handler` to capture, else os.Logger (subsystem "SwiftyTube").
public enum SwiftyTubeLog: Sendable {
    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var storedHandler: (@Sendable (String, Level) -> Void)?

    public static var handler: (@Sendable (String, Level) -> Void)? {
        get {
            handlerLock.lock(); defer { handlerLock.unlock() }
            return storedHandler
        }
        set {
            handlerLock.lock(); defer { handlerLock.unlock() }
            storedHandler = newValue
        }
    }

    public enum Level: String, Sendable {
        case debug
        case info
        case notice
        case error
    }

    private static let logger = Logger(subsystem: "SwiftyTube", category: "InnerTube")

    public static func debug(_ message: String) {
        emit(message, level: .debug)
    }

    public static func info(_ message: String) {
        emit(message, level: .info)
    }

    public static func notice(_ message: String) {
        emit(message, level: .notice)
    }

    public static func error(_ message: String) {
        emit(message, level: .error)
    }

    private static func emit(_ message: String, level: Level) {
        if let handler {
            handler(message, level)
            return
        }
        switch level {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .notice:
            logger.notice("\(message)")
        case .error:
            logger.error("\(message)")
        }
    }
}
