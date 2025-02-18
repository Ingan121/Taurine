//
//  bootstrap.swift
//  Taurine
//
//  Created by CoolStar on 5/13/20.
//  Copyright © 2020 coolstar. All rights reserved.
//

import Foundation
import SwiftZSTD

func untarBasebins() -> Bool {
    guard let baseBinLocation = Bundle.main.path(forResource: "basebinaries", ofType: "tar") else {
        return false
    }
    
    let args = ["tar", "-xpf", baseBinLocation, "-C", "/taurine"]
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    var pid = pid_t(0)
    var status = posix_spawn(&pid, "/taurine/tar", nil, nil, argv + [nil], environ)
    if status == 0 {
        if waitpid(pid, &status, 0) == -1 {
            perror("waitpid")
        }
    } else {
        print("posix_spawn:", status)
    }
    return status == 0
}

func untarBootstrap() -> Bool {
    let args = ["tar", "--preserve-permissions", "-xkf", "/taurine/bootstrap.tar", "-C", "/"]
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    var pid = pid_t(0)
    var status = posix_spawn(&pid, "/taurine/tar", nil, nil, argv + [nil], environ)
    if status == 0 {
        if waitpid(pid, &status, 0) == -1 {
            perror("waitpid")
        }
    } else {
        print("posix_spawn:", status)
    }
    return status == 0
}

func extractZstd(source: String, dest: String) -> Bool {
    var retVal = false
    autoreleasepool {
        let processor = ZSTDProcessor(useContext: true)
        guard let bootstrapURL = Bundle.main.url(forResource: source, withExtension: "gz"),
            let bootstrapData = try? Data(contentsOf: bootstrapURL) else {
            return
        }
        let decompressedBootstrap = try? processor.decompressFrame(bootstrapData)
        let tempURL = URL(fileURLWithPath: dest)
        do {
            try decompressedBootstrap?.write(to: tempURL)
        } catch {
            return
        }
        retVal = true
    }
    return retVal
}

func installDebs(debs: [String]) -> Bool {
    var debsList = ""
    for deb in debs {
        guard let debPath = Bundle.main.path(forResource: deb, ofType: "deb") else {
            return false
        }
        if !debsList.isEmpty {
            debsList += " "
        }
        debsList += debPath
    }
    return runUnsandboxed(cmd: "apt install -fy " + debsList) == 0
}

func bootstrapDevice() -> Bool {
    if FileManager.default.fileExists(atPath: "/.installed_odyssey") {
        guard (try? "".write(toFile: "/.installed_taurine", atomically: false, encoding: .utf8)) != nil else {
            return false
        }
        try? FileManager.default.removeItem(atPath: "/.installed_odyssey")
    }
    if FileManager.default.fileExists(atPath: "/.installed_taurine") {
        guard postBootstrap() else {
            return false
        }
        guard ensurePackageManager() else {
            return false
        }
        return true
    }
    
    print("Installing Sileo")
    
    if ( FileManager.default.fileExists(atPath: "/.installed_unc0ver") ||
    FileManager.default.fileExists(atPath: "/.bootstrapped") ) &&
    FileManager.default.fileExists(atPath: "/usr/bin/apt-get") {
        print("Migration Unsupported")
        print("Migrating from other jailbreaks is not supported. Please rootfs restore.")
        return false
    } else {
        guard extractZstd(source: "bootstrap.tar", dest: "/taurine/bootstrap.tar") else {
            return false
        }
        guard untarBootstrap() else {
            return false
        }
        unlink("/taurine/bootstrap.tar")
    }
    
    let debs = [
        "org.coolstar.sileo_2.3_iphoneos-arm"
    ]
    
    guard runUnsandboxed(cmd: "/prep_bootstrap.sh") == 0,
        installDebs(debs: debs),
        runUnsandboxed(cmd: "uicache -p /Applications/Sileo.app") == 0 else {
            return false
    }
    
    guard (try? "".write(toFile: "/.installed_taurine", atomically: false, encoding: .utf8)) != nil else {
        return false
    }
    
    print("Installed Sileo")
    
    guard postBootstrap() else {
        return false
    }

    let systemAptGetArgs = [
        "-oAPT::Get::AllowUnauthenticated=true",
        "-oAcquire::AllowDowngradeToInsecureRepositories=true",
        "-oAcquire::AllowInsecureRepositories=true"]
    let systemAptGet = "/usr/bin/apt-get " + systemAptGetArgs.joined(separator: " ")
    _ = runUnsandboxed(cmd: "\(systemAptGet) update")

    return true
}

func postBootstrap() -> Bool {
    let taurinePrefs = """
        Package: *
        Pin: release o="Odyssey Repo"
        Pin-Priority: 1001
        
        """
    
    let taurineSources = """
        Types: deb
        URIs: https://repo.theodyssey.dev/
        Suites: ./
        Components:
        
        """
    
    let procursusSources = """
        Types: deb
        URIs: https://apt.procurs.us/
        Suites: iphoneos-arm64/1700
        Components: main
        
        """
    
    guard (try? taurinePrefs.write(toFile: "/private/etc/apt/preferences.d/taurine", atomically: false, encoding: .utf8)) != nil,
          (try? taurineSources.write(toFile: "/private/etc/apt/sources.list.d/taurine.sources", atomically: false, encoding: .utf8)) != nil,
          (try? procursusSources.write(toFile: "/private/etc/apt/sources.list.d/procursus.sources", atomically: false, encoding: .utf8)) != nil else {
        return false
    }
    return true
}

func ensurePackageManager() -> Bool {
    let debs = [
        "essential_0-4_iphoneos-arm",
        "org.coolstar.sileo_2.3_iphoneos-arm"
    ]
    if runUnsandboxed(cmd: "/usr/bin/dpkg-query -W -f='${Status}' essential") != 0 {
        guard installDebs(debs: debs) else {
            return false
        }
    }
    return true
}

func startDaemons() {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/Library/LaunchDaemons/") else {
        return
    }
    for file in files {
        let fullURL = URL(fileURLWithPath: "/Library/LaunchDaemons/").appendingPathComponent(file)
        if runUnsandboxed(cmd: "launchctl load " + fullURL.path) != 0 {
            print("[launchd] Unable to load daemon", file)
        }
    }
}
