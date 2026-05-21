'use strict';

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

function findGlobalExport(name) {
    if (typeof Module.findGlobalExportByName === 'function') {
        return Module.findGlobalExportByName(name);
    }
    if (typeof Module.getGlobalExportByName === 'function') {
        try {
            return Module.getGlobalExportByName(name);
        } catch (error) {
            return null;
        }
    }
    if (typeof Module.findExportByName === 'function') {
        return Module.findExportByName(null, name);
    }
    return null;
}

function emit(event, message, extra) {
    const payload = extra || {};
    payload.event = event;
    payload.message = message;
    send(payload);
}

let hookCount = 0;
['dlopen', 'android_dlopen_ext'].forEach(function(name) {
    const address = findGlobalExport(name);
    if (address === null) {
        return;
    }

    hookCount += 1;
    Interceptor.attach(address, {
        onEnter(args) {
            this.api = name;
            this.path = safeReadCString(args[0]) || '<unknown>';
        },
        onLeave(retval) {
            emit('load', this.api + ' loaded ' + this.path, {
                api: this.api,
                path: this.path,
                handle: retval.toString(),
            });
        },
    });
    emit('hook', 'Hooked ' + name);
});

if (hookCount === 0) {
    emit('warn', 'No dlopen hooks were installed.');
} else {
    emit('status', 'Installed ' + hookCount + ' library-load hook(s).');
}
