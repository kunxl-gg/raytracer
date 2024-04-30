#include <bits/stdc++.h>
#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <iostream>
#include <vector>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb/stb_image_write.h>
#include <glm/gtc/type_ptr.hpp>  // For glm::value_ptr
#include <glm/glm.hpp>
#include <imgui/imgui.h>
#include <imgui/imgui_impl_glfw.h>
#include <imgui/imgui_impl_opengl3.h>

#include <utils/shader.hpp>

void processInput(GLFWwindow *window, unsigned int fb1, unsigned int fb2,
                  unsigned int &samples);
void render(Shader &shader, float vertices[], unsigned int VAO,
            unsigned int vertLen, unsigned int samples);
unsigned int createFramebuffer(unsigned int *texture);
void saveImage(char *filepath, GLFWwindow *w);

// settings
unsigned int SCR_SIZE = 800;
unsigned int SAMPLES = 6000;
char *PATH = "../image.png";

glm::vec3 cameraPos = glm::vec3(0, 0, 15);
glm::vec3 cameraFront = glm::vec3(0.0f, 0.0f, -1.0f);

glm::vec3 leftWallColor(1.0f, 1.0f, 0.0f);  // Default 
int leftWallMaterial = 0;
glm::vec3 rightWallColor(0.0f, 1.0f, 1.0f);  // Default
int rightWallMaterial = 0;
glm::vec3 backWallColor(0.5f, 0.5f, 0.5f);  // Default
int backWallMaterial = 0;
glm::vec3 upWallColor(0.5f, 0.5f, 0.5f);  // Default
int upWallMaterial = 0;
glm::vec3 cuboidColor(0.2f, 0.3f, 1.0f);
int cuboidMaterial = 0;
glm::vec3 pyramidColor(0.0f, 0.0f, 1.0f);
int pyramidMaterial = 0;

int main() {

  // glfw: initialize and configure
  // ------------------------------
  glfwInit();
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

  srand(time(NULL));
#ifdef _APPLE_
  glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif
  // glfw window creation
  // --------------------

  GLFWmonitor *primaryMonitor = glfwGetPrimaryMonitor();
  const GLFWvidmode *mode = glfwGetVideoMode(primaryMonitor);

  GLFWwindow *window =
      glfwCreateWindow(SCR_SIZE, SCR_SIZE, "Ray Tracer", NULL, NULL);
  if (window == NULL) {
    std::cout << "Failed to create GLFW window" << std::endl;
    glfwTerminate();
    return -1;
  }
  glfwMakeContextCurrent(window);

  GLFWwindow *imguiWindow = glfwCreateWindow(600, 600, "InGui Window", NULL, NULL);
  if (imguiWindow == NULL) {
    std::cout << "Failed to create ImGui window" << std::endl;
    glfwTerminate();
    return -1;
  }

  // glad: load all OpenGL function pointers
  // ---------------------------------------
  if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
    std::cout << "Failed to initialize GLAD" << std::endl;
    return -1;
  }

  // ImGui initialization
  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO &io = ImGui::GetIO();
  ImGui_ImplGlfw_InitForOpenGL(imguiWindow, true);
  ImGui_ImplOpenGL3_Init("#version 330");

  // ImGui::StyleColorsDark(); // Set ImGui style

  //
  // Build and compile our shader zprogram
  // Note: Paths to shader files should be relative to location of executable
  Shader shader("shaders/vert.glsl", "shaders/frag.glsl");
  Shader copyShader("shaders/vert.glsl", "shaders/copy.glsl");
  Shader dispShader("shaders/vert.glsl", "shaders/disp.glsl");

  float vertices[] = {
      -1, -1, -1, +1, +1, +1, -1, -1, +1, +1, +1, -1,
  };

  unsigned int VBO, VAO;
  glGenVertexArrays(1, &VAO);
  glGenBuffers(1, &VBO);

  glBindVertexArray(VAO);

  glBindBuffer(GL_ARRAY_BUFFER, VBO);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

  // Position attribute
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), (void *)0);
  glEnableVertexAttribArray(0);

  // Create two needed framebuffers
  unsigned int fbTexture1;
  unsigned int fb1 = createFramebuffer(&fbTexture1);
  unsigned int fbTexture2;
  unsigned int fb2 = createFramebuffer(&fbTexture2);

  unsigned int samples = 0;

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, fbTexture1);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, fbTexture2);

  // Store start time
  double t0 = glfwGetTime();
  glDisable(GL_DEPTH_TEST);
  while (!glfwWindowShouldClose(window) && !glfwWindowShouldClose(imguiWindow)) {
    glfwMakeContextCurrent(window);
    // input
    // -----
    processInput(window, fb1, fb2, samples);

    // Render pass on fb1
    glBindFramebuffer(GL_FRAMEBUFFER, fb1);
    render(shader, vertices, VAO, sizeof(vertices), samples);

    // Copy to fb2
    glBindFramebuffer(GL_FRAMEBUFFER, fb2);
    glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    unsigned int ID = copyShader.ID;
    copyShader.use();
    copyShader.setInt("fb", 0);
    glUniform2f(glGetUniformLocation(ID, "resolution"), SCR_SIZE, SCR_SIZE);
    glBindVertexArray(VAO);
    glDrawArrays(GL_TRIANGLES, 0, sizeof(vertices) / 3);
    samples += 1;

    // Render to screen
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    dispShader.use();
    ID = dispShader.ID;

    // Render from fb2 texture
    dispShader.setFloat("exposure", 5);
    dispShader.setInt("screenTexture", 0);
    dispShader.setInt("samples", samples);

    glUniform2f(glGetUniformLocation(ID, "resolution"), SCR_SIZE, SCR_SIZE);
    glBindVertexArray(VAO);
    glDrawArrays(GL_TRIANGLES, 0, sizeof(vertices) / 3);

    // glfw: swap buffers and poll IO events (keys pressed/released, mouse moved
    // etc.)
    // -------------------------------------------------------------------------------
    glfwSwapBuffers(window);

    // Render ImGui in the ImGui window
    glfwMakeContextCurrent(imguiWindow);

    // // Start ImGui frame
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    // ImGui window for controlling wall color and material
    ImGui::Begin("Controls");
    ImGui::Text("Control Panel");

    // Collapsible section for Left Wall settings
    if (ImGui::CollapsingHeader("Left Wall Settings")) {
        ImGui::Text("Adjust Left Wall Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &leftWallColor.r);
        ImGui::InputFloat("Green", &leftWallColor.g);
        ImGui::InputFloat("Blue", &leftWallColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &leftWallMaterial);
    }
    // Collapsible section for Right Wall settings
    if (ImGui::CollapsingHeader("Right Wall Settings")) {
        ImGui::Text("Adjust Right Wall Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &rightWallColor.r);
        ImGui::InputFloat("Green", &rightWallColor.g);
        ImGui::InputFloat("Blue", &rightWallColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &rightWallMaterial);
    }
    // Collapsible section for Back Wall settings
    if (ImGui::CollapsingHeader("Back Wall Settings")) {
        ImGui::Text("Adjust Back Wall Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &backWallColor.r);
        ImGui::InputFloat("Green", &backWallColor.g);
        ImGui::InputFloat("Blue", &backWallColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &backWallMaterial);
    }
    // Collapsible section for Up Wall settings
    if (ImGui::CollapsingHeader("Up Wall Settings")) {
        ImGui::Text("Adjust Up Wall Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &upWallColor.r);
        ImGui::InputFloat("Green", &upWallColor.g);
        ImGui::InputFloat("Blue", &upWallColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &upWallMaterial);
    }

    // Collapsible section for Cuboid Wall settings
    if (ImGui::CollapsingHeader("Cuboid Settings")) {
        ImGui::Text("Adjust Cuboid Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &cuboidColor.r);
        ImGui::InputFloat("Green", &cuboidColor.g);
        ImGui::InputFloat("Blue", &cuboidColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &cuboidMaterial);
    }

    // Collapsible section for Pyramid Wall settings
    if (ImGui::CollapsingHeader("Pyramid Settings")) {
        ImGui::Text("Adjust Pyramid Color and Material");

        // Input fields for color components
        ImGui::InputFloat("Red", &pyramidColor.r);
        ImGui::InputFloat("Green", &pyramidColor.g);
        ImGui::InputFloat("Blue", &pyramidColor.b);
        // Input field for the material type
        ImGui::InputInt("Material Type", &pyramidMaterial);
    }

    // End the ImGui window
    ImGui::End();

    // Render ImGui
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

    glfwSwapBuffers(imguiWindow);


    glfwPollEvents();

    std::cout << "Progress: " << samples << "/" << SAMPLES << " samples"
              << '\r';
  }

  // Write to file
  std::cout << "INFO::Output image written to " << PATH << std::endl;
  saveImage(PATH, window);

  std::cout << "INFO::Time taken: " << glfwGetTime() - t0 << "s" << std::endl;

  // Cleanup ImGui
  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplGlfw_Shutdown();
  ImGui::DestroyContext();

  // Deallocate all resources once they've outlived their purpose
  glDeleteVertexArrays(1, &VAO);
  glDeleteBuffers(1, &VBO);
  glDeleteFramebuffers(1, &fb1);
  glDeleteFramebuffers(1, &fb2);
  glDeleteTextures(1, &fbTexture1);
  glDeleteTextures(1, &fbTexture2);

  // glfw: terminate, clearing all previously allocated GLFW resources.
  // ------------------------------------------------------------------
  glfwDestroyWindow(window);
  glfwDestroyWindow(imguiWindow);
  glfwTerminate();
  return 0;
}
// Function to clear the contents of the framebuffers
void clearFramebuffers(unsigned int fb1, unsigned int fb2) {
    glBindFramebuffer(GL_FRAMEBUFFER, fb1);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindFramebuffer(GL_FRAMEBUFFER, fb2);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindFramebuffer(GL_FRAMEBUFFER, 0); // Bind the default framebuffer
}

// process all input: query GLFW whether relevant keys are pressed/released this
// frame and react accordingly
// ---------------------------------------------------------------------------------------------------------
void processInput(GLFWwindow* window, unsigned int fb1, unsigned int fb2, unsigned int& samples) {
    if (glfwGetKey(window, GLFW_KEY_X) == GLFW_PRESS) {
        glfwSetWindowShouldClose(window, true);
    }
    if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS) {
        cameraPos += 0.05f * cameraFront;
    } else if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS) {
        cameraPos -= 0.05f * cameraFront;
    }
    if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS) {
        cameraPos += glm::normalize(glm::cross(cameraFront, glm::vec3(0.0f, 1.0f, 0.0f))) * 0.05f;
    } else if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS) {
        cameraPos -= glm::normalize(glm::cross(cameraFront, glm::vec3(0.0f, 1.0f, 0.0f))) * 0.05f;
    }
    
    // Clear the framebuffers and reset samples count when 'S' or 'W' is pressed
    if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS ||
        glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS || glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS) {
        clearFramebuffers(fb1, fb2);
        samples = 0; // Reset the sample count
    }
}

void render(Shader &shader, float vertices[], unsigned int VAO,
            unsigned int vertLen, unsigned int samples) {
  // render
  // ------
  glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  // render the shader
  shader.use();

  // Set uniforms
  unsigned int ID = shader.ID;
  // Pass the wall color to the shader
  shader.setVec3("leftWallColor", leftWallColor.r, leftWallColor.g, leftWallColor.b);
  shader.setInt("leftWallMaterial", leftWallMaterial);
  shader.setVec3("rightWallColor", rightWallColor.r, rightWallColor.g, rightWallColor.b);
  shader.setInt("rightWallMaterial", rightWallMaterial);
  shader.setVec3("backWallColor", backWallColor.r, backWallColor.g, backWallColor.b);
  shader.setInt("backWallMaterial", backWallMaterial);
  shader.setVec3("upWallColor", upWallColor.r, upWallColor.g, upWallColor.b);
  shader.setInt("upWallMaterial", upWallMaterial);
  shader.setVec3("cuboidColor", cuboidColor.r, cuboidColor.g, cuboidColor.b);
  shader.setInt("cuboidMaterial", cuboidMaterial);
  shader.setVec3("pyramidColor", pyramidColor.r, pyramidColor.g, pyramidColor.b);
  shader.setInt("pyramidMaterial", pyramidMaterial);

  shader.setInt("prevFrame", 1);

  shader.setInt("samples", samples);
  shader.setInt("numBounces", 8);
  shader.setFloat("time", glfwGetTime());
  shader.setInt("seedInit", rand());

  // Light properties
  shader.setFloat("intensity", 1.0);

  // Camera properties
  shader.setFloat("focalDistance", 2);
  shader.setVec3("cameraPos", cameraPos.x, cameraPos.y, cameraPos.z);
  glUniform2f(glGetUniformLocation(ID, "resolution"), SCR_SIZE, SCR_SIZE);

  // Checkerboard
  shader.setFloat("checkerboard", 2);

  glBindVertexArray(VAO);
  glDrawArrays(GL_TRIANGLES, 0, vertLen / 3);
}

unsigned int createFramebuffer(unsigned int *texture) {
  // Create a framebuffer to write output to
  unsigned int fb;
  glGenFramebuffers(1, &fb);
  glBindFramebuffer(GL_FRAMEBUFFER, fb);

  // Create a texture to write to
  glGenTextures(1, texture);
  glBindTexture(GL_TEXTURE_2D, *texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, SCR_SIZE, SCR_SIZE, 0, GL_RGBA,
               GL_FLOAT, NULL);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);

  // Attach texture to framebuffer
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         *texture, 0);

  // Check if framebuffer is ready to be written to
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    std::cout << "ERROR::FRAMEBUFFER:: Framebuffer is not complete!"
              << std::endl;
  }

  return fb;
}

void saveImage(char *filepath, GLFWwindow *w) {
  int width, height;
  glfwGetFramebufferSize(w, &width, &height);
  GLsizei nrChannels = 3;
  GLsizei stride = nrChannels * width;
  stride += (stride % 4) ? (4 - stride % 4) : 0;
  GLsizei bufferSize = stride * height;
  std::vector<char> buffer(bufferSize);
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
  glReadBuffer(GL_FRONT);
  glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, buffer.data());
  stbi_flip_vertically_on_write(true);
  stbi_write_png(filepath, width, height, nrChannels, buffer.data(), stride);
}