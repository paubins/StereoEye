//  Creating a Vertex Shader
//
//  Based on Step 4 of Ray's Tutorial
//  http://www.raywenderlich.com/77488/ios-8-metal-tutorial-swift-getting-started
//

#include <metal_stdlib>
using namespace metal;


// Step 4:
vertex float4 basic_vertex(
                           const device packed_float3* vertex_array [[ buffer(0) ]],
                           unsigned int vid [[ vertex_id ]]) {
    return float4(vertex_array[vid], 1.0);
}

// Step 5:
// After the vertex shader completes, another shader is called for each fragment (think pixel) on the screen: the fragment shader.
// half4 is more memory efficient than float4 because you are writing to less GPU memory
fragment half4 basic_fragment() {
    return half4(1.0);
}
