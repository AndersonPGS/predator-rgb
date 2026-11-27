#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

// GUID do "gaming interface" da Acer (WMID_GUID4 no acer-wmi do Linux).
// 7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56 no formato binário do _WDG.
static const uint8_t kAcerGamingGUID[16] = {
    0xE7, 0xDF, 0x4D, 0x7A, 0x5D, 0x5B, 0xB4, 0x40,
    0x85, 0x95, 0x44, 0x08, 0xE0, 0xCC, 0x7F, 0x56};

class PredatorWMIBridge : public IOService {
    OSDeclareDefaultStructors(PredatorWMIBridge)
public:
    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    // Chama WMxx(instância 0, methodId, buffer de entrada).
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
