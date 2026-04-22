'use strict';

function safeReadUtf8(ptrValue, length) {
    try {
        return Memory.readUtf8String(ptrValue, length);
    } catch (error) {
        return null;
    }
}

function safeReadU32(ptrValue) {
    try {
        return Memory.readU32(ptrValue);
    } catch (error) {
        return null;
    }
}

function looksLikeDex(begin) {
    const magic = safeReadUtf8(begin, 4);
    return magic === 'dex\n';
}

function emit(event, message, extra) {
    const payload = extra || {};
    payload.event = event;
    payload.message = message;
    send(payload);
}

function enumerateMatchingExports(libName, containsText) {
    try {
        return Module.enumerateExportsSync(libName)
            .filter(exp => exp.type === 'function' && exp.name.indexOf(containsText) !== -1);
    } catch (error) {
        return [];
    }
}

const targetSpecs = [
    {
        lib: 'libart.so',
        exact: [
            '_ZN3art7DexFile10OpenMemoryEPKhjRKNSt3__112basic_stringIcNS3_11char_traitsIcEENS3_9allocatorIcEEEEjPNS_6MemMapEPKNS_10OatDexFileEPS9_',
        ],
        contains: ['OpenMemory'],
        label: 'art-open-memory',
    },
    {
        lib: 'libdexfile.so',
        exact: [
            '_ZN3art13DexFileLoader10OpenCommonEPKhjS2_jRKNSt3__112basic_stringIcNS3_11char_traitsIcEENS3_9allocatorIcEEEEjPKNS_10OatDexFileEbbPS9_NS3_10unique_ptrINS_16DexFileContainerENS3_14default_deleteISH_EEEEPNS0_12VerifyResultE',
        ],
        contains: ['OpenCommon'],
        label: 'art-open-common',
    },
    {
        lib: 'libdexfile.so',
        exact: [],
        contains: ['OpenMemory'],
        label: 'art-open-memory-fallback',
    },
];

const hookedAddresses = {};
const seenDexRegions = {};

function tryHook(spec, address, symbolName) {
    const key = address.toString();
    if (hookedAddresses[key]) {
        return false;
    }

    hookedAddresses[key] = true;
    Interceptor.attach(address, {
        onEnter(args) {
            const begin = args[1];
            if (begin.isNull() || !looksLikeDex(begin)) {
                return;
            }

            const size = safeReadU32(begin.add(0x20));
            if (size === null || size < 0x70 || size > 128 * 1024 * 1024) {
                return;
            }

            const regionKey = begin.toString() + ':' + size;
            if (seenDexRegions[regionKey]) {
                return;
            }
            seenDexRegions[regionKey] = true;

            send(
                {
                    event: 'dex_dump',
                    source: spec.label,
                    lib: spec.lib,
                    symbol: symbolName,
                    base: begin.toString(),
                    size: size,
                },
                Memory.readByteArray(begin, size)
            );
        },
    });

    emit('hook', 'Hooked ' + spec.lib + '!' + symbolName);
    return true;
}

let hookCount = 0;
for (const spec of targetSpecs) {
    for (const exact of spec.exact) {
        const addr = Module.findExportByName(spec.lib, exact);
        if (addr !== null) {
            if (tryHook(spec, addr, exact)) {
                hookCount += 1;
            }
        }
    }

    for (const partial of spec.contains) {
        const matches = enumerateMatchingExports(spec.lib, partial);
        for (const match of matches) {
            if (tryHook(spec, match.address, match.name)) {
                hookCount += 1;
            }
        }
    }
}

if (hookCount === 0) {
    emit('warn', 'No DEX loader hooks were installed. Try a different Android version or add more symbols.');
} else {
    emit('status', 'Installed ' + hookCount + ' DEX loader hook(s).');
}
