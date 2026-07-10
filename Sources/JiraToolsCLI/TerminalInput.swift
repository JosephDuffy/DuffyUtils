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

    func readAction() -> TerminalInputAction? {
        guard isEnabled else {
            return nil
        }

        var byte: UInt8 = 0
        while isInputReady(fileDescriptor) && read(fileDescriptor, &byte, 1) == 1 {
            if byte == CharacterCode.uppercaseR || byte == CharacterCode.lowercaseR {
                return .refresh
            }

            if byte == CharacterCode.uppercaseN || byte == CharacterCode.lowercaseN || byte == CharacterCode.space {
                return .nextPage
            }

            if byte == CharacterCode.uppercaseP || byte == CharacterCode.lowercaseP || byte == CharacterCode.backspace || byte == CharacterCode.controlH {
                return .previousPage
            }

            if byte == CharacterCode.escape {
                return readEscapeSequenceAction()
            }
        }

        return nil
    }

    private func readEscapeSequenceAction() -> TerminalInputAction? {
        var bracket: UInt8 = 0
        guard isInputReady(fileDescriptor), read(fileDescriptor, &bracket, 1) == 1 else {
            return nil
        }

        guard bracket == CharacterCode.leftBracket else {
            return nil
        }

        var code: UInt8 = 0
        guard isInputReady(fileDescriptor), read(fileDescriptor, &code, 1) == 1 else {
            return nil
        }

        switch code {
        case CharacterCode.rightArrow:
            return .nextPage
        case CharacterCode.leftArrow:
            return .previousPage
        default:
            return nil
        }
    }
}

enum TerminalInputAction {
    case refresh
    case nextPage
    case previousPage
}

enum CharacterCode {
    static let uppercaseR = UInt8(ascii: "R")
    static let lowercaseR = UInt8(ascii: "r")
    static let uppercaseN = UInt8(ascii: "N")
    static let lowercaseN = UInt8(ascii: "n")
    static let uppercaseP = UInt8(ascii: "P")
    static let lowercaseP = UInt8(ascii: "p")
    static let space: UInt8 = 32
    static let backspace: UInt8 = 127
    static let controlH: UInt8 = 8
    static let escape: UInt8 = 27
    static let leftBracket = UInt8(ascii: "[")
    static let leftArrow = UInt8(ascii: "D")
    static let rightArrow = UInt8(ascii: "C")
}

func isInputReady(_ fileDescriptor: Int32) -> Bool {
    var input = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
    return poll(&input, 1, 0) > 0 && (input.revents & Int16(POLLIN)) != 0
}

func waitForNextRefresh(
    intervalSeconds: TimeInterval,
    terminalInput: TerminalInput?,
) async throws -> TerminalInputAction {
    guard let terminalInput else {
        try await Task.sleep(for: .seconds(intervalSeconds))
        return .refresh
    }

    let deadline = Date().addingTimeInterval(intervalSeconds)
    while Date() < deadline {
        if let action = terminalInput.readAction() {
            return action
        }

        let remaining = deadline.timeIntervalSinceNow
        let sleepSeconds = min(0.1, max(0, remaining))
        if sleepSeconds > 0 {
            try await Task.sleep(for: .seconds(sleepSeconds))
        }
    }

    return .refresh
}
