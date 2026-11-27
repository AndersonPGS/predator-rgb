#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

// Acer "gaming interface" GUID (WMID_GUID4 in Linux acer-wmi),
// 7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 in _WDG binary layout.
static const uint8_t kAcerGamingGUID[16] = {
    0xE7, 0xDF, 0x4D, 0x7A, 0x5D, 0x5B, 0xB4, 0x40,
    0x85, 0x95, 0x44, 0x08, 0xE0, 0xCC, 0x7F, 0x56};

class PredatorWMIBridge : public IOService {
    OSDeclareDefaultStructors(PredatorWMIBridge)
public:
    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    // Calls WMxx(instance 0, methodId, input buffer).
    IOReturn callGamingMethod(uint32_t methodId, const uint8_t *in, uint32_t inLen,
                              uint64_t *out, uint32_t *outType);
private:
    IOACPIPlatformDevice *fDevice = nullptr;
    char fMethodName[5] = {0};
    IOLock *fLock = nullptr;
    bool findGamingObject(IOACPIPlatformDevice *dev, char name[5], OSArray *report);
};

class PredatorWMIUserClient : public IOUserClient {
    OSDeclareDefaultStructors(PredatorWMIUserClient)
public:
    bool initWithTask(task_t owningTask, void *securityID, UInt32 type,
                      OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                            IOExternalMethodDispatch *dispatch, OSObject *target,
                            void *reference) override;
private:
    PredatorWMIBridge *fBridge = nullptr;
};
