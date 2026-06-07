import Foundation

public struct DownloadConfig {
    public var directory: FileManager.SearchPathDirectory
    public var domain: FileManager.SearchPathDomainMask
    public var options: [DownloadOption]

    public init(
        directory: FileManager.SearchPathDirectory = .documentDirectory,
        domain: FileManager.SearchPathDomainMask = .userDomainMask,
        options: [DownloadOption] = [.createIntermediateDirectories, .removePreviousFile]
    ) {
        self.directory = directory
        self.domain = domain
        self.options = options
    }
}

public enum DownloadOption {
    case createIntermediateDirectories
    case removePreviousFile
}
