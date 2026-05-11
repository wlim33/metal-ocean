#pragma once
#import <MetalKit/MetalKit.h>

@interface OceanView : MTKView <MTKViewDelegate>
- (void)setCommandQueue:(id<MTLCommandQueue>)queue;
- (void)setFrameRenderer:(void (^)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*))block;
@end
