import Foundation

public struct FileUpload {
    public var withName: String
    public var fileName: String
    public var mineType: String
    public var path: String
    public var url: URL

    public init(
        withName: String,
        fileName: String,
        mineType: String,
        path: String,
        url: URL = URL(fileURLWithPath: "")
    ) {
        self.withName = withName
        self.fileName = fileName
        self.mineType = mineType
        self.path = path
        self.url = url
    }

    public init(
        withName: String,
        fileName: String,
        mimeType: String,
        path: String,
        url: URL = URL(fileURLWithPath: "")
    ) {
        self.init(withName: withName, fileName: fileName, mineType: mimeType, path: path, url: url)
    }

    public var mimeType: String {
        get { mineType }
        set { mineType = newValue }
    }
}
