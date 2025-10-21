#version 330

// Input vertex attributes
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

// Input uniform values
uniform mat4 mvp;
uniform mat4 matModel;
uniform vec4 colDiffuse;

// Output vertex attributes (to fragment shader)
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragPosition;

void main()
{
    // Send vertex attributes to fragment shader
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor*colDiffuse;
    
    // Calculate world position for fog distance calculation
    fragPosition = vec3(matModel*vec4(vertexPosition, 1.0));
    
    // Calculate final vertex position
    gl_Position = mvp*vec4(vertexPosition, 1.0);
}

