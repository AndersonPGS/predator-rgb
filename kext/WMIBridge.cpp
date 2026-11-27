#include "WMIBridge.hpp"
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSString.h>

OSDefineMetaClassAndStructors(PredatorWMIBridge, IOService)
OSDefineMetaClassAndStructors(PredatorWMIUserClient, IOUserClient)

#define LOG(fmt, ...) IOLog("PredatorWMI: " fmt "\n", ##__VA_ARGS__)

// Reads _WDG (GUID -> WMI object table) and looks for the Acer gaming GUID.
bool PredatorWMIBridge::findGamingObject(IOACPIPlatformDevice *dev, char name[5], OSArray *report) {
    OSObject *res = nullptr;
    if (dev->evaluateObject("_WDG", &res) != kIOReturnSuccess || !res) return false;
    OSData *wdg = OSDynamicCast(OSData, res);
    bool found = false;
    if (wdg) {
        const uint8_t *p = (const uint8_t *)wdg->getBytesNoCopy();
        unsigned n = wdg->getLength() / 20;
        for (unsigned i = 0; i < n; i++, p += 20) {
            // entry: GUID[16], object id[2] (or notify id), instance count[1], flags[1]
            if (report) {
                char s[64];
                snprintf(s, sizeof(s),
                    "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X obj=%c%c inst=%u flags=0x%02X",
                    p[3],p[2],p[1],p[0],p[5],p[4],p[7],p[6],p[8],p[9],p[10],p[11],p[12],p[13],p[14],p[15],
                    (p[16] >= 0x20 && p[16] < 0x7f) ? p[16] : '?', (p[17] >= 0x20 && p[17] < 0x7f) ? p[17] : '?',
                    p[18], p[19]);
                OSString *str = OSString::withCString(s);
                if (str) { report->setObject(str); str->release(); }
            }
            // flags bit 1 = method
            if (!found && memcmp(p, kAcerGamingGUID, 16) == 0 && (p[19] & 0x2)) {
                name[0] = 'W'; name[1] = 'M'; name[2] = (char)p[16]; name[3] = (char)p[17]; name[4] = 0;
                found = true;
            }
        }
    }
    res->release();
    return found;
}

IOService *PredatorWMIBridge::probe(IOService *provider, SInt32 *score) {
    IOACPIPlatformDevice *dev = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!dev) return nullptr;
    char name[5];
    if (!findGamingObject(dev, name, nullptr)) return nullptr;
    return IOService::probe(provider, score);
}

bool PredatorWMIBridge::start(IOService *provider) {
    if (!IOService::start(provider)) return false;
    fDevice = OSDynamicCast(IOACPIPlatformDevice, provider);
    OSArray *report = OSArray::withCapacity(8);
    if (!fDevice || !findGamingObject(fDevice, fMethodName, report)) {
        OSSafeReleaseNULL(report);
        return false;
    }
    fDevice->retain();
    fLock = IOLockAlloc();
    setProperty("WDG", report);
    setProperty("GamingMethod", fMethodName);
    report->release();
    LOG("gaming interface em %s", fMethodName);
    registerService();
    return true;
}

void PredatorWMIBridge::stop(IOService *provider) {
    if (fLock) { IOLockFree(fLock); fLock = nullptr; }
    OSSafeReleaseNULL(fDevice);
    IOService::stop(provider);
}

IOReturn PredatorWMIBridge::callGamingMethod(uint32_t methodId, const uint8_t *in, uint32_t inLen,
                                             uint64_t *out, uint32_t *outType) {
    if (!fDevice || inLen > 16) return kIOReturnBadArgument;
    OSNumber *inst = OSNumber::withNumber(0ULL, 32);
    OSNumber *mid = OSNumber::withNumber((unsigned long long)methodId, 32);
    OSData *buf = OSData::withBytes(in, inLen);
    OSObject *params[3] = {inst, mid, buf};
    OSObject *res = nullptr;
    IOLockLock(fLock);
    IOReturn r = fDevice->evaluateObject(fMethodName, &res, params, 3);
    IOLockUnlock(fLock);
    *out = 0; *outType = 0;
    if (res) {
        if (OSNumber *n = OSDynamicCast(OSNumber, res)) { *out = n->unsigned64BitValue(); *outType = 1; }
        else if (OSData *d = OSDynamicCast(OSData, res)) {
            uint64_t v = 0; memcpy(&v, d->getBytesNoCopy(), d->getLength() < 8 ? d->getLength() : 8);
            *out = v; *outType = 2;
        } else *outType = 3;
        res->release();
    }
    OSSafeReleaseNULL(inst); OSSafeReleaseNULL(mid); OSSafeReleaseNULL(buf);
    return r;
}

// ---- user client ----
// Any user may open it, but only keyboard-lighting methods of the Acer gaming
// interface are allowed (see acer-wmi): fan, turbo and overclock methods are refused.
static bool isAllowedMethod(uint32_t id) {
    switch (id) {
    case 2:  // SET_GAMING_LED (zone enable)
    case 4:  // GET_GAMING_LED
    case 5:  // GET_GAMING_SYS_INFO
    case 6:  // SET_GAMING_STATIC_LED (per-zone color)
    case 20: // SET_GAMINGKBBL (mode/effect, 16 bytes)
    case 21: // GET_GAMINGKBBL
        return true;
    default:
        return false;
    }
}

bool PredatorWMIUserClient::initWithTask(task_t owningTask, void *securityID, UInt32 type,
                                         OSDictionary *properties) {
    return IOUserClient::initWithTask(owningTask, securityID, type, properties);
}

bool PredatorWMIUserClient::start(IOService *provider) {
    fBridge = OSDynamicCast(PredatorWMIBridge, provider);
    return fBridge && IOUserClient::start(provider);
}

IOReturn PredatorWMIUserClient::clientClose() {
    terminate();
    return kIOReturnSuccess;
}

// selector 0: scalarInput[0] = methodId; structInput = input buffer (<= 16 bytes);
//             scalarOutput[0] = value, [1] = type (0 none, 1 integer, 2 buffer, 3 other), [2] = IOReturn
IOReturn PredatorWMIUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *a,
                                               IOExternalMethodDispatch *, OSObject *, void *) {
    if (selector != 0 || a->scalarInputCount != 1 || a->scalarOutputCount != 3 || a->structureInputDescriptor)
        return kIOReturnBadArgument;
    if (!isAllowedMethod((uint32_t)a->scalarInput[0])) return kIOReturnNotPermitted;
    if (a->structureInputSize > 16) return kIOReturnBadArgument;
    uint64_t v; uint32_t t;
    IOReturn r = fBridge->callGamingMethod((uint32_t)a->scalarInput[0],
        (const uint8_t *)a->structureInput, a->structureInputSize, &v, &t);
    a->scalarOutput[0] = v; a->scalarOutput[1] = t; a->scalarOutput[2] = (uint64_t)(uint32_t)r;
    return kIOReturnSuccess;
}
