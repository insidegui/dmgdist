//
//  main.swift
//  dmgdist
//
//  Created by Gui Rambo on 08/10/20.
//

import Cocoa
import ArgumentParser
import ShellOut
import Darwin

private var statusCheckTimer: Timer?
var bundleId: String!

struct DMGDist: ParsableCommand {
    
    static let maxOutputDMGFilenameLength = 27

    struct Failure: LocalizedError {
        var errorDescription: String?
        
        init(_ description: String) {
            self.errorDescription = description
        }
    }

    @Flag(help: "Verbose output")
    var verbose = false
    
    @Flag(inversion: .prefixedNo, help: "Enable/disable using the modern notarytool for submission instead of the legacy altool")
    var useNotaryTool = true

    @Option(help: "A notarization request id. If provided, the script will skip creating the DMG and uploading it for notarization and just keep checking for the notarization status.")
    var checkRequestId: String?

    @Argument(help: "Path to the developer ID signed .app (doesn't have to be notarized)")
    var appFilePath: String

    @Argument(help: "Your code signing identity, such as \"Developer ID Application: John Doe (XXXX123YY)\"")
    var identity: String

    @Argument(help: "Your App Store Connect provider ID (same as your developer's team ID)")
    var ascProvider: String

    @Argument(help: "Your App Store Connect e-mail")
    var ascEmail: String

    @Argument(help: "Your App Store Connect app-specific password, or the identifier for a keychain item in the format @keychain:ITEMNAME")
    var ascPassword: String
    
    @Option(name: .long, help: "Custom name for the output DMG file (max \(Self.maxOutputDMGFilenameLength) characters)")
    var dmgName: String?

    /// Uses `create-dmg` to prepare a temporary DMG with the app, returns the URL of the DMG.
    func prepareDMG() throws -> URL {
        let appFileURL = URL(fileURLWithPath: appFilePath)
        
        let appName = appFileURL.deletingPathExtension().lastPathComponent
        let sanitizedAppName = appName.replacingOccurrences(of: " ", with: "")
        
        if appName.contains(" ") {
            fputs("WARNING: The app file name contains spaces, they will be removed in the output file.\n", stderr)
        }

        guard FileManager.default.fileExists(atPath: appFileURL.path) else {
            throw Failure("The input app doesn't exist at \(appFileURL.path)")
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DMGDist-" + sanitizedAppName + "-\(Date().timeIntervalSince1970)")

        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        }

        guard let appBundle = Bundle(url: appFileURL) else {
            throw Failure("Failed to construct app bundle")
        }

        guard let shortVersionString = appBundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw Failure("Failed to read CFBundleShortVersionString from app's Info.plist")
        }

        guard let bundleVersion = appBundle.infoDictionary?["CFBundleVersion"] as? String else {
            throw Failure("Failed to read CFBundleVersion from app's Info.plist")
        }

        guard let identifier = appBundle.bundleIdentifier else {
            throw Failure("Couldn't get app bundle identifier")
        }

        bundleId = identifier

        let outputDMGName = dmgName ?? "\(sanitizedAppName)_v\(shortVersionString)-\(bundleVersion)"
        
        guard outputDMGName.count < Self.maxOutputDMGFilenameLength else {
            throw Failure("The output DMG file name \"\(outputDMGName)\" exceeds the maximum character limit of \(Self.maxOutputDMGFilenameLength).\nPlease specify a shorter custom name with the --dmg-name option.")
        }

        if verbose {
            print("Primary bundle ID is \(identifier)")
            print("Output DMG will be named \(outputDMGName)")
            print("Using temporary directory \(tempDir.path)")
        }

        try shellOut(to: "create-dmg", arguments: ["--identity=\"\(identity)\"", "--overwrite", "--dmg-title=\"\(outputDMGName)\"", "\"\(appFilePath)\"", tempDir.path])

        if verbose {
            print("Renaming output DMG")
        }

        guard let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) else {
            throw Failure("Failed to read output directory")
        }

        guard let originalDMGURL = enumerator.allObjects.compactMap({ $0 as? URL }).first(where: { $0.pathExtension.lowercased() == "dmg" }) else {
            throw Failure("Couldn't find output DMG in temporary directory")
        }

        let outputDMGURL = tempDir
            .appendingPathComponent(outputDMGName)
            .appendingPathExtension("dmg")

        try FileManager.default.moveItem(at: originalDMGURL, to: outputDMGURL)

        return outputDMGURL
    }

    /// Calls `altool` to notarize the DMG and returns the request ID.
    private func requestNotarizationWithLegacyTool(for dmgURL: URL) throws -> String {
        if verbose {
            print("Uploading for notarization")
        }

        let output = try shellOut(
            to: "xcrun",
            arguments: [
                "altool",
                "--notarize-app",
                "--primary-bundle-id", bundleId,
                "-f", dmgURL.path,
                "-u", "\"\(ascEmail)\"",
                "-p", "\"\(ascPassword)\"",
                "--asc-provider", ascProvider,
                "--output-format", "json"
            ]
        )

        if verbose {
            print("altool output:")
            print(output)
        }

        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(NotarizationResponse.self, from: data)

        return response.upload.requestUUID
    }
 
    private func fetchNotarizationStatus(for id: String) throws -> NotarizationStatusResponse {
        let output = try shellOut(
            to: "xcrun",
            arguments: [
                "altool",
                "--notarization-info", "\"\(id)\"",
                "-u", "\"\(ascEmail)\"",
                "-p", "\"\(ascPassword)\"",
                "--asc-provider", ascProvider,
                "--output-format", "json"
            ]
        )

        if verbose {
            print("altool output:")
            print(output)
        }

        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(NotarizationStatusResponse.self, from: data)

        return response
    }

    private func waitForRequestToBeFulfilled(_ id: String, completion: @escaping (Bool) -> Void) {
        func check(_ timer: Timer?) {
            do {
                let response = try fetchNotarizationStatus(for: id)

                if response.isDone {
                    timer?.invalidate()
                    statusCheckTimer = nil

                    print("Notarization done")

                    completion(true)

                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
            } catch {
                print("Error checking for notarization status: \(error)")
            }
        }

        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { timer in
            check(timer)
        })

        check(nil)

        CFRunLoopRun()
    }

    private func stapleDMG(at dmgURL: URL) throws {
        if verbose { print("📝 Stapling…") }
        
        var args = ["stapler", "staple"]
        
        if verbose { args.append("-v") }
        
        args.append(dmgURL.path)
        
        let output = try shellOut(to: "xcrun", arguments: args)
        
        if verbose {
            print("stapler output:")
            print(output)
        }

        print("Ready for distribution 🎉")

        NSWorkspace.shared.selectFile(dmgURL.path, inFileViewerRootedAtPath: dmgURL.deletingLastPathComponent().path)
    }

    func run() throws {
        if let requestId = checkRequestId {
            print("Checking status of request \(requestId)")

            waitForRequestToBeFulfilled(requestId) { success in
                print("Request \(requestId) fulfilled with success = \(success)")
                Self.exit(withError: nil)
            }
            return
        }

        let dmgURL = try prepareDMG()
        
        if useNotaryTool {
            if verbose {
                print("Running notarytool")
            }
            
            // xcrun notarytool submit Package.dmg --keychain-profile "NOTARYTOOLRAMBO" --wait
            try shellOut(
                to: "xcrun",
                arguments: [
                    "notarytool",
                    "submit", "\"\(dmgURL.path)\"",
                    "--keychain-profile", "\"\(ascPassword)\"",
                    "--wait"
                ]
            )
            
            try stapleDMG(at: dmgURL)
        } else {
            let requestId = try requestNotarizationWithLegacyTool(for: dmgURL)
            
            if verbose {
                print("Notarization request ID: \(requestId)")
            }
            
            waitForRequestToBeFulfilled(requestId) { success in
                guard success else {
                    Self.exit(withError: Failure("Notarization failed"))
                }
                
                try! stapleDMG(at: dmgURL)
            }
        }
    }

}

DMGDist.main()
