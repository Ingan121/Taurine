//
//  amfidtakeover.swift
//  Taurine
//
//  Created by CoolStar on 3/30/20.
//  Copyright © 2020 coolstar. All rights reserved.
//

import Foundation
import Darwin.POSIX.spawn
import Darwin.Mach.message
import Darwin.Mach.thread_status

let ARM_THREAD_STATE64_COUNT = MemoryLayout<arm_thread_state64_t>.size/MemoryLayout<UInt32>.size

class AmfidTakeover {
    let offsets = Offsets.shared
    private var electra: Electra
    
    private var amfid_task_port: mach_port_t = mach_port_t()
    private var exceptionPort = mach_port_t()
    
    private var has_entitlements = false
    public var amfidebilitate_spawned = false
    
    init(electra: Electra) {
        self.electra = electra
    }
    
    public func startAmfid() {
        let dict = xpc_dictionary_create(nil, nil, 0)
        
        xpc_dictionary_set_uint64(dict, "subsystem", 3)
        xpc_dictionary_set_uint64(dict, "handle", UInt64(HANDLE_SYSTEM))
        xpc_dictionary_set_uint64(dict, "routine", UInt64(ROUTINE_START))
        xpc_dictionary_set_uint64(dict, "type", 1)
        xpc_dictionary_set_string(dict, "name", "com.apple.MobileFileIntegrity")
        
        var outDict: xpc_object_t?
        let rc = xpc_pipe_routine(xpc_bootstrap_pipe(), dict, &outDict)
        if rc == 0,
            let outDict = outDict {
            let rc2 = Int32(xpc_dictionary_get_int64(outDict, "error"))
            if rc2 != 0 {
                return
            }
        } else if rc != 0 {
            return
        }
    }

    
    public func grabEntitlements(entitleMe: EntitleMe) -> Bool {
        guard !has_entitlements else {
            return false
        }
        
        guard entitleMe.grabEntitlements(path: "/bin/ps", wantedEntitlements: ["task_for_pid-allow"]) else {
            return false
        }
                
        has_entitlements = true
        return true
    }
    
    public func resetEntitlements(entitleMe: EntitleMe) {
        guard has_entitlements else {
            return
        }
        
        entitleMe.resetEntitlements()
        
        has_entitlements = false
    }
    
    private func loadAddr(port: mach_port_t) -> UInt64 {
        var region_count = mach_msg_type_number_t(VM_REGION_BASIC_INFO_64)
        var object_name = mach_port_t(MACH_PORT_NULL)
        
        var first_addr = mach_vm_address_t(0)
        var first_size = mach_vm_size_t(0x1000)
        
        var region = vm_region_basic_info_64()
        let regionSz = MemoryLayout.size(ofValue: region)
        let err = withUnsafeMutablePointer(to: &region) {
            $0.withMemoryRebound(to: Int32.self, capacity: regionSz) {
                mach_vm_region(port,
                               &first_addr,
                               &first_size,
                               VM_REGION_BASIC_INFO_64,
                               $0,
                               &region_count,
                               &object_name)
            }
        }
        if err != KERN_SUCCESS {
            print("Failed to get the region:", mach_error_string(err) ?? "")
            return 0
        }
        return first_addr
    }
    
    private func amfidWrite64(addr: UInt64, data: UInt64) {
        var data = data
        _ = withUnsafePointer(to: &data) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt64>.size) {
                mach_vm_write(amfid_task_port, addr as mach_vm_address_t, $0, mach_msg_type_number_t(MemoryLayout<UInt64>.size))
            }
        }
    }
    
    private func amfidWrite32(addr: UInt64, data: UInt32) {
        var data = data
        _ = withUnsafePointer(to: &data) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt32>.size) {
                mach_vm_write(amfid_task_port, addr as mach_vm_address_t, $0, mach_msg_type_number_t(MemoryLayout<UInt32>.size))
            }
        }
    }
    
    private func amfidRead32(addr: UInt64) -> UInt32 {
        var data = UInt32(0)
        withUnsafeMutablePointer(to: &data) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt32>.size) {
                var outSz = mach_vm_size_t()
                mach_vm_read_overwrite(amfid_task_port, addr as mach_vm_address_t, mach_vm_size_t(MemoryLayout<UInt32>.size), $0, &outSz)
            }
        }
        return data
    }
    
    private func amfidRead64(addr: UInt64) -> UInt64 {
        var data = UInt64(0)
        withUnsafeMutablePointer(to: &data) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt64>.size) {
                var outSz = mach_vm_size_t()
                mach_vm_read_overwrite(amfid_task_port, addr as mach_vm_address_t, mach_vm_size_t(MemoryLayout<UInt64>.size), $0, &outSz)
            }
        }
        return data
    }
    
    private func amfidRead(addr: UInt64, len: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: len)
        var size = mach_vm_size_t()
        mach_vm_read_overwrite(amfid_task_port, addr as mach_vm_address_t, mach_vm_size_t(len), &buf, &size)
        return buf
    }
    
    private func amfidWrite(addr: UInt64, data: UnsafePointer<UInt8>, len: Int) {
        mach_vm_write(amfid_task_port, addr, data, mach_msg_type_number_t(len))
    }
    
    private func isRet(opcode: UInt32) -> Bool {
        (((opcode >> 25) & 0x7f) == 0b1101011) && (((opcode >> 21) & 0xf) == 0b10)
    }
    
    public func takeoverAmfid(amfid_pid: UInt32) {
        guard has_entitlements else {
            return
        }
        
        var standardError = FileHandle.standardError
        
        let retVal = task_for_pid(mach_task_self_, Int32(amfid_pid), &amfid_task_port)
        guard retVal == 0 else {
            print(String(format: "Unable to get amfid task: %s", mach_error_string(retVal)))
            return
        }
        
        let patchOffsets = parseMacho(path: "/usr/libexec/amfid", symbol: "_MISValidateSignatureAndCopyInfo")
        let loadAddress = loadAddr(port: amfid_task_port)
        
        mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &exceptionPort)
        mach_port_insert_right(mach_task_self_, exceptionPort, exceptionPort, mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
        
        task_set_exception_ports(amfid_task_port, exception_mask_t(EXC_MASK_BAD_ACCESS), exceptionPort, EXCEPTION_DEFAULT, ARM_THREAD_STATE64)
        
        var origOffsets: [UInt64:UInt64] = [:]
        
        for (patchOffset, signedPtr) in patchOffsets {
            let page = vm_address_t(loadAddress + UInt64(patchOffset)) & ~vm_page_mask
            vm_protect(amfid_task_port, page, vm_page_size, 0, VM_PROT_READ | VM_PROT_WRITE)
        
            let patchAddr = loadAddress + UInt64(patchOffset)
            
            origOffsets[patchAddr] = amfidRead64(addr: patchAddr)
            
            if signedPtr {
                var data = [signPac_data(ptr: 0x12345, context: patchAddr)]
                signPac_signPointers(&data, 1)
                
                amfidWrite64(addr: patchAddr, data: data[0].ptr)
            } else {
                amfidWrite64(addr: patchAddr, data: 0x12345)
            }
        }
        
        print("Got amfid task port: ", amfid_task_port, to: &standardError)
        
        DispatchQueue(label: "amfidebilitate", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem).async {
            var amfid_ret: UInt64 = 0
            
            while true {
                if self.amfidebilitate_spawned {
                    print("[amfid] amfidebilitate spawned. We done here.", to: &standardError)
                    mach_port_destroy(mach_task_self_, self.exceptionPort)
                    break
                }
                let head = UnsafeMutablePointer<mach_msg_header_t>.allocate(capacity: 0x4000)
                
                defer { head.deallocate() }
                
                var ret = mach_msg(head,
                                   MACH_RCV_MSG | MACH_RCV_LARGE | Int32(MACH_MSG_TIMEOUT_NONE),
                                   0,
                                   0x4000,
                                   self.exceptionPort,
                                   0, 0)
                guard ret == KERN_SUCCESS else {
                    print("[amfid] error receiving from port:", mach_error_string(ret) ?? "", to: &standardError)
                    continue
                }
                
                let req = head.withMemoryRebound(to: exception_raise_request.self, capacity: 0x4000) { $0.pointee }
//                let req = head
                
                let thread_port = req.thread.name
                let task_port = req.task.name
                
                defer {
                    var reply = exception_raise_reply()
                    reply.Head.msgh_bits = req.Head.msgh_bits & UInt32(MACH_MSGH_BITS_REMOTE_MASK)
                    reply.Head.msgh_size = mach_msg_size_t(MemoryLayout.size(ofValue: reply))
                    reply.Head.msgh_remote_port = req.Head.msgh_remote_port
                    reply.Head.msgh_local_port = mach_port_t(MACH_PORT_NULL)
                    reply.Head.msgh_id = req.Head.msgh_id + 0x64
                    
                    reply.NDR = req.NDR
                    reply.RetCode = KERN_SUCCESS
                    
                    ret = mach_msg(&reply.Head,
                                   1,
                                   reply.Head.msgh_size,
                                   0,
                                   mach_port_name_t(MACH_PORT_NULL),
                                   MACH_MSG_TIMEOUT_NONE,
                                   mach_port_name_t(MACH_PORT_NULL))
                    mach_port_deallocate(mach_task_self_, thread_port)
                    mach_port_deallocate(mach_task_self_, task_port)
                    
                    if ret != KERN_SUCCESS {
                        print("[amfid] error sending reply to exception: ", mach_error_string(ret) ?? "", to: &standardError)
                    }
                }
                
                var state = arm_thread_state64_t()
                var stateCnt = mach_msg_type_number_t(ARM_THREAD_STATE64_COUNT)
                
                ret = withUnsafeMutablePointer(to: &state) {
                    $0.withMemoryRebound(to: UInt32.self, capacity: MemoryLayout<arm_thread_state64_t>.size) {
                        thread_get_state(thread_port, ARM_THREAD_STATE64, $0, &stateCnt)
                    }
                }
                guard ret == KERN_SUCCESS else {
                    print("[amfid] error getting thread state:", mach_error_string(ret) ?? "", to: &standardError)
                    continue
                }
                
                if amfid_ret == 0 {
                    let lr = getLr(state)
                    let pageDumpRaw = self.amfidRead(addr: lr, len: Int(vm_page_size))
                    for i in 0..<Int(vm_page_size) / MemoryLayout<UInt32>.size {
                        let offset = i * MemoryLayout<UInt32>.size
                        let op = pageDumpRaw.withUnsafeBytes {
                            $0.load(fromByteOffset: offset, as: UInt32.self)
                        }
                        if op == 0x52800000 {
                            amfid_ret = lr + UInt64(offset)
                        }
                        if self.isRet(opcode: op) {
                            break
                        }
                    }
                    
                    if isArm64e(){
                        var data = [signPac_data(ptr: amfid_ret, context: Offsets.shared.pac.pc)]
                        signPac_signPointers(&data, 1)
                        
                        amfid_ret = data[0].ptr
                    }
                }
                
                defer {
                    setPc(&state, amfid_ret)
                    ret = withUnsafeMutablePointer(to: &state) {
                        $0.withMemoryRebound(to: UInt32.self, capacity: MemoryLayout<arm_thread_state64_t>.size) {
                            thread_set_state(thread_port, 6, $0, mach_msg_type_number_t(ARM_THREAD_STATE64_COUNT))
                        }
                    }
                    if ret != KERN_SUCCESS {
                        print("[amfid] error setting thread state:", mach_error_string(ret) ?? "", to: &standardError)
                    }
                }
                
                let fileNameRaw = self.amfidRead(addr: state.__x.22, len: 1024)
                guard let fileNamePtr = fileNameRaw.withUnsafeBytes({ $0.bindMemory(to: UInt8.self) }).baseAddress else {
                    self.amfidWrite32(addr: state.__x.26, data: 0)
                    continue
                }
                
                let fileName = String(cString: fileNamePtr)
                
                autoreleasepool {
                    let newCdHash = getCodeSignature(path: fileName)
                    if newCdHash.count == CS_CDHASH_LEN {
                        self.amfidWrite(addr: state.__x.23, data: newCdHash, len: CS_CDHASH_LEN)
                        self.amfidWrite32(addr: state.__x.26, data: 1)
                        
                        if fileName == "/taurine/amfidebilitate" {
                            self.amfidebilitate_spawned = true
                            for (patchOffset, _) in patchOffsets {
                                let patchAddr = loadAddress + UInt64(patchOffset)
                                
                                self.amfidWrite64(addr: patchAddr, data: origOffsets[patchAddr] ?? UInt64(0))
                            }
                        }
                    } else {
                        self.amfidWrite32(addr: state.__x.26, data: 0)
                    }
                }
            }
        }
    }
    
    public func spawnAmfiDebilitate(kernelProc: UInt64) -> Bool {
        let kernelProcStr = String(format: "0x%llx", kernelProc)
        let environmentVariables = [
            "kernelProc": kernelProcStr
        ]
        
        let launchdPlist: [String: Any] = [
            "KeepAlive": true,
            "RunAtLoad": true,
            "UserName": "root",
            "Program": "/taurine/amfidebilitate",
            "Label": "amfidebilitate",
            "POSIXSpawnType": "Interactive",
            "EnvironmentVariables": environmentVariables
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: launchdPlist, format: .binary, options: .zero)
        try? plistData?.write(to: URL(fileURLWithPath: "/taurine/amfidebilitate.plist"))
        
        let dict = xpc_dictionary_create(nil, nil, 0)
        
        var str = xpc_string_create("/taurine/amfidebilitate.plist")
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
        return true
    }
}
