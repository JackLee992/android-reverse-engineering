'use strict';

function safeReadCString(ptrValue) {
    try {
        return ptrValue.isNull() ? null : Memory.readCString(ptrValue);
    } catch (error) {
        return null;
    }
}

function emit(event, message, extra) {
    const payload = extra || {};
    payload.event = event;
    payload.message = message;
    send(payload);
}

let hookCount = 0;
['dlopen', 'android_dlopen_ext'].forEach(function(name) {
    const address = Module.findExportByName(null, name);
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
