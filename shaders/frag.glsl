#version 330

// #define DEBUG_ALBEDO
// #define DEBUG_NORMALS
// #define DEBUG_SINGLE
#define USE_NEE
#define USE_VNDF
// BVH is actually slower
// #define USE_BVH

out vec4 fragColor;

// Previous frame
uniform sampler2D prevFrame;

// Render settings
uniform int numBounces;
uniform int seedInit;

uniform vec3 cameraPos;

// Light properties
uniform float intensity;

// Camera properties
uniform vec2 resolution;
uniform float focalDistance;

// Checkerboard pattern
// Set to -ve to disable
uniform float checkerboard;

// Constants
const float pi = 3.14159265;
const float inf = 99999999.0;
const float eps = 1e-5;

int seed = 0;
int flatIdx = 0;

// Primitives
struct Ray {
  vec3 origin;
  vec3 dir;
};

struct Sphere {
  vec3 center;
  float radius;
};

// Only support axis aligned for now
struct Cuboid {
  vec3 minPos;
  vec3 maxPos;
};

struct Rectangle {
  // normal = cross(dirx, diry)
  // d = dot(normal, center)
  vec4 plane;  // vec4(normal, d)
  vec3 center;
  vec3 dirX;
  vec3 dirY;
  float lenX;
  float lenY;
};

struct Triangle {
  vec3 v0;
  vec3 v1;
  vec3 v2;
};

struct Material {
  int type;  // 0 for reflective, 1 for refractive, 2 for emmisive, 3 for
             // checkerboard
  float roughness;
  vec3 color;
  float ior;
};

#ifdef USE_BVH
struct BVHNode {
  Cuboid bbox;
  int left;   // Index of left node in array
  int right;  // Index of right node in array
};
#endif

// New uniform for the left wall color
uniform vec3 leftWallColor;
uniform int leftWallMaterial;

uniform vec3 rightWallColor;
uniform int rightWallMaterial;

uniform vec3 backWallColor;
uniform int backWallMaterial;

uniform vec3 upWallColor;
uniform int upWallMaterial;

// Walls
vec4[5] walls = vec4[5](vec4(0, 1, 0, 5), vec4(0, -1, 0, 5), vec4(1, 0, 0, 5),
                        vec4(-1, 0, 0, 5), vec4(0, 0, 1, 5));
Material[5] wallsMat = Material[5](
    Material(checkerboard < 0 ? 0 : 3, 0.05, vec3(0.5, 0.5, 0.5), 0),
    Material(upWallMaterial, 0.9, upWallColor, 0), // up
    Material(leftWallMaterial, 0.2, leftWallColor, 0),
    Material(rightWallMaterial, 0.2, rightWallColor, 0),
    Material(backWallMaterial, 0.9, backWallColor, 0)); // back

// Sphere
Sphere sphere = Sphere(vec3(0, -3.7, 3), 1.3);
Material sphereMat = Material(1, 0.1, vec3(1.0, 1.0, 1.0), 1.4);

uniform vec3 cuboidColor;
uniform int cuboidMaterial;

// Cuboid
Cuboid cuboid = Cuboid(vec3(-4, -5, -2), vec3(-1, 1, 1));
Material cuboidMat = Material(cuboidMaterial, 0.8, cuboidColor, 0);

uniform vec3 pyramidColor;
uniform int pyramidMaterial;

// Pyramid
vec3 pyramidCenter = vec3(2.5, -5, -2);
vec3 pyramidNorm = vec3(0, 1, 0);
float pyramidHeight = 4;
float pyramidLength = 3;
vec3 pyramidTip = pyramidCenter + pyramidHeight * pyramidNorm;
vec3 quad0 = vec3(1, 0, 1);
vec3 quad1 = vec3(1, 0, -1);
vec3 quad2 = vec3(-1, 0, -1);
vec3 quad3 = vec3(-1, 0, 1);
Triangle[4] pyrTris =
    Triangle[4](Triangle(pyramidTip, pyramidCenter + quad0 * pyramidLength / 2,
                         pyramidCenter + quad1 * pyramidLength / 2),
                Triangle(pyramidTip, pyramidCenter + quad1 * pyramidLength / 2,
                         pyramidCenter + quad2 * pyramidLength / 2),
                Triangle(pyramidTip, pyramidCenter + quad2 * pyramidLength / 2,
                         pyramidCenter + quad3 * pyramidLength / 2),
                Triangle(pyramidTip, pyramidCenter + quad3 * pyramidLength / 2,
                         pyramidCenter + quad0 * pyramidLength / 2));
Rectangle pyrBase = Rectangle(
    vec4(-pyramidNorm, -dot(-pyramidNorm, pyramidCenter)), pyramidCenter,
    vec3(1, 0, 0), vec3(0, 0, 1), pyramidLength, pyramidLength);
Material pyramidMat = Material(pyramidMaterial, 0.01, pyramidColor, 0);

// Light
Rectangle lightRect = Rectangle(vec4(0, -1, 0, 5 - eps), vec3(0, 5 - eps, 0),
                                vec3(1, 0, 0), vec3(0, 0, 1), 5, 5);
Material lightMat = Material(2, 0, vec3(2), 0);

#ifdef USE_BVH
// BVH Tree (stored in an array)
Cuboid sphereBbox =
    Cuboid(sphere.center - sphere.radius, sphere.center + sphere.radius);
Cuboid pyramidBbox = Cuboid(pyramidCenter - quad0 * pyramidCenter,
                            pyramidTip + quad0 * pyramidCenter);
Cuboid pyrCubBbox = Cuboid(min(pyramidBbox.minPos, cuboid.minPos),
                           max(pyramidBbox.maxPos, cuboid.maxPos));
Cuboid rootBbox = Cuboid(min(pyrCubBbox.minPos, sphereBbox.minPos),
                         max(pyrCubBbox.maxPos, sphereBbox.maxPos));
BVHNode[5] bvhTree = BVHNode[5](
    // Root
    BVHNode(rootBbox, 1, 2),
    // Sphere
    BVHNode(sphereBbox, -1, -1),
    // Pyramid and Cuboid
    BVHNode(pyrCubBbox, 3, 4),
    // Pyramid
    BVHNode(pyramidBbox, -2, -2),
    // Cuboid
    BVHNode(cuboid, -3, -3));
#endif

// Random number generator
void encryptTea(inout uvec2 arg) {
  uvec4 key = uvec4(0xa341316c, 0xc8013ea4, 0xad90777d, 0x7e95761e);
  uint v0 = arg[0], v1 = arg[1];
  uint sum = 0u;
  uint delta = 0x9e3779b9u;

  for (int i = 0; i < 32; i++) {
    sum += delta;
    v0 += ((v1 << 4) + key[0]) ^ (v1 + sum) ^ ((v1 >> 5) + key[1]);
    v1 += ((v0 << 4) + key[2]) ^ (v0 + sum) ^ ((v0 >> 5) + key[3]);
  }
  arg[0] = v0;
  arg[1] = v1;
}

vec2 getRandom() {
  uvec2 arg = uvec2(flatIdx, seed++);
  encryptTea(arg);
  return fract(vec2(arg) / vec2(0xffffffffu));
}

float clampDot(vec3 a, vec3 b, bool zero) {
  return max(dot(a, b), zero ? 0 : eps);
}

mat3 constructONBFrisvad(vec3 normal) {
  mat3 ret;
  ret[1] = normal;
  if (normal.z < -0.999805696) {
    ret[0] = vec3(0.0, -1.0, 0.0);
    ret[2] = vec3(-1.0, 0.0, 0.0);
  } else {
    float a = 1.0 / (1.0 + normal.z);
    float b = -normal.x * normal.y * a;
    ret[0] = vec3(1.0 - normal.x * normal.x * a, b, -normal.x);
    ret[2] = vec3(b, 1.0 - normal.y * normal.y * a, -normal.y);
  }
  return ret;
}

// Camera is placed at (0, 0, 0) looking at (0, 0, -1)
Ray genRay(vec2 rng) {
  Ray ray;

  vec2 xy = 2.0 * gl_FragCoord.xy / resolution - vec2(1.0);

  ray.origin = cameraPos;
  ray.dir = normalize(
      vec3(xy + rng.x * dFdx(xy) + rng.y * dFdy(xy), 15 - focalDistance) -
      // vec3(xy, 15 - focalDistance) -
      ray.origin);

  return ray;
}

// Intersection
bool intersectPlane(Ray ray, vec4 plane, out float t, out vec3 normal) {
  t = -dot(plane, vec4(ray.origin, 1.0)) / dot(plane.xyz, ray.dir);
  normal = plane.xyz;
  return t > 0.0;
}

bool intersectRectangle(Ray ray, Rectangle rect, out float t, out vec3 normal) {
  // Check if on correct side of plane
  if (!intersectPlane(ray, rect.plane, t, normal)) {
    return false;
  }
  // Check if lies inside rectangle
  vec3 newPos = ray.origin + ray.dir * t;
  newPos = newPos - rect.center;
  float projX = dot(newPos, rect.dirX);
  float projY = dot(newPos, rect.dirY);
  if (abs(projX) < rect.lenX / 2 && abs(projY) < rect.lenY / 2) {
    return true;
  }
  return false;
}

bool intersectCuboid(Ray ray, Cuboid cuboid, out float t, out vec3 normal) {
  float tMin = 0;
  float tMax = inf;

  vec3 div = 1.0 / ray.dir;
  vec3 t1 = (cuboid.minPos - ray.origin) * div;
  vec3 t2 = (cuboid.maxPos - ray.origin) * div;

  vec3 tMin2 = min(t1, t2);
  vec3 tMax2 = max(t1, t2);

  tMin = max(max(tMin2.x, tMin2.y), max(tMin2.z, tMin));
  tMax = min(min(tMax2.x, tMax2.y), min(tMax2.z, tMax));
  t = tMin;

  vec3 center = (cuboid.minPos + cuboid.maxPos) / 2;
  normal = ray.origin + t * ray.dir - center;

  vec3 an = abs(normal) / (cuboid.maxPos - cuboid.minPos);
  if (an.x > an.y && an.x > an.z) {
    normal = vec3(normal.x > 0 ? 1 : -1, 0, 0);
  }
  if (an.y > an.x && an.y > an.z) {
    normal = vec3(0, normal.y > 0 ? 1 : -1, 0);
  }
  if (an.z > an.x && an.z > an.y) {
    normal = vec3(0, 0, normal.z > 0 ? 1 : -1);
  }

  return tMin < tMax;
}

bool intersectSphere(Ray ray, Sphere sphere, out float t, out vec3 normal) {
  vec3 oc = ray.origin - sphere.center;
  float b = dot(oc, ray.dir);
  float c = dot(oc, oc) - sphere.radius * sphere.radius;
  float disc = b * b - c;
  if (disc < 0.0) {
    return false;
  }
  disc = sqrt(disc);
  t = -b - disc;
  t = t > 0 ? t : -b + disc;
  normal = normalize(ray.origin + ray.dir * t - sphere.center);
  return t > 0;
}

bool intersectTriangle(Ray ray, Triangle tri, out float t, out vec3 normal) {
  vec3 v1v0 = tri.v1 - tri.v0;
  vec3 v2v0 = tri.v2 - tri.v0;
  vec3 rov0 = ray.origin - tri.v0;
  normal = cross(v1v0, v2v0);
  vec3 q = cross(rov0, -ray.dir);
  float d = 1.0 / dot(ray.dir, -normal);
  float u = d * dot(-q, v2v0);
  float v = d * dot(q, v1v0);
  t = d * dot(normal, rov0);
  normal = normalize(normal);
  if (u < 0.0 || v < 0.0 || (u + v) > 1.0 || t < 0.0) {
    return false;
  }
  return true;
}

#ifdef USE_BVH
bool intersect(Ray ray, bool shadow, out float t, out Material mat,
               out vec3 normal) {
  bool intersect = false;
  t = inf;
  float tmpT;
  vec3 tmpNorm;

  int bvhStack[5] = int[5](0, -1, -1, -1, -1);
  // Root is already present
  int front = 0;
  while (front >= 0) {
    // Pop from stack
    BVHNode node = bvhTree[bvhStack[front]];
    front -= 1;

    if (intersectCuboid(ray, node.bbox, tmpT, tmpNorm)) {
      if (node.left < 0) {
        switch (node.left) {
          case -1:
            // Sphere
            if (intersectSphere(ray, sphere, tmpT, tmpNorm)) {
              intersect = true;
              if (tmpT < t) {
                t = tmpT;
                mat = sphereMat;
                normal = tmpNorm;
              }
            }
            break;
          case -2:
            // Pyramid
            for (int i = 0; i < 4; i += 1) {
              if (intersectTriangle(ray, pyrTris[i], tmpT, tmpNorm)) {
                intersect = true;
                if (tmpT < t) {
                  t = tmpT;
                  mat = pyramidMat;
                  normal = tmpNorm;
                }
              }
            }
            if (intersectRectangle(ray, pyrBase, tmpT, tmpNorm)) {
              intersect = true;
              if (tmpT < t) {
                t = tmpT;
                mat = pyramidMat;
                normal = tmpNorm;
              }
            }
            break;
          case -3:
            // Cuboid: Special case as BVH for it is same
            intersect = true;
            if (tmpT < t) {
              t = tmpT;
              mat = cuboidMat;
              normal = tmpNorm;
            }
            break;
        }
      } else {
        bvhStack[++front] = node.left;
        bvhStack[++front] = node.right;
      }
    }
  }

  // Light
  if (intersectRectangle(ray, lightRect, tmpT, tmpNorm)) {
    intersect = true;
    if (tmpT < t) {
      t = tmpT;
      mat = lightMat;
      normal = tmpNorm;
    }
  }

  // Walls don't cast shadows
  if (!shadow) {
    for (int i = 0; i < 5; i += 1) {
      if (intersectPlane(ray, walls[i], tmpT, tmpNorm)) {
        intersect = true;
        if (tmpT < t) {
          t = tmpT;
          mat = wallsMat[i];
          normal = tmpNorm;
        }
      }
    }
  }

  return intersect;
}
#else
bool intersect(Ray ray, bool shadow, out float t, out Material mat,
               out vec3 normal) {
  bool intersect = false;
  t = inf;
  float tmpT;
  vec3 tmpNorm;

  if (intersectSphere(ray, sphere, tmpT, tmpNorm)) {
    intersect = true;
    if (tmpT < t) {
      t = tmpT;
      mat = sphereMat;
      normal = tmpNorm;
    }
  }

  if (intersectCuboid(ray, cuboid, tmpT, tmpNorm)) {
    intersect = true;
    if (tmpT < t) {
      t = tmpT;
      mat = cuboidMat;
      normal = tmpNorm;
    }
  }

  // Pyramid
  for (int i = 0; i < 4; i += 1) {
    if (intersectTriangle(ray, pyrTris[i], tmpT, tmpNorm)) {
      intersect = true;
      if (tmpT < t) {
        t = tmpT;
        mat = pyramidMat;
        normal = tmpNorm;
      }
    }
  }
  if (intersectRectangle(ray, pyrBase, tmpT, tmpNorm)) {
    intersect = true;
    if (tmpT < t) {
      t = tmpT;
      mat = pyramidMat;
      normal = tmpNorm;
    }
  }

  if (intersectRectangle(ray, lightRect, tmpT, tmpNorm)) {
    intersect = true;
    if (tmpT < t) {
      t = tmpT;
      mat = lightMat;
      normal = tmpNorm;
    }
  }

  // Walls don't cast shadows
  if (!shadow) {
    for (int i = 0; i < 5; i += 1) {
      if (intersectPlane(ray, walls[i], tmpT, tmpNorm)) {
        intersect = true;
        if (tmpT < t) {
          t = tmpT;
          mat = wallsMat[i];
          normal = tmpNorm;
        }
      }
    }
  }

  return intersect;
}
#endif

// Reflective GGX
float D(vec3 N, vec3 H, float roughness) {
  float a2 = roughness * roughness;
  float NdotH = clampDot(N, H, true);
  float denom = ((NdotH * NdotH) * (a2 * a2 - 1) + 1);
  return a2 / (pi * denom * denom);
}

float G(vec3 N, vec3 V, vec3 L, float roughness) {
  float NdotV = clampDot(N, V, false);
  float NdotL = clampDot(N, L, false);
  float k = roughness * roughness / 2;
  float G_V = NdotV / (NdotV * (1.0 - k) + k);
  float G_L = NdotL / (NdotL * (1.0 - k) + k);

  return G_V * G_L;
}

vec3 F(vec3 L, vec3 H, vec3 F0) {
  float LdotH = clampDot(L, H, true);
  return F0 + (1.0 - F0) * pow(1.0 - LdotH, 5.0);
}

#ifdef USE_VNDF
// Adapted from https://jcgt.org/published/0007/04/01/
vec3 sampleVndf(vec3 V, float roughness, vec2 rng, mat3 onb) {
  V = vec3(dot(V, onb[0]), dot(V, onb[2]), dot(V, onb[1]));

  // Transforming the view direction to the hemisphere configuration
  V = normalize(vec3(roughness * V.x, roughness * V.y, V.z));

  // Orthonormal basis (with special case if cross product is zero)
  float lensq = V.x * V.x + V.y * V.y;
  vec3 T1 =
      lensq > 0. ? vec3(-V.y, V.x, 0) * inversesqrt(lensq) : vec3(1, 0, 0);
  vec3 T2 = cross(V, T1);

  // Parameterization of the projected area
  float r = sqrt(rng.x);
  float phi = 2.0 * pi * rng.y;
  float t1 = r * cos(phi);
  float t2 = r * sin(phi);
  float s = 0.5 * (1.0 + V.z);
  t2 = (1.0 - s) * sqrt(1.0 - t1 * t1) + s * t2;

  // Reprojection onto hemisphere
  vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * V;
  // Transforming the normal back to the ellipsoid configuration
  vec3 Ne = normalize(vec3(roughness * Nh.x, max(0.0, Nh.z), roughness * Nh.y));
  return normalize(onb * Ne);
}

float sampleVndfPdf(vec3 V, vec3 H, float D) {
  float VdotH = clampDot(V, H, true);
  return VdotH > 0 ? D / (4 * VdotH) : 0;
}

#else

vec3 sampleNdf(float roughness, vec2 rng, mat3 onb) {
  // GGX NDF sampling
  float a2 = roughness * roughness;
  float cosThetaH = sqrt(max(0.0, (1.0 - rng.x) / ((a2 - 1.0) * rng.x + 1.0)));
  float sinThetaH = sqrt(max(0.0, 1.0 - cosThetaH * cosThetaH));
  float phiH = rng.y * pi * 2.0;

  // Get our GGX NDF sample (i.e., the half vector)
  vec3 H = vec3(sinThetaH * cos(phiH), cosThetaH, sinThetaH * sin(phiH));
  return normalize(onb * H);
}

float sampleNdfPdf(vec3 L, vec3 H, vec3 N, float D) {
  return D * clampDot(N, H, true) / (4 * clampDot(H, L, false));
}
#endif

// Light sampling
vec3 sampleLight(Rectangle light, vec2 rng) {
  float x = (rng.x - 0.5) * light.lenX;
  float y = (rng.y - 0.5) * light.lenY;
  vec3 pos = (light.dirX * x + light.dirY * y) + light.center;
  return pos;
}

float sampleLightPdf(Rectangle light) { return 1 / (light.lenX * light.lenY); }

// Convert from area measure to angle measure
float pdfA2W(float pdf, float dist2, float cos_theta) {
  float abs_cos_theta = abs(cos_theta);
  if (abs_cos_theta < 1e-8) {
    return 0.0;
  }

  return pdf * dist2 / abs_cos_theta;
}

vec3 evalBSDF(Material mat, vec3 N, vec3 H, vec3 V, vec3 L, vec3 pos,
              out float pdf) {
  float d = D(N, H, mat.roughness);
  float g = G(N, V, L, mat.roughness);
  vec3 color = mat.color;
  // Check if checkerboard material
  if (mat.type == 3) {
    float fac = 2 * pi / checkerboard;
    if (sin(fac * pos.x) * sin(fac * pos.y) * sin(fac * pos.z) < 0) {
      color = vec3(0.1, 0.1, 0.1);
    }
  }
  vec3 f = F(L, H, color);
  vec3 brdf = d * g * f;
  brdf = brdf / (4 * clampDot(N, H, false) * clampDot(N, L, false));

#ifdef USE_VNDF
  pdf = sampleVndfPdf(V, H, d);
#else
  pdf = sampleNdfPdf(V, H, N, d);
#endif

  return brdf;
}

vec3 rayTrace(Ray ray) {
  Material mat;
  float t;
  vec3 normal;
  vec3 contrib = vec3(0);
  vec3 tp = vec3(1);

#ifdef DEBUG_ALBEDO
  if (intersect(ray, false, t, mat, normal)) {
    return mat.color;
  }
#endif

#ifdef DEBUG_NORMALS
  if (intersect(ray, false, t, mat, normal)) {
    return normalize(normal + vec3(1));
  }
#endif

  bool hit = intersect(ray, false, t, mat, normal);
  if (!hit) {
    return vec3(0);
  }

  if (mat.type == 2) {
    return mat.color;
  }

  for (int i = 0; i < numBounces; i++) {
    mat3 onb = constructONBFrisvad(normal);
    vec3 V = -ray.dir;
// Next event estimation
#ifdef USE_NEE
    {
      float lightPdf = sampleLightPdf(lightRect);
      vec3 pos = sampleLight(lightRect, getRandom());
      vec3 newPos = ray.origin + t * ray.dir;
      vec3 L = normalize(pos - newPos);
      float dist = distance(pos, newPos);
      dist = dist * dist;

      float tTmp;
      Material tMat;
      vec3 tNormal;
      bool hit = intersect(Ray(newPos + eps * L, L), true, tTmp, tMat, tNormal);
      if (hit && tMat.type == 2) {
        vec3 H = normalize(V + L);

        float brdfPdf;
        vec3 brdf = evalBSDF(mat, normal, H, V, L, newPos, brdfPdf);

        float lightPdfW = pdfA2W(lightPdf, dist, dot(-L, tNormal));

        float misW = lightPdfW / (lightPdfW + brdfPdf);

        contrib += misW * tMat.color * tp * brdf * clampDot(normal, L, true) /
                   lightPdfW;
      }
    }
#endif
    {
      Material nextMat;
      vec3 nextNormal;

#ifdef USE_VNDF
      vec3 H = sampleVndf(V, mat.roughness, getRandom(), onb);
#else
      vec3 H = sampleNdf(mat.roughness, getRandom(), onb);
#endif

      vec3 L = normalize(reflect(ray.dir, H));

      vec3 newPos = ray.origin + t * ray.dir + eps * L;
      ray = Ray(newPos, L);

      // Didn't hit anything
      if (!intersect(ray, false, t, nextMat, nextNormal)) {
        break;
      }

      float brdfPdf;
      vec3 brdf = evalBSDF(mat, normal, H, V, L, newPos, brdfPdf);

      if (nextMat.type == 2) {
#ifdef USE_NEE
        float lightPdf = sampleLightPdf(lightRect);
        sampleLight(lightRect, getRandom());
        float lightPdfW = pdfA2W(lightPdf, dot(L, L), dot(-L, nextNormal));
        float misW = brdfPdf / (lightPdfW + brdfPdf);
#else
        float misW = 1;
#endif

        contrib += misW * nextMat.color * tp * brdf *
                   clampDot(normal, L, true) / brdfPdf;
        break;
      }

      tp *= clampDot(normal, L, true) * brdf / brdfPdf;
      mat = nextMat;
      normal = nextNormal;
    }
  }

  return contrib;
}

void main() {
  seed = seedInit;
  flatIdx = int(dot(gl_FragCoord.xy, vec2(1, 4096)));

  // Generate sample
  Ray ray = genRay(getRandom());
  // vec3 op = clamp(rayTrace(ray), vec3(0), vec3(1));
  vec3 op = clamp(rayTrace(ray), vec3(0), vec3(1));

  // Get previous data
  vec3 prev = texture(prevFrame, gl_FragCoord.xy / resolution.xy).rgb;

  // Add to previous frame
#ifndef DEBUG_SINGLE
  fragColor = vec4(op + prev, 1);
#else
  fragColor = vec4(op, 1);
#endif
}
