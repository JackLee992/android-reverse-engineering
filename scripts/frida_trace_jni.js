'use strict';

function emit(event, message, extra) {
    const payload = extra || {};
    payload.event = event;
    payload.message = message;
    send(payload);
}

function safeReadCString(ptrValue) {
    try {
        if (ptrValue.isNull()) {
            return null;
        }
        if (typeof ptrValue.readCString === 'function') {
            return ptrValue.readCString();
        }
        return Memory.readCString(ptrValue);
    } catch (error) {
        return null;
    }
}

function moduleOffset(address) {
    let mod = null;
    try {
        if (typeof Process.findModuleByAddress === 'function') {
            mod = Process.findModuleByAddress(address);
        } else {
            mod = Process.getModuleByAddress(address);
        }
    } catch (error) {
        mod = null;
    }
    if (mod === null) {
        return {
            module: null,
            offset: null,
        };
    }

    return {
        module: mod.name,
        offset: '0x' + address.sub(mod.base).toString(16),
    };
}

function findRegisterNatives() {
    const candidates = ['libart.so', 'libartd.so'];
    for (const lib of candidates) {
        try {
            let symbols = null;
            if (typeof Module.enumerateSymbolsSync === 'function') {
                symbols = Module.enumerateSymbolsSync(lib);
            } else {
                symbols = Process.getModuleByName(lib).enumerateSymbols();
            }
            for (const symbol of symbols) {
                if (symbol.name.indexOf('RegisterNatives') === -1) {
                    continue;
                }
                if (symbol.name.indexOf('CheckJNI') !== -1) {
                    continue;
                }
                return {
                    lib: lib,
                    name: symbol.name,
                    address: symbol.address,
                };
            }
        } catch (error) {
        }
    }
    return null;
}

const target = findRegisterNatives();
if (target === null) {
    emit('warn', 'RegisterNatives hook point not found.');
} else {
    Interceptor.attach(target.address, {
        onEnter(args) {
            const methods = args[2];
            const count = args[3].toInt32();
            const stride = Process.pointerSize * 3;

            for (let index = 0; index < count; index += 1) {
                const entry = methods.add(index * stride);
                const namePtr = typeof entry.readPointer === 'function' ? entry.readPointer() : Memory.readPointer(entry);
                const sigSlot = entry.add(Process.pointerSize);
                const fnSlot = entry.add(Process.pointerSize * 2);
                const sigPtr = typeof sigSlot.readPointer === 'function' ? sigSlot.readPointer() : Memory.readPointer(sigSlot);
                const fnPtr = typeof fnSlot.readPointer === 'function' ? fnSlot.readPointer() : Memory.readPointer(fnSlot);
                const location = moduleOffset(fnPtr);

                emit('jni', 'RegisterNatives ' + (safeReadCString(namePtr) || '<unnamed>'), {
                    hook: target.name,
                    index: index,
                    name: safeReadCString(namePtr),
                    signature: safeReadCString(sigPtr),
                    fnPtr: fnPtr.toString(),
                    module: location.module,
                    offset: location.offset,
                    classPtr: args[1].toString(),
                });
            }
        },
    });
    emit('hook', 'Hooked ' + target.lib + '!' + target.name);
}
