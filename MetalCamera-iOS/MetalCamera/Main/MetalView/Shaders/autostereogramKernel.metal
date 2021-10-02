//
//  autostereogramKernel.metal
//  MetalCamera
//
//  Created by Patrick Aubin on 4/22/21.
//  Copyright © 2021 GS. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

//uniform float max_shift = 0.1;
//uniform int horizontal_repeats = 10;
//uniform bool show_depth = false;
//uniform bool show_dots = true;

uint wang_hash(uint seed)
{
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return seed;
}

kernel void autostereogramKernel(depth2d<float, access::sample> inTexture [[ texture(0) ]],
                          texture2d<float, access::read_write> outTexture [[ texture(1) ]],
                          texture2d<float, access::read> lightHouseTexture [[ texture(2) ]],
                          constant int &showDepth [[buffer(0)]],
                          uint2 gid [[ thread_position_in_grid ]],
                          uint2 threadgroup_position_in_grid [[ threadgroup_position_in_grid ]],
                          uint2 thread_position_in_threadgroup [[ thread_position_in_threadgroup ]],
                          uint2 tpg [[ threads_per_threadgroup ]]) {
    uint lhwidth = lightHouseTexture.get_width();
    uint lhheight = lightHouseTexture.get_height();
    
    if (showDepth) {
        return outTexture.write(inTexture.read({gid.x, gid.y}), gid);
    }

    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
       return;
    }

    if (gid.y < lhheight) {
        outTexture.write(lightHouseTexture.read({gid.x % lhwidth, gid.y}), gid);
    } else {
        int shift = (inTexture.read(gid)) * 0.1 * lhheight;
        outTexture.write(outTexture.read({gid.x, gid.y - lhheight + shift}), gid);
    }
}
