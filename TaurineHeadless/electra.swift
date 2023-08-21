//
//  electra.swift
//  Taurine
//
//  Created by CoolStar on 3/1/20.
//  Copyright © 2020 coolstar. All rights reserved.
//

import Foundation

enum JAILBREAK_RETURN_STATUS {
    case ERR_NOERR
    case ERR_VERSION
    case ERR_EXPLOIT
    case ERR_UNSUPPORED
    case ERR_KERNRW
    case ERR_ALREADY_JAILBROKEN
    case ERR_ROOTFS_RESTORE
    case ERR_REMOUNT
    case ERR_SNAPSHOT
    case ERR_JAILBREAK
    case ERR_CONFLICT
}

class Electra {
    private let any_proc: UInt64
    private let enable_tweaks: Bool
    private let restore_rootfs: Bool
    private let nonce: String
    
    private let offsets = Offsets.shared
    private let consts = Consts.shared
    
    private var kernel_slide: UInt64 = 0
    
    public var all_proc: UInt64 = 0
    
    private(set) var our_proc: UInt64 = 0
    private(set) var launchd_proc: UInt64 = 0
    private(set) var kernel_proc: UInt64 = 0
    
    private(set) var amfid_pid: UInt32 = 0
    private(set) var jailbreakd_pid: UInt32 = 0
    private(set) var cfprefsd_pid: UInt32 = 0
    
    private var our_task_addr: UInt64 = 0
    private var our_label: UInt64 = 0
    
    private var root_vnode: UInt64 = 0
    
    public init(any_proc: UInt64, enable_tweaks: Bool, restore_rootfs: Bool, nonce: String) {
        self.any_proc = any_proc
        self.enable_tweaks = enable_tweaks
        self.restore_rootfs = restore_rootfs
        self.nonce = nonce
    }
    
    private func find_allproc() {
        var proc = rk64(kernel_proc + 8)
        while proc != 0 {
            let prevProc = rk64(proc + 8)
            let pid = rk32(proc + offsets.proc.pid)
            if pid == 0 {
                print("May have found allproc...")
                all_proc = proc
                break
            }
            if prevProc == 0 {
                print("Can't find allProc. Using fallback")
                all_proc = 0
                break
            }
            if rk64(prevProc) != proc {
                print(String(format: "Allproc? 0x%llx", proc))
                all_proc = proc
                break
            }
            proc = prevProc
        }
    }
    
    private func find_kernproc(){
        var proc = any_proc
        while proc != 0 {
            let pid = rk32(proc + offsets.proc.pid)
            if pid == 0 {
                print("Found kernproc")
                kernel_proc = proc
                break
            }
            proc = rk64(proc)
        }
    }
    
    public func findPort(port: mach_port_name_t) -> UInt64 {
        let ourTask = rk64ptr(self.our_proc + offsets.proc.task)
        let itkSpace = rk64ptr(ourTask + offsets.task.itk_space)
        let isTable = rk64ptr(itkSpace + offsets.ipc_space.is_table)
        
        let portIndex = UInt32(port) >> 8
        let ipcEntrySz = UInt32(0x18)
        
        let portAddr = rk64ptr(isTable + UInt64((portIndex * ipcEntrySz)))
        return portAddr
    }
    
    public func fixOurProc(our_proc: UInt64){
        our_task_addr = rk64ptr(our_proc + offsets.proc.task)
        
        let our_flags = rk32(our_task_addr + offsets.task.flags)
        wk32(our_task_addr + offsets.task.flags, our_flags | consts.TF_PLATFORM)
        
        var our_csflags = rk32(our_proc + offsets.proc.csflags)
        our_csflags = our_csflags | consts.CS_PLATFORM_BINARY | consts.CS_INSTALLER | consts.CS_GET_TASK_ALLOW
        our_csflags &= ~(consts.CS_RESTRICT | consts.CS_HARD | consts.CS_KILL)
        wk32(our_proc + offsets.proc.csflags, our_csflags)
    }
    
    public func populate_procs() {
        let our_pid = getpid()
        var proc = all_proc != 0 ? rk64(all_proc) : kernel_proc
        while proc != 0 {
            let pid = rk32(proc + offsets.proc.pid)
            if pid == 0 && all_proc != 0 {
                kernel_proc = proc
                print("found kernel proc")
            } else if pid == our_pid {
                print("found our pid")
                
                our_proc = proc
                fixOurProc(our_proc: proc)
                
                let our_vnode = rk64ptr(proc + offsets.proc.textvp)
                if our_vnode != 0 {
                    let ubc_info = rk64ptr(our_vnode + offsets.vnode.ubcinfo)
                    if ubc_info != 0 {
                        var cs_blobs = rk64ptr(ubc_info + offsets.ubcinfo.csblobs)
                        while cs_blobs != 0 {
                            let csb_platform_binary = rk32(cs_blobs + offsets.csblob.csb_platform_binary)
                            wk32(cs_blobs + offsets.csblob.csb_platform_binary, csb_platform_binary | 1)
                            
                            cs_blobs = rk64ptr(cs_blobs)
                        }
                    }
                }
            } else if pid == 1 {
                print("found launchd")
                
                launchd_proc = proc
            } else {
                let nameptr = proc + offsets.proc.name
                var name = [UInt8](repeating: 0, count: 32)
                kread(nameptr, &name, 32)
                //print("found proc name: ", String(cString: &name))

                let swiftName = String(cString: &name)
                if swiftName == "amfid" {
                    print("found amfid")
                    amfid_pid = pid
                    
                    let amfid_csflags = rk32(proc + offsets.proc.csflags)
                    wk32(proc + offsets.proc.csflags, amfid_csflags | consts.CS_GET_TASK_ALLOW)
                } else if swiftName == "cfprefsd" {
                    print("found cfprefsd")
                    cfprefsd_pid = pid
                } else if swiftName == "jailbreakd" || swiftName == "substrated" || swiftName == "substituted" {
                    print("found jailbreakd (\(swiftName))")
                    jailbreakd_pid = pid
                }
            }
            
            if all_proc == 0 {
                proc = rk64(proc + 8)
            } else {
                proc = rk64(proc)
            }
        }
    }
    
    public func find_proc(pid: UInt32) -> UInt64 {
        var proc = all_proc != 0 ? rk64(all_proc) : kernel_proc
        while proc != 0 {
            let proc_pid = rk32(proc + offsets.proc.pid)
            if proc_pid == pid {
                return proc
            }
            if all_proc == 0 {
                proc = rk64(proc + 8)
            } else {
                proc = rk64(proc)
            }
        }
        return proc
    }
    
    private func getRoot() -> JAILBREAK_RETURN_STATUS {
        let self_ucred = rk64ptr(our_proc + offsets.proc.ucred)
        
        let our_label = rk64ptr(self_ucred + offsets.ucred.cr_label)
        
        let our_sandboxPAC = rk64(our_label + 0x10)
        
        wk64(our_label + 0x10, 0)
        wk32(self_ucred + offsets.ucred.cr_svuid, UInt32(0))
        
        setuid(0)
        setuid(0)
        
        wk64(our_label + 0x10, our_sandboxPAC)
        
        guard getuid() == 0 else {
            return .ERR_JAILBREAK
        }
        return .ERR_NOERR
    }
    
    private func cleanupCreds() {
        setuid(501)
        print("Reset creds")
    }
    
    private func dePlatform(){
        let our_vnode = rk64ptr(our_proc + offsets.proc.textvp)
        if our_vnode != 0 {
            let ubc_info = rk64ptr(our_vnode + offsets.vnode.ubcinfo)
            if ubc_info != 0 {
                var cs_blobs = rk64ptr(ubc_info + offsets.ubcinfo.csblobs)
                while cs_blobs != 0 {
                    let csb_platform_binary = rk32(cs_blobs + offsets.csblob.csb_platform_binary)
                    wk32(cs_blobs + offsets.csblob.csb_platform_binary, csb_platform_binary & ~UInt32(1))
                    
                    cs_blobs = rk64ptr(cs_blobs)
                }
            }
        }
    }
    
    public func jailbreak() -> JAILBREAK_RETURN_STATUS {
        var doUserspaceReboot = 0
        let ret = jailbreak_internal(doUserspaceReboot: &doUserspaceReboot)
        
        defer { cleanupCreds() }
        
        if doUserspaceReboot == 1 {
            //_ = runUnsandboxed(cmd: "/usr/bin/nohup /usr/bin/ldrestart >/dev/null 2>&1 &")
        }
        
        if doUserspaceReboot == 2 {
            let handoffPidFile = "/var/run/launchd-handoff.pid"
            while !FileManager.default.fileExists(atPath: handoffPidFile){
                usleep(1000)
            }
            
            while Int((try? String(contentsOf: URL(fileURLWithPath: handoffPidFile))) ?? "") == nil {
                usleep(1000)
            }
            
            print("Initiating userspace reboot (2/3)...")
            
            if let handoffPidStr = try? String(contentsOf: URL(fileURLWithPath: handoffPidFile)),
               let handoffPid = Int(handoffPidStr),
               handoffPid > 0 {
                var jbd_port = mach_port_t(MACH_PORT_NULL)
                guard bootstrap_look_up(bootstrap_port, "org.coolstar.jailbreakd", &jbd_port) == KERN_SUCCESS else {
                    print("Unable to get jailbreakd")
                    return .ERR_JAILBREAK
                }
                let JAILBREAKD_COMMAND_EARLY_KRW_HANDOFF = UInt8(0x42)
                let JAILBREAKD_COMMAND_EARLY_KRW_HANDOFF_STATUS = UInt8(0x43)
                
                repeat {
                    let callErr = jbd_call(jbd_port, JAILBREAKD_COMMAND_EARLY_KRW_HANDOFF, UInt32(handoffPid))
                    guard callErr == KERN_SUCCESS else {
                        print(String(format: "Unable to tell jailbreakd to handoff: %s", mach_error_string(callErr)))
                        sleep(1)
                        continue
                    }
                    
                    let statusErr = jbd_call(jbd_port, JAILBREAKD_COMMAND_EARLY_KRW_HANDOFF_STATUS, UInt32(handoffPid))
                    guard statusErr == KERN_ALREADY_WAITING || statusErr == KERN_SUCCESS else {
                        print(String(format: "handoff status failed: %s", mach_error_string(statusErr)))
                        sleep(1)
                        continue
                    }
                    break
                } while true
            }
        }
        return ret
    }
    
    private func procName(pid: pid_t) -> String? {
        var path_buffer = [UInt8](repeating: 0, count: 4096)
        let ret = proc_pidpath(pid, &path_buffer, 4096)
        if ret < 0 {
            return nil
        }
        
        let pathStr = String(cString: path_buffer)
        return pathStr
    }
     
    private func jailbreak_internal(doUserspaceReboot: inout Int) -> JAILBREAK_RETURN_STATUS {
        doUserspaceReboot = 0
        
        print("Starting Electra...")
        
        guard isKernRwReady() else {
            return .ERR_KERNRW
        }
        
        defer { terminateKernRw() }
        
        var err: JAILBREAK_RETURN_STATUS = .ERR_NOERR
        
        find_kernproc()
        
        find_allproc()
        populate_procs()
        
        defer { dePlatform() }

        if jailbreakd_pid != 0 {
            return .ERR_ALREADY_JAILBROKEN
        }
        
        let slide = getKernSlide(our_proc: our_proc)
        print(String(format: "kernel slide is at 0x%016llx", slide))
        kernel_slide = slide
        
        ksetOffsets(slide + UInt64(0xFFFFFFF007004000), kernel_proc, all_proc)
        
        print(String(format: "our proc is at 0x%016llx", our_proc))
        print(String(format: "kern proc is at 0x%016llx", kernel_proc))
        
        err = getRoot()
        if err != .ERR_NOERR {
            return err
        }
        
        print(String(format: "our uid is %d", getuid()))
        
        let entitleMe = EntitleMe(electra: self)
        
        let nvram = NVRamUtil(electra: self)
        _ = nvram.setNonce(nonce: nonce, entitleMe: entitleMe) //Not fatal is nonce setting fails
        
        let signOracle = signPAC_initSigningOracle()
        var signPac: [signPac_data] = []
        var thread_jop_pid_offset = UInt64(0)
        let pac_testSym = findSymbol("posix_spawn")
        let pac_compare = signPtr(pac_testSym, 0)
        if isArm64e() {
            let our_jop_pid = rk64(our_task_addr + offsets.task.jop_pid)
            
            let launchd_task = rk64ptr(launchd_proc + offsets.proc.task)
            let launchd_jop_pid = rk64(launchd_task + offsets.task.jop_pid)
            
            let signThreadPort = findPort(port: signOracle)
            let signThread = rk64ptr(signThreadPort + offsets.ipc_port.ip_kobject)
            
            for i in 0..<170 {
                let test_rd = rk64(signThread + UInt64(i * 8))
                if test_rd == our_jop_pid {                    thread_jop_pid_offset = UInt64(i * 8)
                    break
                }
            }
            
            guard thread_jop_pid_offset != 0 else {
                return .ERR_JAILBREAK
            }
            
            signPac.append(signPac_data(ptr: pac_testSym, context: 0))
            
            signPac_signPointers(&signPac, 1)
            
            wk64(signThread + thread_jop_pid_offset, launchd_jop_pid)
            
            while signPac[0].ptr == pac_compare {
                signPac = []
                signPac.append(signPac_data(ptr: pac_testSym, context: 0))
                
                signPac_signPointers(&signPac, 1)
            }
        }
        
        defer {
            if isArm64e(){
                let our_jop_pid = rk64(our_task_addr + offsets.task.jop_pid)
                let signThreadPort = findPort(port: signOracle)
                let signThread = rk64ptr(signThreadPort + offsets.ipc_port.ip_kobject)
                
                wk64(signThread + thread_jop_pid_offset, our_jop_pid)
                
                while signPac[0].ptr != pac_compare {
                    signPac = []
                    signPac.append(signPac_data(ptr: pac_testSym, context: 0))
                    
                    signPac_signPointers(&signPac, 1)
                }
                signPac_destroySigningOracle()
                signPac = []
            }
        }
        print("11111111")
        let amfidtakeover = AmfidTakeover(electra: self)
        guard amfidtakeover.grabEntitlements(entitleMe: entitleMe) else {
            return .ERR_JAILBREAK
        }
        print("22222")
        if amfid_pid == 0 {
            print("Attempting to start amfid as we didn't find it")
            amfidtakeover.startAmfid()
            while queryDaemon(daemonLabel: "com.apple.MobileFileIntegrity") <= 0 {
                print("Waiting for amfid to register")
                sleep(1)
            }
            amfid_pid = UInt32(queryDaemon(daemonLabel: "com.apple.MobileFileIntegrity"))
            print("amfid pid:", amfid_pid)
            while procName(pid: pid_t(amfid_pid)) != "/usr/libexec/amfid" {
                usleep(1000)
            }
            
            print("sending test query to amfid")
            _ = testUnsandboxedExec()
            
            print("amfid test query sent")
        }
        amfidtakeover.takeoverAmfid(amfid_pid: amfid_pid)
        
        amfidtakeover.resetEntitlements(entitleMe: entitleMe)
        
        let remount = Remount(electra: self, kernel_proc: kernel_proc)
        if !remount.remount(launchd_proc: launchd_proc, entitleMe: entitleMe) {
            return .ERR_REMOUNT
        }
        
        if restore_rootfs {
            if !remount.restore_rootfs(entitleMe: entitleMe) {
                return .ERR_ROOTFS_RESTORE
            }
            return .ERR_NOERR
        }
        
        try? FileManager.default.removeItem(atPath: "/taurine")
        
        mkdir("/taurine", 0o755)
        chown("/taurine", 0, 0)
        
        mkdir("/taurine/cstmp/", 0o700)
        chown("/taurine/cstmp/", 0, 0)
        
        unlink("/taurine/pspawn_payload.dylib")
        unlink("/usr/lib/pspawn_payload-stg2.dylib")
        
        guard extractZstd(source: "tar", dest: "/taurine/tar") else {
            return .ERR_JAILBREAK
        }
        try? FileManager.default.copyItem(at: Bundle.main.url(forResource: "signcert", withExtension: "p12")!,
                                          to: URL(fileURLWithPath: "/taurine/signcert.p12"))
        chown("/taurine/tar", 0, 0)
        chmod("/taurine/tar", 0o0755)
        guard untarBasebins() else {
            return .ERR_JAILBREAK
        }
        
        rename("/taurine/pspawn_payload-stg2.dylib", "/usr/lib/pspawn_payload-stg2.dylib")
        
        unlink("/var/run/amfidebilitate.pid")
        guard amfidtakeover.spawnAmfiDebilitate(kernelProc: kernel_proc) else {
            print("failed to submit amfidebilitate...")
            return .ERR_JAILBREAK
        }
        
        print("waiting for amfidebilitate...")
        while !amfidtakeover.amfidebilitate_spawned {
            usleep(1000)
        }
        
        while queryDaemon(daemonLabel: "amfidebilitate") == 0 {
            usleep(1000)
        }
        
        let amfidebilitatePid = queryDaemon(daemonLabel: "amfidebilitate")
        print("amfidebilitate daemon pid", amfidebilitatePid)
        
        guard entitleMe.grabEntitlements(path: "/bin/ps", wantedEntitlements: ["task_for_pid-allow"]) else {
            return .ERR_JAILBREAK
        }
        handoffKernRw(pid_t(amfidebilitatePid),"/taurine/amfidebilitate")
        
        while !FileManager.default.fileExists(atPath: "/var/run/amfidebilitate.pid") {
            usleep(1000)
        }
               
        print("Waiting for amfi to really be debilitated...")
        while testUnsandboxedExec() != 0 {
            usleep(1000)
        }
        
        print("Starting Patchfinder...")
        
        guard getKernel() else {
            print("Unable to extract kernel")
            return .ERR_JAILBREAK
        }
        guard let kernelPatchFinder = KernelPatchfinder(url: URL(fileURLWithPath: "/tmp/kernel")) else {
            print("Unable to initialize patchfinder")
            return .ERR_JAILBREAK
        }
        guard let rawGenCountAddr = kernelPatchFinder.find_cs_blob_generation_count() else {
            print("Error: patchfinder failed")
            return .ERR_JAILBREAK
        }
        let genCountAddr = rawGenCountAddr + slide
        unlink("/tmp/kernel")
        print("Done patchfinding")
        
        guard spawnJailbreakd(genCountAddr: genCountAddr) else {
            return .ERR_JAILBREAK
        }
        
        while queryDaemon(daemonLabel: "jailbreakd") == 0 {
            usleep(0)
        }
        
        let jailbreakdPid = queryDaemon(daemonLabel: "jailbreakd")
        print("jailbreakd pid", jailbreakdPid)
        handoffKernRw(pid_t(jailbreakdPid), "/taurine/jailbreakd")
        
        entitleMe.resetEntitlements()
        
        print("Waiting for jailbreakd...")
        while !FileManager.default.fileExists(atPath: "/var/run/jailbreakd.pid") {
            usleep(1000)
        }
        print("jailbreakd started")
                
        guard bootstrapDevice() else {
            return .ERR_JAILBREAK
        }
        
        if enable_tweaks {
            unlink("/.disable_tweakinject")
        } else {
            try? "".write(toFile: "/.disable_tweakinject", atomically: false, encoding: .utf8)
        }
        
        var springboardPlist: [String: Any] = [:]
        let plistURL = URL(fileURLWithPath: "/var/mobile/Library/Preferences/com.apple.springboard.plist")
        if let plistData = try? Data(contentsOf: plistURL) {
            if let springboardPlistRaw = try? PropertyListSerialization.propertyList(from: plistData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                springboardPlist = springboardPlistRaw
            }
        }
        springboardPlist["SBShowNonDefaultSystemApps"] = true
        if let data = try? PropertyListSerialization.data(fromPropertyList: springboardPlist, format: .binary, options: 0) {
            try? data.write(to: plistURL)
        }
        
        try? FileManager.default.setAttributes([FileAttributeKey.posixPermissions: 0755,
                                           FileAttributeKey.ownerAccountName: "mobile"], ofItemAtPath: plistURL.path)
        
        kill(pid_t(cfprefsd_pid), SIGKILL)
        
        _ = runUnsandboxed(cmd: "uicache -p /Applications/SafeMode.app")
        
        //startDaemons()

        let files = [
            "/sbin/launchd",
            "/usr/libexec/xpcproxy",
            "/taurine/amfidebilitate",
            "/taurine/jailbreakd",
            "/usr/libexec/keybagd",
            "/taurine/pspawn_payload.dylib"
        ]
        for file in files {
            retainFile(file: file, our_proc: our_proc)
        }
        _ = preflightExecutable(exec: "/sbin/launchd")
        _ = preflightExecutable(exec: "/usr/libexec/keybagd")
        _ = runUnsandboxed(cmd: "DYLD_INSERT_LIBRARIES=/taurine/pspawn_payload.dylib /usr/libexec/xpcproxy")
        
        try? "1".write(toFile: "/taurine/runtime_vers", atomically: true, encoding: .utf8)
        
        _ = prepareUserspaceReboot(allProc:all_proc, kernelProc: kernel_proc, genCountAddr: genCountAddr)
        doUserspaceReboot = 2
        
        return err
    }
    
    private func spawnJailbreakd(genCountAddr: UInt64) -> Bool {
        let genCountAddrStr = String(format: "0x%llx", genCountAddr)
        let allProcStr = String(format: "0x%llx", all_proc)
        let kernelProcStr = String(format: "0x%llx", kernel_proc)
        
        let environmentVariables = [
            "genCountAddr": genCountAddrStr,
            "allProc": allProcStr,
            "kernelProc": kernelProcStr//,
            //"LAUNCHD": "1"
        ]
        
        let launchdPlist: [String: Any] = [
            "KeepAlive": true,
            "RunAtLoad": true,
            "UserName": "root",
            "Program": "/taurine/jailbreakd",
            "Label": "jailbreakd",
            "POSIXSpawnType": "Interactive",
            "EnvironmentVariables": environmentVariables,
            "MachServices": [
                "org.coolstar.jailbreakd": [
                    "HostSpecialPort": 15
                ]
            ]
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: launchdPlist, format: .binary, options: .zero)
        try? plistData?.write(to: URL(fileURLWithPath: "/taurine/jailbreakd.plist"))
        
        let dict = xpc_dictionary_create(nil, nil, 0)
        
        var str = xpc_string_create("/taurine/jailbreakd.plist")
        let paths = xpc_array_create(&str, 1)
        
        xpc_dictionary_set_value(dict, "paths", paths)
        xpc_dictionary_set_uint64(dict, "subsystem", 3)
        xpc_dictionary_set_bool(dict, "enable", true)
        xpc_dictionary_set_uint64(dict, "type", 1)
        xpc_dictionary_set_uint64(dict, "handle", 0)
        xpc_dictionary_set_uint64(dict, "routine", UInt64(ROUTINE_LOAD))
        
        var outDict: xpc_object_t?
        let rc = xpc_pipe_routine(xpc_bootstrap_pipe(), dict, &outDict)
        if rc == 0,
            let outDict = outDict {
            let rc2 = Int32(xpc_dictionary_get_int64(outDict, "error"))
            if rc2 != 0 {
                print(String(format: "Error submitting service: %s", xpc_strerror(rc2)))
                return false
            }
        } else if rc != 0 {
            print(String(format: "Error submitting service (no outdict): %s", xpc_strerror(rc)))
            return false
        }
        
        print("NERF THIS!!!")
        return true
    }
}
