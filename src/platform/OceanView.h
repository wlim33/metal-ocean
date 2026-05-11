#pragma once
#import <MetalKit/MetalKit.h>
#include "platform/InputBridge.h"

@interface OceanView : MTKView <MTKViewDelegate>
- (void)setFrameRenderer:(void (^)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*))block;
- (void)setCommandQueue:(id<MTLCommandQueue>)queue;
- (void)setInputBridge:(mo::InputBridge*)bridge;
@end
