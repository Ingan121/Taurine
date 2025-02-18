//
//  nvramutils.h
//  Chimera
//
//  Created by CoolStar on 9/3/19.
//  Copyright © 2019 Electra Team. All rights reserved.
//

#ifndef nvramutils_h
#include <stdbool.h>
#include <stdint.h>
#include <mach/mach.h>

#define nvramutils_h

typedef struct {
    uint64_t key;
    uint64_t value;
} dict_entry_t;

uint64_t lookup_key_in_dicts(dict_entry_t *dict, uint32_t count, uint64_t key);

void iterate_keys_in_dict(dict_entry_t *os_dict_entries, uint32_t count, void (^callback)(uint64_t key, uint64_t value));

bool isArm64e(void);
uint64_t rk64ptr(uint64_t where);
uint64_t signPtr(uint64_t data, uint64_t key);
uint64_t getFp(arm_thread_state64_t state);
uint64_t getLr(arm_thread_state64_t state);
uint64_t getSp(arm_thread_state64_t state);
uint64_t getPc(arm_thread_state64_t state);
uint64_t findSymbol(const char *symbol);
void setLr(arm_thread_state64_t *state, uint64_t lr);
void setPc(arm_thread_state64_t *state, uint64_t pc);
void amfid_test(mach_port_t amfid_port);

#ifdef ENABLE_XPC
#include <xpc/xpc.h>
// os_alloc_once_table:
//
// Ripped this from XNU's libsystem
#define OS_ALLOC_ONCE_KEY_MAX    100

struct _os_alloc_once_s {
    long once;
    void *ptr;
};

extern struct _os_alloc_once_s _os_alloc_once_table[];

// XPC sets up global variables using os_alloc_once. By reverse engineering
// you can determine the values. The only one we actually need is the fourth
// one, which is used as an argument to xpc_pipe_routine

struct xpc_global_data {
    uint64_t    a;
    uint64_t    xpc_flags;
    mach_port_t    task_bootstrap_port;  /* 0x10 */
#ifndef _64
    uint32_t    padding;
#endif
    xpc_object_t    xpc_bootstrap_pipe;   /* 0x18 */
    // and there's more, but you'll have to wait for MOXiI 2 for those...
    // ...
};

xpc_object_t xpc_bootstrap_pipe(void);
bool xpc_object_is_dict(xpc_object_t obj);
#endif

#endif /* nvramutils_h */
