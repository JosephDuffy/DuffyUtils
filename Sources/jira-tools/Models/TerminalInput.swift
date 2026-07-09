import Darwin
import Foundation

final class TerminalInput {
    private let fileDescriptor = STDIN_FILENO
    private var originalTermios: termios?
    private var isEnabled = false

    func enableRawMode() {
        guard isatty(fileDescriptor) == 1 else {
            return
        }

        var current = termios()
        guard tcgetattr(fileDescriptor, &current) == 0 else {
            return
        }

        originalTermios = current

        current.c_lflag &= ~tcflag_t(ICANON | ECHO)
        current.c_cc.16 = 0
        current.c_cc.17 = 0

        guard tcsetattr(fileDescriptor, TCSANOW, &current) == 0 else {
            originalTermios = nil
            return
        }

        isEnabled = true
    }

    func restore() {
        guard isEnabled else {
            return
        }

        if var originalTermios {
            _ = tcsetattr(fileDescriptor, TCSANOW, &originalTermios)
        }

        isEnabled = false
    }

    func readRefreshKey() -> Bool {
        guard isEnabled else {
            return false
        }

        var byte: UInt8 = 0
        while isInputReady(fileDescriptor) && read(fileDescriptor, &byte, 1) == 1 {
            if byte == CharacterCode.uppercaseR || byte == CharacterCode.lowercaseR {
                return true
            }
        }

        return false
    }
}

enum CharacterCode {
    static let uppercaseR = UInt8(ascii: "R")
    static let lowercaseR = UInt8(ascii: "r")
}

func isInputReady(_ fileDescriptor: Int32) -> Bool {
    var input = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
    return poll(&input, 1, 0) > 0 && (input.revents & Int16(POLLIN)) != 0
}

func waitForNextRefresh(
    intervalSeconds: TimeInterval,
    terminalInput: TerminalInput?,
) async throws {
    guard let terminalInput else {
        try await Task.sleep(for: .seconds(intervalSeconds))
        return
    }

    let deadline = Date().addingTimeInterval(intervalSeconds)
    while Date() < deadline {
        if terminalInput.readRefreshKey() {
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        let sleepSeconds = min(0.1, max(0, remaining))
        if sleepSeconds > 0 {
            try await Task.sleep(for: .seconds(sleepSeconds))
        }
    }
}
