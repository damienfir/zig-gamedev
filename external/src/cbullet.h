#pragma once

#define CBT_DECLARE_HANDLE(name) typedef struct name##__ { int unused; } *name

// CbtRayCastResult
#define CBT_COLLISION_FILTER_DEFAULT 1
#define CBT_COLLISION_FILTER_STATIC 2
#define CBT_COLLISION_FILTER_KINEMATIC 4
#define CBT_COLLISION_FILTER_DEBRIS 8
#define CBT_COLLISION_FILTER_SENSOR_TRIGGER 16
#define CBT_COLLISION_FILTER_CHARACTER 32
#define CBT_COLLISION_FILTER_ALL -1

// CbtRayCastResult::flags
#define CBT_RAYCAST_FLAG_SKIP_BACKFACES 1
#define CBT_RAYCAST_FLAG_KEEP_UNFLIPPED_NORMALS 2

// cbtBodySetAnisotropicFriction
#define CBT_ANISOTROPIC_FRICTION_DISABLED 0
#define CBT_ANISOTROPIC_FRICTION 1
#define CBT_ANISOTROPIC_ROLLING_FRICTION 2

// cbtShapeGetType
#define CBT_SHAPE_TYPE_BOX 0
#define CBT_SHAPE_TYPE_BOX_2D 17
#define CBT_SHAPE_TYPE_SPHERE 8
#define CBT_SHAPE_TYPE_CAPSULE 10
#define CBT_SHAPE_TYPE_CONE 11
#define CBT_SHAPE_TYPE_CYLINDER 13
#define CBT_SHAPE_TYPE_STATIC_PLANE 28

typedef float CbtVector3[3];

#ifdef __cplusplus
extern "C" {
#endif

CBT_DECLARE_HANDLE(CbtWorldHandle);
CBT_DECLARE_HANDLE(CbtShapeHandle);
CBT_DECLARE_HANDLE(CbtBodyHandle);

typedef void (*CbtDrawLineCallback)(const CbtVector3 p0, const CbtVector3 p1, const CbtVector3 color, void* user_data);
typedef void (*CbtDrawContactPointCallback)(
    const CbtVector3 point,
    const CbtVector3 normal,
    float distance,
    int life_time,
    const CbtVector3 color,
    void* user_data
);
typedef void (*CbtReportErrorWarningCallback)(const char* str, void* user_data);

typedef struct CbtDebugDrawCallbacks {
    CbtDrawLineCallback drawLine;
    CbtDrawContactPointCallback drawContactPoint;
    CbtReportErrorWarningCallback reportErrorWarning;
    void* user_data;
} CbtDebugDrawCallbacks;

typedef struct CbtRayCastResult {
    CbtVector3 hit_normal_world;
    CbtVector3 hit_point_world;
    float hit_fraction;
    CbtBodyHandle body;
} CbtRayCastResult;

//
// World
//
CbtWorldHandle cbtWorldCreate(void);
void cbtWorldDestroy(CbtWorldHandle handle);
void cbtWorldSetGravity(CbtWorldHandle handle, const CbtVector3 gravity);
int cbtWorldStepSimulation(CbtWorldHandle handle, float time_step, int max_sub_steps, float fixed_time_step);

//void cbtRayTestClosest(const CbtVector3 ray_from_world, const CbtVector3 ray_to_world, CbtRayCastResult* result);

void cbtWorldDebugSetCallbacks(CbtWorldHandle handle, const CbtDebugDrawCallbacks* callbacks);
void cbtWorldDebugDraw(CbtWorldHandle handle);
void cbtWorldDebugDrawLine(CbtWorldHandle handle, const CbtVector3 p0, const CbtVector3 p1, const CbtVector3 color);
void cbtWorldDebugDrawSphere(CbtWorldHandle handle, const CbtVector3 position, float radius, const CbtVector3 color);

//
// Shape
//
CbtShapeHandle cbtShapeCreateBox(const CbtVector3 half_extents);
CbtShapeHandle cbtShapeCreateBox2d(float x_half_extent, float y_half_extent);
CbtShapeHandle cbtShapeCreateSphere(float radius);
CbtShapeHandle cbtShapeCreatePlane(const CbtVector3 normal, float distance);

CbtShapeHandle cbtShapeCreateCapsuleX(float radius, float height);
CbtShapeHandle cbtShapeCreateCapsuleY(float radius, float height);
CbtShapeHandle cbtShapeCreateCapsuleZ(float radius, float height);

CbtShapeHandle cbtShapeCreateCylinderX(const CbtVector3 half_extents);
CbtShapeHandle cbtShapeCreateCylinderY(const CbtVector3 half_extents);
CbtShapeHandle cbtShapeCreateCylinderZ(const CbtVector3 half_extents);

CbtShapeHandle cbtShapeCreateConeX(float radius, float height);
CbtShapeHandle cbtShapeCreateConeY(float radius, float height);
CbtShapeHandle cbtShapeCreateConeZ(float radius, float height);

void cbtShapeSetUserPointer(CbtShapeHandle handle, void* user_pointer);
void cbtShapeSetUserIndex(CbtShapeHandle handle, int user_index);
void* cbtShapeGetUserPointer(CbtShapeHandle handle);
int cbtShapeGetUserIndex(CbtShapeHandle handle);

void cbtShapeDestroy(CbtShapeHandle handle);
int cbtShapeGetType(CbtShapeHandle handle);

//
// Body
//
CbtBodyHandle cbtBodyCreate(
    CbtWorldHandle world_handle,
    float mass,
    const CbtVector3 transform[4],
    CbtShapeHandle shape_handle
);
void cbtBodyDestroy(CbtWorldHandle world_handle, CbtBodyHandle body_handle);

void cbtBodySetShape(CbtBodyHandle body_handle, CbtShapeHandle shape_handle);
CbtShapeHandle cbtBodyGetShape(CbtBodyHandle handle);

void cbtBodySetRestitution(CbtBodyHandle handle, float restitution);

void cbtBodySetFriction(CbtBodyHandle handle, float friction);
void cbtBodySetRollingFriction(CbtBodyHandle handle, float friction);
void cbtBodySetSpinningFriction(CbtBodyHandle handle, float friction);
void cbtBodySetAnisotropicFriction(CbtBodyHandle handle, const CbtVector3 friction, int mode);

void cbtBodySetContactStiffnessAndDamping(CbtBodyHandle handle, float stiffness, float damping);

void cbtBodySetMassProps(CbtBodyHandle handle, float mass, const CbtVector3 inertia);

void cbtBodySetDamping(CbtBodyHandle handle, float linear, float angular);

void cbtBodySetLinearVelocity(CbtBodyHandle handle, const CbtVector3 velocity);
void cbtBodySetAngularVelocity(CbtBodyHandle handle, const CbtVector3 velocity);
void cbtBodySetPushVelocity(CbtBodyHandle handle, const CbtVector3 velocity);
void cbtBodySetTurnVelocity(CbtBodyHandle handle, const CbtVector3 velocity);


void cbtBodyApplyCentralForce(CbtBodyHandle handle, const CbtVector3 force);
void cbtBodyApplyCentralImpulse(CbtBodyHandle handle, const CbtVector3 impulse);
void cbtBodyApplyCentralPushImpulse(CbtBodyHandle handle, const CbtVector3 impulse);

void cbtBodyApplyForce(CbtBodyHandle handle, const CbtVector3 force, const CbtVector3 rel_pos);
void cbtBodyClearForces(CbtBodyHandle handle);

void cbtBodyApplyImpulse(CbtBodyHandle handle, const CbtVector3 impulse, const CbtVector3 rel_pos);
void cbtBodyApplyPushImpulse(CbtBodyHandle handle, const CbtVector3 impulse, const CbtVector3 rel_pos);

void cbtBodyApplyTorque(CbtBodyHandle handle, const CbtVector3 torque);
void cbtBodyApplyTorqueImpulse(CbtBodyHandle handle, const CbtVector3 impulse);
void cbtBodyApplyTorqueTurnImpulse(CbtBodyHandle handle, const CbtVector3 impulse);


float cbtBodyGetRestitution(CbtBodyHandle handle);

float cbtBodyGetFriction(CbtBodyHandle handle);
float cbtBodyGetRollingFriction(CbtBodyHandle handle);
float cbtBodyGetSpinningFriction(CbtBodyHandle handle);
void cbtBodyGetAnisotropicFriction(CbtBodyHandle handle, CbtVector3 friction);

float cbtBodyGetContactStiffness(CbtBodyHandle handle);
float cbtBodyGetContactDamping(CbtBodyHandle handle);

float cbtBodyGetMass(CbtBodyHandle handle);

float cbtBodyGetLinearDamping(CbtBodyHandle handle);
float cbtBodyGetAngularDamping(CbtBodyHandle handle);

void cbtBodyGetLinearVelocity(CbtBodyHandle handle, CbtVector3 velocity);
void cbtBodyGetAngularVelocity(CbtBodyHandle handle, CbtVector3 velocity);
void cbtBodyGetPushVelocity(CbtBodyHandle handle, CbtVector3 velocity);
void cbtBodyGetTurnVelocity(CbtBodyHandle handle, CbtVector3 velocity);

void cbtBodyGetTotalForce(CbtBodyHandle handle, CbtVector3 force);
void cbtBodyGetTotalTorque(CbtBodyHandle handle, CbtVector3 torque);


void cbtBodyGetGraphicsTransform(CbtBodyHandle handle, CbtVector3 transform[4]);

#ifdef __cplusplus
}
#endif