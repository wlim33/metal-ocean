#import "bench/CounterSampler.h"
#import "gpu/MetalContext.h"
#import <Metal/Metal.h>

namespace mo {

bool CounterSampler::init(const MetalContext& ctx) {
    id<MTLDevice> dev = (__bridge id<MTLDevice>)ctx.device;
    id<MTLCounterSet> set = nil;
    for (id<MTLCounterSet> s in dev.counterSets) {
        if ([s.name isEqualToString:MTLCommonCounterSetTimestamp]) { set = s; break; }
    }
    if (!set) { supported_ = false; return false; }
    counter_set_ = (__bridge_retained void*)set;

    MTLCounterSampleBufferDescriptor* d = [MTLCounterSampleBufferDescriptor new];
    d.counterSet = set;
    d.storageMode = MTLStorageModeShared;
    d.sampleCount = CAPACITY;
    NSError* err = nil;
    id<MTLCounterSampleBuffer> b = [dev newCounterSampleBufferWithDescriptor:d error:&err];
    if (!b) { supported_ = false; return false; }
    buffer_ = (__bridge_retained void*)b;
    supported_ = true;
    return true;
}

void CounterSampler::resolve(int n, std::vector<PassTiming>& out, const std::vector<std::string>& names) {
    if (!supported_) return;
    id<MTLCounterSampleBuffer> b = (__bridge id<MTLCounterSampleBuffer>)buffer_;
    NSData* data = [b resolveCounterRange:NSMakeRange(0, n)];
    auto* ts = (const MTLCounterResultTimestamp*)data.bytes;
    out.clear();
    for (int i = 0; i + 1 < n && i / 2 < (int)names.size(); i += 2) {
        double ms = (double)(ts[i + 1].timestamp - ts[i].timestamp) / 1e6;
        out.push_back({ names[i / 2], ms });
    }
    next_index = 0;
}
}
