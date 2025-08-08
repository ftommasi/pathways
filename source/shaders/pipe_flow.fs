#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Custom variables
#define PI 3.14159265358979323846
uniform float uTime = 0.0;

void main() {
    if gl_FragCoord.x < uTimme {
        finalColor = vec4(0,255,255,1.0)
    }else{
        finalColor = vec4(0,255,255,1.0)
    }
}
