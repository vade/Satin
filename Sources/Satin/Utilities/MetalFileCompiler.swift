//
//  MetalLibraryCompiler.swift
//  Satin
//
//  Created by Reza Ali on 8/6/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Foundation

public enum MetalFileCompilerError: Error {
    case invalidFile(_ fileURL: URL)
}

extension MetalFileCompilerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidFile(fileURL):
            return NSLocalizedString("MetalFileCompiler did not find: \(fileURL.path)\n\n\n", comment: "MetalFileCompiler Error")
        }
    }
}

public class MetalFileCompiler {
    public var watch: Bool {
        didSet {
            if watch != oldValue {
                for watcher in watchers {
                    if watch {
                        watcher.watch()
                    } else {
                        watcher.unwatch()
                    }
                }
            }
        }
    }

    public var onUpdate: (() -> Void)?

    private var files: [URL] = []
    private var watchers: [FileWatcher] = []

    public init(watch: Bool = true) {
        self.watch = watch
    }

    public func touch() {
        onUpdate?()
    }

    public func parse(_ fileURL: URL) throws -> String {
        files = []
        watchers = []
        return try _parse(fileURL)
    }

    private func _parse(_ fileURL: URL) throws -> String {
        var fileURLResolved = fileURL.resolvingSymlinksInPath()

        if !files.contains(fileURLResolved) {
            let baseURL = fileURL.deletingLastPathComponent()
            var content = ""
            do {
                content = try String(contentsOf: fileURLResolved, encoding: .utf8)
            } catch {
                let pathComponents = fileURLResolved.pathComponents
                if let index = pathComponents.lastIndex(of: "Satin"), var frameworkFileURL = getPipelinesSatinURL()
                {
                    for i in (index + 1) ..< pathComponents.count {
                        frameworkFileURL.appendPathComponent(pathComponents[i])
                    }

                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                } else if let index = pathComponents.lastIndex(of: "Chunks"), var frameworkFileURL = getPipelinesChunksURL()
                {
                    for i in (index + 1) ..< pathComponents.count {
                        frameworkFileURL.appendPathComponent(pathComponents[i])
                    }

                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                } else if let index = pathComponents.lastIndex(of: "Library"), var frameworkFileURL = getPipelinesLibraryURL()
                {
                    for i in (index + 1) ..< pathComponents.count {
                        frameworkFileURL.appendPathComponent(pathComponents[i])
                    }

                    content = try String(contentsOf: frameworkFileURL, encoding: .utf8)
                    fileURLResolved = frameworkFileURL
                } else {
                    throw MetalFileCompilerError.invalidFile(fileURLResolved)
                }
            }

            let watcher = FileWatcher(filePath: fileURLResolved.path, timeInterval: 0.25, active: watch) { [weak self] in
                self?.onUpdate?()
            }
            watchers.append(watcher)
            files.append(fileURLResolved)

            let pattern = #"^#include\s+\"(.*)\"\n"#
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            let nsrange = NSRange(content.startIndex ..< content.endIndex, in: content)
            var matches = regex.matches(in: content, options: [], range: nsrange)
            while !matches.isEmpty {
                let match = matches[0]
                if match.numberOfRanges == 2,
                   let r0 = Range(match.range(at: 0), in: content),
                   let r1 = Range(match.range(at: 1), in: content)
                {
                    let includeURL = URL(fileURLWithPath: String(content[r1]), relativeTo: baseURL)
                    do {
                        let includeContent = try _parse(includeURL)
                        content.replaceSubrange(r0, with: includeContent + "\n")
                    } catch {
                        throw MetalFileCompilerError.invalidFile(includeURL)
                    }
                }
                let nsrange = NSRange(content.startIndex ..< content.endIndex, in: content)
                matches = regex.matches(in: content, options: [], range: nsrange)
            }

            return content
        }

        return ""
    }

    deinit {
        onUpdate = nil
        files = []
        watchers = []
    }
}
