'use strict';

function emit(event, message, extra) {
    const payload = extra || {};
    payload.event = event;
    payload.message = message;
    send(payload);
}

function safeReadCString(ptrValue) {
    try {
        return ptrValue.isNull() ? null : Memory.readCString(ptrValue);
    } catch (error) {
        return null;
    }
}

function moduleOffset(address) {
    const mod = Process.findModuleByAddress(address);
    if (!mod) {
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
            const symbols = Module.enumerateSymbolsSync(lib);
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
                const namePtr = Memory.readPointer(entry);
                const sigPtr = Memory.readPointer(entry.add(Process.pointerSize));
                const fnPtr = Memory.readPointer(entry.add(Process.pointerSize * 2));
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
