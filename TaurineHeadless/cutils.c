//
//  nvramutils.c
//  Chimera
//
//  Created by CoolStar on 9/3/19.
//  Copyright © 2019 Electra Team. All rights reserved.
//

#include "cutils.h"
#include <ptrauth.h>
#include <dlfcn.h>

#if DEBUG
extern void swiftDebug_internal(const char *);
void swiftDebug(const char *format, ...){
    va_list args;
    va_start(args, format);
    
    size_t bufSz = vsnprintf(NULL, 0, format, args);
    char *buf = malloc(bufSz + 1);
    vsnprintf(buf, bufSz + 1, format, args);
    swiftDebug_internal(buf);
    free(buf);
    va_end(args);
}
#endif

uint64_t lookup_key_in_dicts(dict_entry_t *os_dict_entries, uint32_t count, uint64_t key){
    uint64_t value = 0;
    for (int i = 0; i < count; ++i){
        if (os_dict_entries[i].key == key){
            value = os_dict_entries[i].value;
            break;
        }
    }
    return value;
}

void iterate_keys_in_dict(dict_entry_t *os_dict_entries, uint32_t count, void (^callback)(uint64_t key, uint64_t value)){
    for (int i = 0; i < count; ++i){
        callback(os_dict_entries[i].key, os_dict_entries[i].value);
    }
}

bool isArm64e(void){
#if __arm64e__
    return (ptrauth_sign_unauthenticated((void *)0x12345, ptrauth_key_asia, 0) != (void *)0x12345);
#else
    return false;
#endif
}

extern uint64_t rk64(uint64_t);
uint64_t rk64ptr(uint64_t where){
    uint64_t raw = rk64(where);
#if __arm64e__
    if (raw){
        raw |= 0xffffff8000000000;
    }
#endif
    return raw;
}

uint64_t signPtr(uint64_t data, uint64_t key) {
    return (uint64_t)ptrauth_sign_unauthenticated((void *)data, ptrauth_key_asia, key);
}

uint64_t getFp(arm_thread_state64_t state){
#if __arm64e__
    if (state.__opaque_flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH){
        return (uint64_t)state.__opaque_fp;
    }
    return (uint64_t)ptrauth_strip(state.__opaque_fp, ptrauth_key_process_independent_code);
#else
    return state.__fp;
#endif
}

uint64_t getLr(arm_thread_state64_t state){
#if __arm64e__
    if (state.__opaque_flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH){
        return (uint64_t)state.__opaque_lr;
    }
    uint64_t lr = (uint64_t)ptrauth_strip(state.__opaque_lr, ptrauth_key_process_independent_code);
    return lr;
#else
    return state.__lr;
#endif
}

uint64_t getSp(arm_thread_state64_t state){
#if __arm64e__
    if (state.__opaque_flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH){
        return (uint64_t)state.__opaque_sp;
    }
    return (uint64_t)ptrauth_strip(state.__opaque_sp, ptrauth_key_process_independent_code);
#else
    return state.__sp;
#endif
}

uint64_t getPc(arm_thread_state64_t state){
#if __arm64e__
    if (state.__opaque_flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH){
        return (uint64_t)state.__opaque_pc;
    }
    return (uint64_t)ptrauth_strip(state.__opaque_pc, ptrauth_key_process_independent_code);
#else
    return state.__pc;
#endif
}

void setLr(arm_thread_state64_t *state, uint64_t lr){
#if __arm64e__
#if DEBUG
    if (lr == (uint64_t)ptrauth_strip((void *)lr, ptrauth_key_asia)){
        fprintf(stderr, "Warning: LR needs to be signed on arm64e!\n");
    }
#endif
    state->__opaque_flags = state->__opaque_flags & ~__DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR;
    state->__opaque_lr = (void *)lr;
#else
    state->__lr = lr;
#endif
}

void setPc(arm_thread_state64_t *state, uint64_t pc){
#if __arm64e__
#if DEBUG
    if (pc == (uint64_t)ptrauth_strip((void *)pc, ptrauth_key_asia)){
        fprintf(stderr, "Warning: PC needs to be signed on arm64e!\n");
    }
#endif
    state->__opaque_pc = (void *)pc;
#else
    state->__pc = pc;
#endif
}

uint64_t findSymbol(const char *symbol){
    return (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, symbol), ptrauth_key_asia);
}

#ifdef ENABLE_XPC
xpc_object_t xpc_bootstrap_pipe(void) {
    struct xpc_global_data *xpc_gd = _os_alloc_once_table[1].ptr;
    return xpc_gd->xpc_bootstrap_pipe;
}

bool xpc_object_is_dict(xpc_object_t obj){
    return xpc_get_type(obj) == XPC_TYPE_DICTIONARY;
}
#endif
