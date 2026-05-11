#import "gpu/MetalContext.h"
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>

namespace mo {

static void die(const char* msg) {
    fprintf(stderr, "FATAL: %s\n", msg);
    std::exit(1);
}

MetalContext create_metal_context() {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) die("No Metal-capable GPU detected");

    id<MTLCommandQueue> q = [dev newCommandQueue];
    if (!q) die("Failed to create MTLCommandQueue");

    NSString* lib_path = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"metallib"];
    if (!lib_path) die("default.metallib missing from app bundle");

    NSError* err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:lib_path] error:&err];
    if (!lib) {
        fprintf(stderr, "metallib load error: %s\n", err.localizedDescription.UTF8String);
        die("metallib load failed");
    }

    MetalContext ctx;
    ctx.device = (__bridge_retained void*)dev;
    ctx.queue  = (__bridge_retained void*)q;
    ctx.library = (__bridge_retained void*)lib;
    return ctx;
}

}
