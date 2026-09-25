import ArgumentParser
import Foundation

@main
struct OWCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "owctl",
        abstract: "OpenWallpaperMac developer tool: inspect, convert, validate, render and benchmark wallpapers.",
        subcommands: [
            InspectCommand.self, ExtractCommand.self, TexToPNGCommand.self, ValidateCommand.self,
            RenderCommand.self, BenchCommand.self, MakeSampleCommand.self,
        ]
    )
}

struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
