import ArgumentParser

enum CLIError: Error, Equatable {
    case invalidDeviceURL(String)
    case connectionClosed
    case inputReadFailed
    case invalidCommand
    case unmatchedQuote
    case fileOpenError
}

struct RoamCLIGlobalOptions: ParsableArguments {
    @Option(help: "The IP address or hostname to connect to")
    public var device: String

    @Option(help: "An output file to write instead of stdout")
    public var outFile: String?
}

@main
struct RoamCLI: AsyncParsableCommand {
    @OptionGroup var globals: RoamCLIGlobalOptions

    static let configuration = CommandConfiguration(
        abstract: "Execute a single command via the ECP API",
        subcommands: [Execute.self, Shell.self],
        defaultSubcommand: Shell.self
    )
}

struct Execute: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a single command via the ECP API",
        subcommands: [
            Exit.self, RequestEvents.self, PressKey.self,
            LaunchApp.self, ListApps.self, JsonCommand.self,
            VoiceService.self
        ],
        defaultSubcommand: Exit.self
    )
}

struct Shell: AsyncParsableCommand {
    @OptionGroup var globals: RoamCLIGlobalOptions

    @Option(help: "An input file to read commands from instead of stdout")
    public var inFile: String?

    static let configuration = CommandConfiguration(
        abstract: "Execute a series of commands via the ECP API"
    )

    public func run() async throws {
        guard let deviceURL = URL(string: self.globals.device) else {
            throw CLIError.invalidDeviceURL(self.globals.device)
        }
        let stdOutHandle = FileHandle.standardOutput
        let ecpWebsocketClient = ECPWebsocketClient(location: deviceURL, websocketStateUpdated: { state in
            stdOutHandle.write("> State Changed: \(state.debugDescription)\n")
            switch state {
            case .connected:
                stdOutHandle.write("> Connected\n")
            case .connecting:
                stdOutHandle.write("> Connecting...\n")
            case .disconnected:
                stdOutHandle.write("> Disconnected\n")
                stdOutHandle.write("> Exiting...\n")
                Self.exit(withError: CLIError.connectionClosed)
            }
        }, notificationHandler: { notification in
            stdOutHandle.write("> Notification: \(notification.notifyType)\n")
        })

        await ecpWebsocketClient.start()
        let inHandle: FileHandle
        if let filePath = self.inFile {
            if let fileHandle = FileHandle(forReadingAtPath: filePath) {
                inHandle = fileHandle
            } else {
                throw CLIError.fileOpenError
            }
        } else {
            inHandle = FileHandle.standardInput
        }
        var parsingLine: String = ""
        do {
            for try await line in inHandle.bytes.lines {
                let command: any ParsableCommand
                do {
                    parsingLine += line
                    if line.hasSuffix("\\") {
                        continue
                    }
                    var args = try splitArguments(parsingLine)
                    args.append("--device")
                    args.append(self.globals.device)
                    print("Got args \(args)\n")
                    command = try Execute.parseAsRoot(args)
                    parsingLine = ""
                } catch {
                    stdOutHandle.write("> Failed to parse command\n")

                    self.printHelp()
                    parsingLine = ""
                    continue
                }
                if let asyncCommand = command as? any ECPCommand {
                    do {
                        try await asyncCommand.runEcp(ecpWebsocketClient)
                    } catch {
                        print("> Comman failed\n\(error)")
                        self.printHelp()
                    }
                } else {
                    print("> Unknown command")
                    self.printHelp()
                }
            }
        } catch {
            throw CLIError.inputReadFailed
        }
    }

    func printHelp() {
        let stdOutHandle = FileHandle.standardOutput

        var helpText = Execute.helpMessage()
        if let range = helpText.range(of: "SUBCOMMANDS:\\s*\\n", options: .regularExpression) {
            helpText = String(helpText[range.upperBound...])
        }
        if let range = helpText.range(of: "\\s*See 'execute help <subcommand>'", options: .regularExpression) {
            helpText = String(helpText[...range.lowerBound])
        }
        stdOutHandle.write("> Options: \n\(helpText)\n")
    }
}

protocol ECPCommand {
    func runEcp(_ websocket: ECPWebsocketClient) async throws
}

extension Execute {
    struct Exit: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Exits the shell")
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            print("> Exiting immediately")
            Self.exit()
        }

        public func runEcp(_: ECPWebsocketClient) async throws {
            try await self.run()
        }
    }

    struct RequestEvents: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Requests notification events")

        @Argument(help: "Events to request...")
        public var events: [String]
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })
            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            let events = self.events.map{"+\($0)"}.joined(separator: ",")
            try await websocket.requestEventsNotify(events: events)
        }
    }

    struct PressKey: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Presses a key")

        @Argument(help: "Which key to press")
        public var key: RemoteButton
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })

            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            try await websocket.pressButton(self.key)
        }
    }

    struct LaunchApp: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Opens an app")

        @Argument(help: "Which app to launch")
        public var app: String
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })

            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            try await websocket.launchApp(self.app)
        }
    }

    struct ListApps: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "List apps")
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })

            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            let result = try await websocket.getDeviceApps()
            let apps = result.map{
                ($0.name, $0.id)
            }
            print("> \(apps)")
        }
    }

    struct VoiceService: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Execute voice service command")
        @Argument(help: "Which voice service command to run")
        public var command: String

        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })

            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            do {
                let result = try await websocket.sendCommand(
                    ECPRequestMessage.requestVoiceService(
                        VoiceServiceRequest(events: self.command, requestId: "")
                    )
                )
                switch result {
                case .base(let response):
                    print("> Voice service succeeded with \(response.status)")
                    let responseData = response.contentData ?? Data()
                    let responseString = String(data: responseData, encoding: .utf8)
                    print("\(responseString ?? "")")
                }
            } catch {
                print("> Json request failed\n\(error)\n")
            }
        }
    }

    struct JsonCommand: AsyncParsableCommand, ECPCommand {
        static let configuration = CommandConfiguration(abstract: "Execute json command")

        @Argument(help: "Command to execute")
        public var command: String
        @OptionGroup var globals: RoamCLIGlobalOptions

        public func run() async throws {
            let websocket = try await startWebsocket(self.globals.device, exit: { error in
                if let error {
                    Self.exit(withError: error)
                } else {
                    Self.exit()
                }
            })

            try await self.runEcp(websocket)
        }

        public func runEcp(_ websocket: ECPWebsocketClient) async throws {
            let parsedCommand: CustomRequest
            do {
                let command = self.command
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = kebabParamDecodingStrategy()
                parsedCommand = try decoder.decode(CustomRequest.self, from: Data(command.utf8))
            } catch {
                print("> Invalid JSON command\n\(error)\n")
                Self.exit(withError: CLIError.invalidCommand)
            }

            do {
                let result = try await websocket.sendCommand(ECPRequestMessage.custom(parsedCommand))
                switch result {
                case .base(let response):
                    print("> Json request succeeded with \(response.status)")
                    let responseData = response.contentData ?? Data()
                    let responseString = String(data: responseData, encoding: .utf8)
                    print("\(responseString ?? "")")
                }
            } catch {
                print("> Json request failed\n\(error)\n")
            }
        }
    }
}

extension FileHandle: @retroactive TextOutputStream {
  public func write(_ string: String) {
    let data = Data(string.utf8)
    self.write(data)
  }
}

extension RemoteButton: ExpressibleByArgument { }

class ArgumentLexer {
    private enum State {
        case normal
        case inSingleQuote
        case inDoubleQuote
        case escaped
    }

    private var state: State = .normal
    private var buffer: String = ""
    private var arguments: [String] = []

    func parse(_ string: String) throws -> [String] {
        for char in string {
            switch state {
            case .normal:
                handleNormal(char)
            case .inSingleQuote:
                try handleInSingleQuote(char)
            case .inDoubleQuote:
                try handleInDoubleQuote(char)
            case .escaped:
                handleEscaped(char)
            }
        }
        try finalize()
        return arguments
    }

    private func handleNormal(_ char: Character) {
        switch char {
        case " ":
            if !buffer.isEmpty {
                arguments.append(buffer)
                buffer = ""
            }
        case "\"":
            state = .inDoubleQuote
        case "'":
            state = .inSingleQuote
        case "\\":
            state = .escaped
        default:
            buffer.append(char)
        }
    }

    private func handleInSingleQuote(_ char: Character) throws {
        if char == "'" {
            state = .normal
        } else {
            buffer.append(char)
        }
    }

    private func handleInDoubleQuote(_ char: Character) throws {
        switch char {
        case "\"":
            state = .normal
        case "\\":
            state = .escaped
        default:
            buffer.append(char)
        }
    }

    private func handleEscaped(_ char: Character) {
        buffer.append(char)
        state = .normal
    }

    private func finalize() throws {
        if state == .inSingleQuote || state == .inDoubleQuote {
            throw CLIError.unmatchedQuote
        }
        if !buffer.isEmpty {
            arguments.append(buffer)
        }
    }
}

func splitArguments(_ string: String) throws -> [String] {
    let lexer = ArgumentLexer()
    return try lexer.parse(string)
}

func startWebsocket(_ device: String, exit: (@escaping @Sendable ((any Error)?) -> Void)) async throws -> ECPWebsocketClient {
    guard let deviceURL = URL(string: device) else {
        throw CLIError.invalidDeviceURL(device)
    }
    let stdOutHandle = FileHandle.standardOutput
    let ecpWebsocketClient = ECPWebsocketClient(location: deviceURL, websocketStateUpdated: { state in
        stdOutHandle.write("> State Changed: \(state.debugDescription)\n")
        switch state {
        case .connected:
            stdOutHandle.write("> Connected\n")
        case .connecting:
            stdOutHandle.write("> Connecting...\n")
        case .disconnected:
            stdOutHandle.write("> Disconnected\n")
            stdOutHandle.write("> Exiting...\n")
            exit(CLIError.connectionClosed)
        }
    }, notificationHandler: { notification in
        stdOutHandle.write("> Notification: \(notification.notifyType)\n")
    })

    await ecpWebsocketClient.start()

    return ecpWebsocketClient
}
