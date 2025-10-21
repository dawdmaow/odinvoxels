#version 330

// Input from vertex shader
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragPosition;

// Input uniform values
uniform sampler2D texture0;
uniform vec3 cameraPosition;
uniform vec4 fogColor;
uniform float fogDensity;
uniform float fogStart;
uniform float fogEnd;
uniform int fogEnabled;

// Output fragment color
out vec4 finalColor;

void main()
{
    // Sample texture color
    vec4 texColor=texture(texture0,fragTexCoord);
    
    // Apply vertex color to texture first
    vec4 finalTexColor=texColor*fragColor;
    
    // If fog is disabled, just return the texture color
    if(fogEnabled==0){
        finalColor=finalTexColor;
        return;
    }
    
    // Calculate distance from camera to fragment
    float distance=length(cameraPosition-fragPosition);
    
    // Calculate fog factor using linear fog
    // Fog starts at fogStart and becomes fully opaque at fogEnd
    float fogFactor=clamp((fogEnd-distance)/(fogEnd-fogStart),0.,1.);
    
    // If fog factor is very low (almost pure fog), just return fog color directly
    if(fogFactor<.1){
        // Ensure fog color is fully opaque
        finalColor=vec4(fogColor.rgb,1.);
        return;
    }
    
    // Mix texture color with fog color (ensure fog is fully opaque)
    vec4 fogColorOpaque=vec4(fogColor.rgb,1.);
    finalColor=mix(fogColorOpaque,finalTexColor,fogFactor);
}
