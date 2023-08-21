import Foundation

public enum UntetherState {
    case enabled
    case disabled
    case forceRestore
}

public func getUntetherState() -> UntetherState {
    var masterPort: io_master_t = 0
    let kr = IOMasterPort(bootstrap_port, &masterPort)
    guard kr == KERN_SUCCESS else {
        // Safety first
        return .disabled
    }
    
    let entry = IORegistryEntryFromPath(masterPort, "IODeviceTree:/options")
    guard entry != 0 else {
        // Safety first
        return .disabled
    }
    
    defer { IOObjectRelease(entry) }
    
    guard let nvramVar = IORegistryEntryCreateCFProperty(entry, "boot-args" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? String else {
        // Safety first
        return .disabled
    }
    
    if nvramVar.contains("untether_force_restore") {
        return .forceRestore
    } else if nvramVar.contains("no_untether") {
        return .disabled
    }
    
    return .enabled
}

func jailbreak() {
    let state = getUntetherState()
    if state == .disabled {
        print("Detected no_untether boot-args. Aborting jailbreak...")
        return
    }
    print("Running Exploit.. 1/3")
    
    let enableTweaks = true
    let restoreRootFs = state == .forceRestore
    let generator = "0xbd34a880be0b53f3"
    let useSmith = true
            
    var hasKernelRw = false
    var any_proc = UInt64(0)
    
    if #available(iOS 14, *){
        if useSmith {
            print("Selecting kfd - smith exploit for iOS 14.0 - 14.4.2")
            if do_kopen(0x800, 0x1, 0x2, 0x2) != 0 {
                print("Successfully exploited kernel!");
                any_proc = our_proc_kAddr
                hasKernelRw = true
            }
        }
        else {
            print("Selecting kfd - physpuppet exploit for iOS 14.0 - 14.4.2")
            if do_kopen(0x800, 0x0, 0x2, 0x2) != 0 {
                print("Successfully exploited kernel!");
                any_proc = our_proc_kAddr
                hasKernelRw = true
            }
        }
                
    }
    guard hasKernelRw else {
        print("Error: Exploit Failed")
        exit(-1)
    }
            
    print("Please Wait... 2/3")
    let electra = Electra(
        any_proc: any_proc,
        enable_tweaks: enableTweaks,
        restore_rootfs: restoreRootFs,
        nonce: generator)
    let err = electra.jailbreak()
    
    if err != .ERR_NOERR {
        print("Oh no", "\(String(describing: err))")
    }
}

print(String(format: "our uid is %d", getuid()))

if getuid() == 0 {
    print("Running as root is not supported!") // it will cause a panic during post-exploit
    print("Please run as mobile.")
} else {
    jailbreak()
}
