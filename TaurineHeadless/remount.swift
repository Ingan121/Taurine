//
//  remount.swift
//  Taurine
//
//  Created by CoolStar on 3/1/20.
//  Copyright © 2020 coolstar. All rights reserved.
//

import Foundation

class Remount {
    let electra: Electra
    let our_proc: UInt64
    let kernel_proc: UInt64
    
    init(electra: Electra, kernel_proc: UInt64) {
        self.electra = electra
        self.our_proc = electra.our_proc
        self.kernel_proc = kernel_proc
    }
    
    private let offsets = Offsets.shared
    
    let mntpathSW = "/var/MobileSoftwareUpdate/rootfsmnt"
    let mntpath = strdup("/var/MobileSoftwareUpdate/rootfsmnt")
    
    private func findRootVnode(launchd_proc: UInt64) -> UInt64 {
        let textvp = rk64ptr(launchd_proc + offsets.proc.textvp)
        var nameptr = rk64(textvp + offsets.vnode.name)
        var name = [UInt8](repeating: 0, count: 20)
        kread(nameptr, &name, 20)
        
        #if DEBUG
        print("found vnode: ", String(cString: &name))
        #endif
        
        let sbin = rk64ptr(textvp + offsets.vnode.parent)
        nameptr = rk64(sbin + offsets.vnode.name)
        kread(nameptr, &name, 20)
        
        #if DEBUG
        print("found vnode (should be sbin): ", String(cString: &name))
        #endif
        
        let rootvnode = rk64ptr(sbin + offsets.vnode.parent)
        nameptr = rk64(rootvnode + offsets.vnode.name)
        kread(nameptr, &name, 20)
        
        #if DEBUG
        print("found vnode (should be root): ", String(cString: &name))
        #endif
        
        let flags = rk32(rootvnode + offsets.vnode.flag)
        #if DEBUG
        print(String(format: "vnode flags: 0x%x", flags))
        #endif
        
        return rootvnode
    }
    
    private func isOTAMounted() -> Bool {
        let path = strdup("/var/MobileSoftwareUpdate/mnt1")
        defer {
            free(path)
        }
        
        var buffer = stat()
        if lstat(path, &buffer) != 0 {
            return false
        }
        
        let S_IFMT = 0o170000
        let S_IFDIR = 0o040000
        
        guard Int(buffer.st_mode) & S_IFMT == S_IFDIR else {
            return false
        }
        
        let cwd = getcwd(nil, 0)
        chdir(path)
        
        var p_buf = stat()
        lstat("..", &p_buf)
        
        if let cwd = cwd {
            chdir(cwd)
            free(cwd)
        }
        
        return buffer.st_dev != p_buf.st_dev || buffer.st_ino == p_buf.st_ino
    }
    
    private func isRenameRequired() -> Bool {
        var statfsptr: UnsafeMutablePointer<statfs>?
        let mntsize = getmntinfo(&statfsptr, MNT_NOWAIT)
        guard mntsize != 0 else {
            fatalError("Unable to get mount info")
        }
        for _ in 0..<mntsize {
            if var statfs = statfsptr?.pointee {
                let on = withUnsafePointer(to: &statfs.f_mntonname.0){
                    $0.withMemoryRebound(to: UInt8.self, capacity: Int(MAXPATHLEN)){
                        String(cString: $0)
                    }
                }
                let from = withUnsafePointer(to: &statfs.f_mntfromname.0){
                    $0.withMemoryRebound(to: UInt8.self, capacity: Int(MAXPATHLEN)){
                        String(cString: $0)
                    }
                }
                if on == "/" {
                    print(from)
                    if from.hasPrefix("/dev/") {
                        return false
                    }
                    if from.hasPrefix("com.apple.os.update-"){
                        return true
                    }
                    if from.contains("@"){
                        return true
                    }
                    print("From name is weird... assuming snapshot")
                    return true
                }
            }
            statfsptr = statfsptr?.successor()
        }
        fatalError("Didn't find /")
    }
    
    private func find_boot_snapshot() -> String? {
        let chosen = IORegistryEntryFromPath(0, "IODeviceTree:/chosen")
        guard let data = IORegistryEntryCreateCFProperty(chosen,
                                                         "boot-manifest-hash" as CFString,
                                                         kCFAllocatorDefault, 0).takeUnretainedValue() as? Data else {
            return nil
        }
        IOObjectRelease(chosen)
        
        var manifestHash = ""
        let buf = [UInt8](data)
        for byte in buf {
            manifestHash = manifestHash.appendingFormat("%02X", byte)
        }
        
        let systemSnapshot = "com.apple.os.update-" + manifestHash
        
        print("System Snapshot: ", systemSnapshot)
        return systemSnapshot
    }
    
    private func mountRealRootfs(rootvnode: UInt64) -> Int32 {
        let vmount = rk64ptr(rootvnode + offsets.vnode.mount)
        let dev = rk64(vmount + offsets.mount.devvp)
        
        /*let nameptr = rk64(dev + offsets.vnode.name)
        var name = [UInt8](repeating: 0, count: 20)
        kread(nameptr, &name, 20)
        print("found dev vnode name: ", String(cString: &name))*/
        // This debug code breaks for some users
        
        let specinfo = rk64ptr(dev + offsets.vnode.specinfo)
        let flags = rk32(specinfo + offsets.specinfo.flags)
        print("found dev flags: ", flags)
        
        wk32(specinfo + offsets.specinfo.flags, 0)
        
        let fspec = strdup("/dev/disk0s1s1")
        
        var mntargs = hfs_mount_args()
        mntargs.fspec = fspec
        mntargs.hfs_mask = 1
        gettimeofday(nil, &mntargs.hfs_timezone)
        
        let retval = mount("apfs", mntpath, 0, &mntargs)
        print("mount:",retval, errno)
        
        free(fspec)
        
        print("mount completed with status ", retval)
        
        return retval
    }
    
    private func findNewMount(rootvnode: UInt64) -> UInt64? {
        let snapshotMount = rk64ptr(rootvnode + offsets.vnode.mount)
        
        var vmount = rk64(snapshotMount + offsets.mount.mnt_next)
        while vmount != 0 {
            let dev = rk64(vmount + offsets.mount.devvp)
            if dev != 0 {
                let nameptr = rk64(dev + offsets.vnode.name)
                var name = [UInt8](repeating: 0, count: 20)
                kread(nameptr, &name, 20)
                let devName = String(cString: &name)
                print("found dev vnode name: ", devName)
                
                if devName == "disk0s1s1" && vmount != snapshotMount {
                    return vmount
                }
            }
            
            vmount = rk64(vmount + offsets.mount.mnt_next)
        }
        return nil
    }
    
    private func unsetSnapshotFlag(newmnt: UInt64) -> Bool {
        let dev = rk64(newmnt + offsets.mount.devvp)
        
        let nameptr = rk64(dev + offsets.vnode.name)
        var name = [UInt8](repeating: 0, count: 20)
        kread(nameptr, &name, 20)
        print("found dev vnode name: ", String(cString: &name))
        
        let specinfo = rk64ptr(dev + offsets.vnode.specinfo)
        let flags = rk32(specinfo + offsets.specinfo.flags)
        print("found dev flags: ", flags)
        
        var vnodelist = rk64(newmnt + offsets.mount.vnodelist)
        while vnodelist != 0 {
            print("vnodelist: ", vnodelist)

            let nameptr = rk64(vnodelist + offsets.vnode.name)
            let len = Int(kstrlen(nameptr))
            var name = [UInt8](repeating: 0, count: len)
            kread(nameptr, &name, len)
            
            let vnodeName = String(cString: &name)
            print("found vnode name: ", vnodeName)
            
            if vnodeName.hasPrefix("com.apple.os.update-") {
                let vdata = rk64(vnodelist + offsets.vnode.data)
                
                let flag = rk32(vdata + offsets.apfsData.flag)
                print("found apfs flag: ", flag)
                
                if (flag & 0x40) != 0 {
                    print("would unset the flag here to", flag & ~0x40)
                    wk32(vdata + offsets.apfsData.flag, flag & ~0x40)
                    return true
                }
            }
            
            usleep(1000)
            vnodelist = rk64(vnodelist + UInt64(0x20))
        }
        return false
    }
    
    public func remount(launchd_proc: UInt64, entitleMe: EntitleMe) -> Bool {
        let rootvnode = findRootVnode(launchd_proc: launchd_proc)
        if self.isRenameRequired() {
            if FileManager.default.fileExists(atPath: mntpathSW) {
                try? FileManager.default.removeItem(atPath: mntpathSW)
            }
            
            mkdir(mntpath, 0755)
            chown(mntpath, 0, 0)
            
            if isOTAMounted() {
                print("OTA update already mounted")
                return false
            }
            
            guard entitleMe.grabEntitlements(path: "/System/Library/Filesystems/apfs.fs/fsck_apfs",
                                             wantedEntitlements: [
                                                "com.apple.private.security.disk-device-access",
                                                "com.apple.private.vfs.snapshot",
                                                "com.apple.private.apfs.revert-to-snapshot"
                                             ]) else {
                return false
            }
            
            guard let bootSnapshot = find_boot_snapshot(),
                mountRealRootfs(rootvnode: rootvnode) == 0 else {
                entitleMe.resetEntitlements()
                return false
            }
            
            let fd = open("/var/MobileSoftwareUpdate/rootfsmnt", O_RDONLY, 0)
            guard fd > 0,
                fs_snapshot_revert(fd, bootSnapshot.cString(using: .utf8), 0) == 0 else {
                print("fs_snapshot_revert failed")
                unmount(mntpath, MNT_FORCE)
                rmdir(mntpath)
                entitleMe.resetEntitlements()
                return false
            }
            close(fd)
            
            guard unmount(mntpath, MNT_FORCE) == 0,
                  mountRealRootfs(rootvnode: rootvnode) == 0,
                  let newmnt = findNewMount(rootvnode: rootvnode),
                unsetSnapshotFlag(newmnt: newmnt) else {
                entitleMe.resetEntitlements()
                return false
            }
            
            let fd2 = open("/var/MobileSoftwareUpdate/rootfsmnt", O_RDONLY, 0)
            guard fd2 > 0,
                fs_snapshot_rename(fd2, bootSnapshot.cString(using: .utf8), "orig-fs", 0) == 0 else {
                print("fs_snapshot_rename failed")
                unmount(mntpath, 0)
                rmdir(mntpath)
                entitleMe.resetEntitlements()
                return false
            }
            close(fd2)
            
            unmount(mntpath, 0)
            rmdir(mntpath)
            
            entitleMe.resetEntitlements()
            
            print("rebooting...")
            print("=======================")
            print("Reboot required")
            print("Taurine has to reboot to finish the jailbreak process. When your device reboots, re-open Taurine to complete the process")
            print("Rebooting in 10 seconds...")
            sleep(10)
            reboot(0)
        } else {
            let vmount = rk64ptr(rootvnode + offsets.vnode.mount)
            let vflag = rk32(vmount + offsets.mount.flag) & ~(UInt32(MNT_RDONLY))
            wk32(vmount + offsets.mount.flag, vflag & ~UInt32(MNT_ROOTFS))
            
            var dev_path = strdup("/dev/disk0s1s1")
            let retval = mount("apfs", "/", MNT_UPDATE, &dev_path)
            free(dev_path)
            
            wk32(vmount + offsets.mount.flag, vflag | UInt32(MNT_NOSUID))
            return retval == 0
        }
        return true
    }
    
    public func restore_rootfs(entitleMe: EntitleMe) -> Bool {
        if !self.isRenameRequired() {
            guard let bootSnapshot = find_boot_snapshot() else {
                return false
            }
            
            try? FileManager.default.removeItem(atPath: "/var/cache")
            try? FileManager.default.removeItem(atPath: "/var/lib")
            try? FileManager.default.removeItem(atPath: "/var/log/apt")
            try? FileManager.default.removeItem(atPath: "/var/log/dpkg")
            try? FileManager.default.removeItem(atPath: "/var/db/sudo")
            
            guard entitleMe.grabEntitlements(path: "/System/Library/Filesystems/apfs.fs/fsck_apfs",
                                             wantedEntitlements: [
                                                "com.apple.private.security.disk-device-access",
                                                "com.apple.private.vfs.snapshot",
                                                "com.apple.private.apfs.revert-to-snapshot"
                                             ]) else {
                return false
            }
            
            mkdir(mntpath, 0755)
            chown(mntpath, 0, 0)
            
            let fd = open("/", O_RDONLY, 0)
            guard fd > 0,
                fs_snapshot_rename(fd, "orig-fs", bootSnapshot.cString(using: .utf8), 0) == 0 else {
                print("fs_snapshot_rename failed")
                entitleMe.resetEntitlements()
                return false
            }
            guard fs_snapshot_revert(fd, bootSnapshot.cString(using: .utf8), 0) == 0 else {
                print("fs_snapshot_revert failed")
                entitleMe.resetEntitlements()
                return false
            }
            guard fs_snapshot_mount(fd, mntpath, bootSnapshot.cString(using: .utf8), 0) == 0 else {
                print("fs_snapshot_mount failed")
                entitleMe.resetEntitlements()
                return false
            }
            close(fd)
            
            unlink("/var/containers/Bundle/Application/uicache")
            guard extractZstd(source: "uicache", dest: "/var/containers/Bundle/Application/uicache") else {
                print("failed to extract uicache")
                return false
            }
            chown("/var/containers/Bundle/Application/uicache", 0, 0)
            chmod("/var/containers/Bundle/Application/uicache", 0755)
            
            let rootApps: [String] = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
            let mntApps: [String] = (try? FileManager.default.contentsOfDirectory(atPath: "/var/MobileSoftwareUpdate/rootfsmnt/Applications")) ?? []
            let apps = Set(rootApps).subtracting(Set(mntApps))
            if !apps.isEmpty {
                var args = ["uicache"]
                for app in apps {
                    print("unregistering \(app)...")
                    args.append(contentsOf: ["-u", "/Applications/\(app)"])
                }
                let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
                defer { for case let arg? in argv { free(arg) } }
                
                var pid = pid_t(0)
                var status = posix_spawn(&pid, "/var/containers/Bundle/Application/uicache", nil, nil, argv + [nil], environ)
                if status == 0 {
                    if waitpid(pid, &status, 0) == -1 {
                        perror("waitpid")
                    }
                } else {
                    print("posix_spawn:", status)
                }
            }
            
            unmount(mntpath, 0)
            rmdir(mntpath)
            unlink("/var/containers/Bundle/Application/uicache")
            
            entitleMe.resetEntitlements()
            
            print("rebooting...")
            print("=======================")
            print("Reboot required")
            print("Taurine has to reboot to finish the restore. When your device reboots, you may open Taurine if you wish to re-jailbreak")
            print("Rebooting in 10 seconds...")
            sleep(10)
            reboot(0)
        } else {
            print("rootfs restore not required")
        }
        return true
    }
}
