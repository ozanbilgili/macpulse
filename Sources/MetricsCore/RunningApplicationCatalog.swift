import Foundation
import AppKit

@MainActor public enum RunningApplicationCatalog {
    public static func read() -> [ApplicationDescriptor] {
        var result: [String: ApplicationDescriptor] = [:]
        for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
            guard let url = application.bundleURL else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard let root = ProcessGrouping.bundleRoot(path + "/Contents") else { continue }
            if root != path { continue } // Nested helper names must not replace the outer application.
            result[root] = ApplicationDescriptor(name: application.localizedName ?? url.deletingPathExtension().lastPathComponent,
                bundlePath: root, bundleIdentifier: application.bundleIdentifier)
        }
        return Array(result.values)
    }
}
