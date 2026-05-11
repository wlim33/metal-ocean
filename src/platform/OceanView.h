#pragma once
#import <MetalKit/MetalKit.h>

@interface OceanView : MTKView
- (void)setFrameRenderer:(void (^)(id<MTLCommandBuffer>, MTLRenderPassDescriptor*))block;
@end
