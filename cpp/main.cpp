// lmphysics: Project Chrono core (rigid bodies, joints, contact) behind an lmscript `_dsl_` schema.
// Scripting only: the executable has no user-facing commands besides --dsl and the schema/version queries.
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include "chrono/collision/ChCollisionShapeBox.h"
#include "chrono/collision/ChCollisionShapeCylinder.h"
#include "chrono/collision/ChCollisionShapeSphere.h"
#include "chrono/functions/ChFunctionBase.h"
#include "chrono/physics/ChBody.h"
#include "chrono/physics/ChContactMaterialNSC.h"
#include "chrono/physics/ChContactMaterialSMC.h"
#include "chrono/physics/ChLinkDistance.h"
#include "chrono/physics/ChLinkLock.h"
#include "chrono/physics/ChLinkMotorRotation.h"
#include "chrono/physics/ChLinkMotorRotationAngle.h"
#include "chrono/physics/ChLinkMotorRotationSpeed.h"
#include "chrono/physics/ChLinkTSDA.h"
#include "chrono/physics/ChSystemNSC.h"
#include "chrono/physics/ChSystemSMC.h"
#include "chrono/solver/ChIterativeSolverLS.h"
#include "chrono/timestepper/ChTimestepper.h"
#include "chrono/solver/ChIterativeSolverVI.h"

#include "dslvm.hpp"
#include "expr.hpp"
#include "notices_embedded.hpp"
#include "schema_embedded.hpp"

namespace {
using dslvm::Args;
using dslvm::Value;
namespace ch = chrono;

// An lmscript expression in t, used as a Chrono scalar function (motor speed or angle).
class ExprFunction : public ch::ChFunction {
 public:
  explicit ExprFunction(const std::string &text) : e_(std::make_shared<lmphysics::Expr>(text, std::vector<std::string>{"t"})) {}
  ExprFunction *Clone() const override { return new ExprFunction(*this); }
  double GetVal(double t) const override { return e_->eval(&t); }
 private:
  std::shared_ptr<lmphysics::Expr> e_;
};

struct SysObj;
enum class Shape { None, Box, Sphere, Cylinder };

struct BodyObj {
  std::string name;
  std::shared_ptr<ch::ChBody> b;
  Shape shape = Shape::None;
  double d[3] = {0, 0, 0};  // box lengths, sphere radius, cylinder radius + height
  bool collide = false;
  SysObj *sys = nullptr;
};

enum class JKind { Lock, Revolute, Prismatic, Spherical, Distance, Spring, Motor };
struct JointObj {
  std::string name;
  JKind kind = JKind::Lock;
  std::shared_ptr<ch::ChLinkBase> link;
  std::shared_ptr<ch::ChLinkTSDA> tsda;
  std::shared_ptr<ch::ChLinkMotorRotation> motor;  // motors are built with the bodies swapped (Chrono turns body 1 against body 2)
  double k = 0, rest = 0;       // spring data for energy()
  double angle = 0, prev = 0;   // unwrapped relative rotation about the joint axis
  bool angle_init = false;
};

struct Record { bool is_body; BodyObj *body; JointObj *joint; std::vector<std::string> cols; };

struct SysObj {
  bool smc = false;
  std::unique_ptr<ch::ChSystem> sys;
  std::map<std::string, std::shared_ptr<ch::ChContactMaterial>> mats;
  std::vector<std::unique_ptr<BodyObj>> bodies;
  std::vector<std::unique_ptr<JointObj>> joints;
  std::vector<Record> recs;
  std::vector<std::vector<double>> rows;
  std::vector<std::string> header{"t"};
  double dt = 1e-3;
  bool started = false;
  std::string integrator = "euler";
};

struct Host { std::vector<std::unique_ptr<SysObj>> systems; };

double rel_rotation(const JointObj &j) {
  ch::ChQuaterniond q = j.link->GetFrame1Abs().GetRot().GetConjugate() * j.link->GetFrame2Abs().GetRot();
  return 2.0 * std::atan2(q.e3(), q.e0());
}
void track_angle(JointObj &j) {
  if (j.motor) { j.angle = j.motor->GetMotorAngle(); return; }
  double raw = rel_rotation(j);
  if (!j.angle_init) { j.angle = raw; j.angle_init = true; }
  else {
    double d = raw - j.prev;
    while (d > ch::CH_PI) d -= ch::CH_2PI;
    while (d < -ch::CH_PI) d += ch::CH_2PI;
    j.angle += d;
  }
  j.prev = raw;
}

template <class F> Value translate(F &&fn) {
  try { return fn(); }
  catch (const dslvm::Error &) { throw; }
  catch (const std::exception &e) { throw dslvm::Error(e.what()); }
}

void check_args(const char *who, const std::vector<std::string> &params, Args &a) {
  for (size_t i = 0; i < params.size(); i++) {
    const auto &want = params[i];
    const auto &v = a[i];
    bool ok = want == "float" ? v.kind == Value::FLOAT
              : want == "int" ? v.kind == Value::INT
              : want == "string" ? v.kind == Value::STR
              : want == "bool" ? v.kind == Value::BOOL
              : v.kind == Value::OBJ && v.type == want && v.obj;
    if (!ok) throw dslvm::Error(std::string(who) + " argument " + std::to_string(i + 1) + " must be " + want);
  }
}

void method(dslvm::Registry &r, const char *type, const char *name, std::vector<std::string> params, std::string returns,
            dslvm::Method cb) {
  std::string who = std::string(type) + "." + name;
  r.method(type, name, params, returns, [who, params, cb](void *self, Args &a) {
    check_args(who.c_str(), params, a);
    return translate([&] { return cb(self, a); });
  });
}

std::string fmt(double x) { char b[40]; std::snprintf(b, sizeof b, "%.10g", x); return b; }
std::string fmt12(double x) { char b[40]; std::snprintf(b, sizeof b, "%.12g", x); return b; }

SysObj &S(void *p) { return *static_cast<SysObj *>(p); }
BodyObj &B(void *p) { return *static_cast<BodyObj *>(p); }
JointObj &J(void *p) { return *static_cast<JointObj *>(p); }
BodyObj &arg_body(Value &v) { return *static_cast<BodyObj *>(v.obj); }
Value sys_value(void *p) { return Value::object("System", p); }
Value body_value(BodyObj *b) { return Value::object("Body", b); }
Value joint_value(JointObj *j) { return Value::object("Joint", j); }
ch::ChVector3d vec(Args &a, int i) { return ch::ChVector3d(a[i].f, a[i + 1].f, a[i + 2].f); }

void finite(const char *who, double x) { if (!std::isfinite(x)) throw dslvm::Error(std::string(who) + ": value is not finite"); }
void positive(const char *who, const char *what, double x) {
  if (!(x > 0) || !std::isfinite(x)) throw dslvm::Error(std::string(who) + ": " + what + " must be positive");
}

void unique_name(SysObj &s, const std::string &name, const char *who) {
  if (name.empty()) throw dslvm::Error(std::string(who) + ": name must not be empty");
  for (auto &b : s.bodies) if (b->name == name) throw dslvm::Error(std::string(who) + ": name '" + name + "' is already used");
  for (auto &j : s.joints) if (j->name == name) throw dslvm::Error(std::string(who) + ": name '" + name + "' is already used");
}

BodyObj *new_body(SysObj &s, const std::string &name, const char *who) {
  unique_name(s, name, who);
  auto b = std::make_unique<BodyObj>();
  b->name = name;
  b->b = chrono_types::make_shared<ch::ChBody>();
  b->sys = &s;
  s.sys->Add(b->b);
  s.bodies.push_back(std::move(b));
  return s.bodies.back().get();
}

void set_mass_props(BodyObj &b, double density) {
  double m = 0, ix = 0, iy = 0, iz = 0;
  if (b.shape == Shape::Box) {
    m = density * b.d[0] * b.d[1] * b.d[2];
    ix = m * (b.d[1] * b.d[1] + b.d[2] * b.d[2]) / 12;
    iy = m * (b.d[0] * b.d[0] + b.d[2] * b.d[2]) / 12;
    iz = m * (b.d[0] * b.d[0] + b.d[1] * b.d[1]) / 12;
  } else if (b.shape == Shape::Sphere) {
    m = density * 4.0 / 3.0 * ch::CH_PI * b.d[0] * b.d[0] * b.d[0];
    ix = iy = iz = 0.4 * m * b.d[0] * b.d[0];
  } else {
    m = density * ch::CH_PI * b.d[0] * b.d[0] * b.d[1];
    iy = 0.5 * m * b.d[0] * b.d[0];
    ix = iz = m * (3 * b.d[0] * b.d[0] + b.d[1] * b.d[1]) / 12;
  }
  b.b->SetMass(m);
  b.b->SetInertiaXX(ch::ChVector3d(ix, iy, iz));
}

ch::ChFrame<> axis_frame(const ch::ChVector3d &p, ch::ChVector3d axis, const char *who) {
  if (axis.Length() < 1e-12) throw dslvm::Error(std::string(who) + ": axis must not be zero");
  axis.Normalize();
  ch::ChMatrix33<> R;
  R.SetFromAxisZ(axis);
  return ch::ChFrame<>(p, R);
}

void check_distinct(BodyObj &a, BodyObj &b, const char *who) {
  if (a.sys != b.sys) throw dslvm::Error(std::string(who) + ": bodies belong to different systems");
  if (&a == &b) throw dslvm::Error(std::string(who) + ": needs two different bodies");
}

JointObj *new_joint(SysObj &s, const std::string &name, JKind k, std::shared_ptr<ch::ChLinkBase> link, const char *who) {
  unique_name(s, name, who);
  auto j = std::make_unique<JointObj>();
  j->name = name; j->kind = k; j->link = link;
  s.sys->Add(link);
  s.joints.push_back(std::move(j));
  track_angle(*s.joints.back());  // the angle is measured from the pose at creation
  return s.joints.back().get();
}

void need_not_started(SysObj &s, const char *who) {
  if (s.started) throw dslvm::Error(std::string(who) + ": not allowed after the simulation has started");
}

double body_value_of(const BodyObj &bo, const std::string &c) {
  auto &b = *bo.b;
  ch::ChVector3d p = b.GetPos(), v = b.GetPosDt(), w = b.GetAngVelParent();
  if (c == "x") return p.x();
  if (c == "y") return p.y();
  if (c == "z") return p.z();
  if (c == "vx") return v.x();
  if (c == "vy") return v.y();
  if (c == "vz") return v.z();
  if (c == "wx") return w.x();
  if (c == "wy") return w.y();
  if (c == "wz") return w.z();
  ch::ChQuaterniond q = b.GetRot();
  if (c == "qw") return q.e0();
  if (c == "qx") return q.e1();
  if (c == "qy") return q.e2();
  if (c == "qz") return q.e3();
  if (c == "speed") return v.Length();
  ch::ChVector3d wl = b.GetAngVelLocal();
  ch::ChVector3d Lw = b.GetRotMat() * (b.GetInertia() * wl);
  if (c == "lx") return Lw.x();
  if (c == "ly") return Lw.y();
  if (c == "lz") return Lw.z();
  if (c == "ke") return 0.5 * b.GetMass() * v.Length2() + 0.5 * wl.Dot(b.GetInertia() * wl);
  throw dslvm::Error("record: unknown body column '" + c + "' (x y z vx vy vz wx wy wz qw qx qy qz speed lx ly lz ke)");
}

double joint_value_of(const JointObj &j, const std::string &c) {
  ch::ChWrenchd w = j.motor ? j.link->GetReaction1() : j.link->GetReaction2();
  ch::ChFramed f2 = j.motor ? j.link->GetFrame1Abs() : j.link->GetFrame2Abs();
  if (c == "fx" || c == "fy" || c == "fz") {
    ch::ChVector3d f = f2.TransformDirectionLocalToParent(w.force);
    return c == "fx" ? f.x() : c == "fy" ? f.y() : f.z();
  }
  if (c == "tx" || c == "ty" || c == "tz") {
    ch::ChVector3d t = f2.TransformDirectionLocalToParent(w.torque);
    return c == "tx" ? t.x() : c == "ty" ? t.y() : t.z();
  }
  if (c == "angle") return j.angle;
  if (c == "length") return (j.link->GetFrame2Abs().GetPos() - j.link->GetFrame1Abs().GetPos()).Length();
  if (c == "force") return j.tsda ? j.tsda->GetForce() : w.force.Length();
  if (c == "torque") return w.torque.Length();
  throw dslvm::Error("record: unknown joint column '" + c + "' (fx fy fz tx ty tz angle length force torque)");
}

void capture_row(SysObj &s) {
  std::vector<double> row{s.sys->GetChTime()};
  for (auto &r : s.recs)
    for (auto &c : r.cols) row.push_back(r.is_body ? body_value_of(*r.body, c) : joint_value_of(*r.joint, c));
  s.rows.push_back(std::move(row));
}

void start(SysObj &s) {
  if (s.started) return;
  s.started = true;
  capture_row(s);
}

void do_step(SysObj &s) {
  start(s);
  try { s.sys->DoStepDynamics(s.dt); }
  catch (const std::exception &e) {
    std::string hint = (s.integrator == "hht" || s.integrator == "newmark")
                           ? " (hint: hht and newmark need a direct solver and enough Newton iterations: solver(\"sparse_lu\", 1), newton(30, 1e-6, 1e-9))" : "";
    throw dslvm::Error(std::string("step failed: ") + e.what() + hint);
  }
  for (auto &j : s.joints) track_angle(*j);
  capture_row(s);
}

double total_energy(SysObj &s) {
  double e = 0;
  ch::ChVector3d g = s.sys->GetGravitationalAcceleration();
  for (auto &bo : s.bodies) {
    auto &b = *bo->b;
    ch::ChVector3d wl = b.GetAngVelLocal();
    e += 0.5 * b.GetMass() * b.GetPosDt().Length2() + 0.5 * wl.Dot(b.GetInertia() * wl);
    e -= b.GetMass() * g.Dot(b.GetPos());
  }
  for (auto &j : s.joints)
    if (j->kind == JKind::Spring) { double x = j->tsda->GetLength() - j->rest; e += 0.5 * j->k * x * x; }
  return e;
}

// A no-argument float method that reads the named column (the same names `record` accepts).
void getter(dslvm::Registry &r, const char *type, const char *col) {
  std::string c = col;
  bool body = std::string(type) == "Body";
  method(r, type, col, {}, "float", [c, body](void *p, Args &) {
    return Value::real(body ? body_value_of(B(p), c) : joint_value_of(J(p), c));
  });
}

void register_host(dslvm::Registry &r, Host &h) {
  r.context("phys", "Phys");

  // ---------------------------------------------------------------- Phys
  method(r, "Phys", "system", {"string"}, "System", [&h](void *, Args &a) {
    if (a[0].s != "nsc" && a[0].s != "smc") throw dslvm::Error("Phys.system: kind must be \"nsc\" or \"smc\"");
    if (h.systems.size() >= 1000) throw dslvm::Error("Phys.system: too many systems");
    auto s = std::make_unique<SysObj>();
    s->smc = a[0].s == "smc";
    if (s->smc) s->sys = std::make_unique<ch::ChSystemSMC>();
    else {
      auto nsc = std::make_unique<ch::ChSystemNSC>();
      // Chrono 9.0.1 leaves the contact container's min_bounce_speed uninitialized (its documented default is 0.15),
      // which makes restitution depend on heap garbage. Always set it.
      nsc->SetMinBounceSpeed(0.15);
      s->sys = std::move(nsc);
    }
    s->sys->SetGravitationalAcceleration(ch::ChVector3d(0, 0, -9.81));
    s->sys->SetNumThreads(1);
    s->sys->SetCollisionSystemType(ch::ChCollisionSystem::Type::BULLET);
    s->sys->SetTimestepperType(ch::ChTimestepper::Type::EULER_IMPLICIT_LINEARIZED);
    auto def = s->smc ? std::shared_ptr<ch::ChContactMaterial>(chrono_types::make_shared<ch::ChContactMaterialSMC>())
                      : std::shared_ptr<ch::ChContactMaterial>(chrono_types::make_shared<ch::ChContactMaterialNSC>());
    s->mats["default"] = def;
    h.systems.push_back(std::move(s));
    return sys_value(h.systems.back().get());
  });
  method(r, "Phys", "assert_close", {"float", "float", "float"}, "void", [](void *, Args &a) {
    if (!(std::fabs(a[0].f - a[1].f) <= a[2].f))
      throw dslvm::Error("assert_close failed: " + fmt(a[0].f) + " vs " + fmt(a[1].f) + " (tolerance " + fmt(a[2].f) + ")");
    return Value::none();
  });
  method(r, "Phys", "print", {"string"}, "void", [](void *, Args &a) { std::cout << a[0].s << std::endl; return Value::none(); });
  method(r, "Phys", "version", {}, "string", [](void *, Args &) {
    return Value::string("lmphysics " LMPHYSICS_VERSION " (Chrono 9.0.1)");
  });

  // ---------------------------------------------------------------- System
  method(r, "System", "gravity", {"float", "float", "float"}, "System", [](void *p, Args &a) {
    for (int i = 0; i < 3; i++) finite("System.gravity", a[i].f);
    S(p).sys->SetGravitationalAcceleration(vec(a, 0)); return sys_value(p);
  });
  method(r, "System", "timestep", {"float"}, "System", [](void *p, Args &a) {
    positive("System.timestep", "dt", a[0].f); S(p).dt = a[0].f; return sys_value(p);
  });
  method(r, "System", "solver", {"string", "int"}, "System", [](void *p, Args &a) {
    static const std::map<std::string, ch::ChSolver::Type> kinds = {
        {"psor", ch::ChSolver::Type::PSOR}, {"pjacobi", ch::ChSolver::Type::PJACOBI}, {"minres", ch::ChSolver::Type::MINRES},
        {"pminres", ch::ChSolver::Type::PMINRES}, {"bb", ch::ChSolver::Type::BARZILAIBORWEIN}, {"apgd", ch::ChSolver::Type::APGD},
        {"sparse_lu", ch::ChSolver::Type::SPARSE_LU}, {"sparse_qr", ch::ChSolver::Type::SPARSE_QR}};
    auto it = kinds.find(a[0].s);
    if (it == kinds.end())
      throw dslvm::Error("System.solver: unknown solver '" + a[0].s + "' (psor pjacobi minres pminres bb apgd sparse_lu sparse_qr)");
    if (a[1].i < 1 || a[1].i > 1000000) throw dslvm::Error("System.solver: iterations must be in 1..1000000");
    auto &sys = *S(p).sys;
    sys.SetSolverType(it->second);
    if (auto *vi = dynamic_cast<ch::ChIterativeSolverVI *>(sys.GetSolver().get())) vi->SetMaxIterations((int)a[1].i);
    else if (auto *ls = dynamic_cast<ch::ChIterativeSolverLS *>(sys.GetSolver().get())) ls->SetMaxIterations((int)a[1].i);
    return sys_value(p);
  });
  method(r, "System", "integrator", {"string"}, "System", [](void *p, Args &a) {
    static const std::map<std::string, ch::ChTimestepper::Type> kinds = {
        {"euler", ch::ChTimestepper::Type::EULER_IMPLICIT_LINEARIZED}, {"euler_projected", ch::ChTimestepper::Type::EULER_IMPLICIT_PROJECTED},
        {"euler_implicit", ch::ChTimestepper::Type::EULER_IMPLICIT}, {"trapezoidal", ch::ChTimestepper::Type::TRAPEZOIDAL}, {"trapezoidal_linearized", ch::ChTimestepper::Type::TRAPEZOIDAL_LINEARIZED},
        {"hht", ch::ChTimestepper::Type::HHT}, {"newmark", ch::ChTimestepper::Type::NEWMARK}};
    auto it = kinds.find(a[0].s);
    if (it == kinds.end()) throw dslvm::Error("System.integrator: unknown integrator '" + a[0].s + "' (euler euler_projected euler_implicit trapezoidal hht newmark)");
    S(p).sys->SetTimestepperType(it->second); S(p).integrator = a[0].s;
    // HHT and Newmark solve a DAE with Newton iterations: give them a direct solver and a Newton budget that converges
    // for joints (Chrono's defaults of 6 iterations and PSOR do not). solver() and newton() override these.
    if (a[0].s == "hht" || a[0].s == "newmark") {
      S(p).sys->SetSolverType(ch::ChSolver::Type::SPARSE_LU);
      auto *it = dynamic_cast<ch::ChImplicitIterativeTimestepper *>(S(p).sys->GetTimestepper().get());
      it->SetMaxIters(30); it->SetRelTolerance(1e-6); it->SetAbsTolerances(1e-9);
    }
    if (auto *h = dynamic_cast<ch::ChTimestepperHHT *>(S(p).sys->GetTimestepper().get())) h->SetStepControl(false);
    return sys_value(p);
  });
  method(r, "System", "bounce_speed", {"float"}, "System", [](void *p, Args &a) {
    if (!(a[0].f >= 0) || !std::isfinite(a[0].f)) throw dslvm::Error("System.bounce_speed: speed must be >= 0");
    auto *nsc = dynamic_cast<ch::ChSystemNSC *>(S(p).sys.get());
    if (!nsc) throw dslvm::Error("System.bounce_speed: only nsc systems have restitution thresholds");
    nsc->SetMinBounceSpeed(a[0].f);
    return sys_value(p);
  });
  method(r, "System", "newton", {"int", "float", "float"}, "System", [](void *p, Args &a) {
    if (a[0].i < 1 || a[0].i > 10000) throw dslvm::Error("System.newton: iterations must be in 1..10000");
    positive("System.newton", "tolerances", a[1].f); positive("System.newton", "tolerances", a[2].f);
    auto st = S(p).sys->GetTimestepper();
    auto *it = dynamic_cast<ch::ChImplicitIterativeTimestepper *>(st.get());
    if (!it) throw dslvm::Error("System.newton: the \"" + S(p).integrator + "\" integrator has no Newton iteration");
    it->SetMaxIters((int)a[0].i); it->SetRelTolerance(a[1].f); it->SetAbsTolerances(a[2].f);
    return sys_value(p);
  });
  method(r, "System", "hht_alpha", {"float"}, "System", [](void *p, Args &a) {
    if (!(a[0].f >= -1.0 / 3.0 && a[0].f <= 0.0)) throw dslvm::Error("System.hht_alpha: alpha must be in [-1/3, 0]");
    auto st = S(p).sys->GetTimestepper();
    auto *h = dynamic_cast<ch::ChTimestepperHHT *>(st.get());
    if (!h) throw dslvm::Error("System.hht_alpha: select integrator(\"hht\") first");
    h->SetAlpha(a[0].f);
    return sys_value(p);
  });
  method(r, "System", "material", {"string", "float", "float"}, "System", [](void *p, Args &a) {
    auto &s = S(p);
    if (a[1].f < 0 || a[2].f < 0 || a[2].f > 1) throw dslvm::Error("System.material: friction >= 0 and restitution in [0,1] required");
    std::shared_ptr<ch::ChContactMaterial> m;
    if (s.smc) { auto q = chrono_types::make_shared<ch::ChContactMaterialSMC>(); q->SetYoungModulus(2e7f); q->SetPoissonRatio(0.3f); m = q; }
    else m = chrono_types::make_shared<ch::ChContactMaterialNSC>();
    m->SetFriction((float)a[1].f);
    m->SetRestitution((float)a[2].f);
    s.mats[a[0].s] = m;
    return sys_value(p);
  });
  method(r, "System", "stiffness", {"string", "float", "float"}, "System", [](void *p, Args &a) {
    auto &s = S(p);
    auto it = s.mats.find(a[0].s);
    if (it == s.mats.end()) throw dslvm::Error("System.stiffness: unknown material '" + a[0].s + "'");
    auto *m = dynamic_cast<ch::ChContactMaterialSMC *>(it->second.get());
    if (!m) throw dslvm::Error("System.stiffness: only smc systems have Young's modulus (use system(\"smc\"))");
    positive("System.stiffness", "Young's modulus", a[1].f);
    if (!(a[2].f > -1 && a[2].f < 0.5)) throw dslvm::Error("System.stiffness: Poisson ratio must be in (-1, 0.5)");
    m->SetYoungModulus((float)a[1].f); m->SetPoissonRatio((float)a[2].f);
    return sys_value(p);
  });
  method(r, "System", "ground", {"string"}, "Body", [](void *p, Args &a) {
    BodyObj *b = new_body(S(p), a[0].s, "System.ground");
    b->b->SetFixed(true);
    b->b->SetMass(1.0);
    return body_value(b);
  });
  method(r, "System", "box", {"string", "float", "float", "float", "float"}, "Body", [](void *p, Args &a) {
    for (int i = 1; i <= 4; i++) positive("System.box", "size and density", a[i].f);
    BodyObj *b = new_body(S(p), a[0].s, "System.box");
    b->shape = Shape::Box; b->d[0] = a[1].f; b->d[1] = a[2].f; b->d[2] = a[3].f;
    set_mass_props(*b, a[4].f);
    return body_value(b);
  });
  method(r, "System", "sphere", {"string", "float", "float"}, "Body", [](void *p, Args &a) {
    positive("System.sphere", "radius and density", a[1].f); positive("System.sphere", "radius and density", a[2].f);
    BodyObj *b = new_body(S(p), a[0].s, "System.sphere");
    b->shape = Shape::Sphere; b->d[0] = a[1].f;
    set_mass_props(*b, a[2].f);
    return body_value(b);
  });
  method(r, "System", "cylinder", {"string", "float", "float", "float"}, "Body", [](void *p, Args &a) {
    for (int i = 1; i <= 3; i++) positive("System.cylinder", "radius, height and density", a[i].f);
    BodyObj *b = new_body(S(p), a[0].s, "System.cylinder");
    b->shape = Shape::Cylinder; b->d[0] = a[1].f; b->d[1] = a[2].f;
    set_mass_props(*b, a[3].f);
    return body_value(b);
  });
  method(r, "System", "floor", {"string", "string"}, "Body", [](void *p, Args &a) {
    auto &s = S(p);
    if (!s.mats.count(a[1].s)) throw dslvm::Error("System.floor: unknown material '" + a[1].s + "'");
    BodyObj *b = new_body(s, a[0].s, "System.floor");
    b->shape = Shape::Box; b->d[0] = 200; b->d[1] = 200; b->d[2] = 2;
    b->b->SetMass(1.0);
    b->b->SetPos(ch::ChVector3d(0, 0, -1));
    b->b->SetFixed(true);
    b->b->AddCollisionShape(chrono_types::make_shared<ch::ChCollisionShapeBox>(s.mats[a[1].s], 200.0, 200.0, 2.0));
    b->b->EnableCollision(true);
    b->collide = true;
    return body_value(b);
  });

  auto joint_common = [](SysObj &s, Args &a, const char *who) -> std::pair<BodyObj *, BodyObj *> {
    BodyObj &x = arg_body(a[1]), &y = arg_body(a[2]);
    if (x.sys != &s || y.sys != &s) throw dslvm::Error(std::string(who) + ": bodies belong to a different system");
    check_distinct(x, y, who);
    return {&x, &y};
  };
  // Lock-formulation joints: position (3 floats) and axis (3 floats) after the two bodies.
  auto lock_joint = [joint_common](const char *who, JKind kind, auto make) {
    return [=](void *p, Args &a) {
      auto &s = S(p);
      auto [x, y] = joint_common(s, a, who);
      for (int i = 3; i < 9; i++) finite(who, a[i].f);
      auto link = make();
      link->Initialize(x->b, y->b, axis_frame(vec(a, 3), vec(a, 6), who));
      return joint_value(new_joint(s, a[0].s, kind, link, who));
    };
  };
  method(r, "System", "revolute", {"string", "Body", "Body", "float", "float", "float", "float", "float", "float"}, "Joint",
         lock_joint("System.revolute", JKind::Revolute, [] { return chrono_types::make_shared<ch::ChLinkLockRevolute>(); }));
  method(r, "System", "prismatic", {"string", "Body", "Body", "float", "float", "float", "float", "float", "float"}, "Joint",
         lock_joint("System.prismatic", JKind::Prismatic, [] { return chrono_types::make_shared<ch::ChLinkLockPrismatic>(); }));
  method(r, "System", "lock", {"string", "Body", "Body", "float", "float", "float"}, "Joint", [joint_common](void *p, Args &a) {
    auto &s = S(p);
    auto [x, y] = joint_common(s, a, "System.lock");
    for (int i = 3; i < 6; i++) finite("System.lock", a[i].f);
    auto link = chrono_types::make_shared<ch::ChLinkLockLock>();
    link->Initialize(x->b, y->b, ch::ChFrame<>(vec(a, 3)));
    return joint_value(new_joint(s, a[0].s, JKind::Lock, link, "System.lock"));
  });
  method(r, "System", "spherical", {"string", "Body", "Body", "float", "float", "float"}, "Joint", [joint_common](void *p, Args &a) {
    auto &s = S(p);
    auto [x, y] = joint_common(s, a, "System.spherical");
    for (int i = 3; i < 6; i++) finite("System.spherical", a[i].f);
    auto link = chrono_types::make_shared<ch::ChLinkLockSpherical>();
    link->Initialize(x->b, y->b, ch::ChFrame<>(vec(a, 3)));
    return joint_value(new_joint(s, a[0].s, JKind::Spherical, link, "System.spherical"));
  });
  method(r, "System", "distance", {"string", "Body", "Body", "float", "float", "float", "float", "float", "float"}, "Joint",
         [joint_common](void *p, Args &a) {
    auto &s = S(p);
    auto [x, y] = joint_common(s, a, "System.distance");
    for (int i = 3; i < 9; i++) finite("System.distance", a[i].f);
    if ((vec(a, 3) - vec(a, 6)).Length() < 1e-9) throw dslvm::Error("System.distance: the two anchor points coincide");
    auto link = chrono_types::make_shared<ch::ChLinkDistance>();
    link->Initialize(x->b, y->b, false, vec(a, 3), vec(a, 6), true);
    return joint_value(new_joint(s, a[0].s, JKind::Distance, link, "System.distance"));
  });
  method(r, "System", "spring", {"string", "Body", "Body", "float", "float", "float"}, "Joint", [joint_common](void *p, Args &a) {
    auto &s = S(p);
    auto [x, y] = joint_common(s, a, "System.spring");
    finite("System.spring", a[3].f); finite("System.spring", a[4].f); finite("System.spring", a[5].f);
    if (a[3].f < 0 || a[4].f < 0 || a[5].f < 0) throw dslvm::Error("System.spring: stiffness, damping and rest length must be >= 0");
    auto link = chrono_types::make_shared<ch::ChLinkTSDA>();
    link->Initialize(x->b, y->b, true, ch::ChVector3d(0, 0, 0), ch::ChVector3d(0, 0, 0));
    link->SetSpringCoefficient(a[3].f);
    link->SetDampingCoefficient(a[4].f);
    link->SetRestLength(a[5].f);
    JointObj *j = new_joint(s, a[0].s, JKind::Spring, link, "System.spring");
    j->tsda = link; j->k = a[3].f; j->rest = a[5].f;
    return joint_value(j);
  });
  auto motor = [joint_common](const char *who, bool speed) {
    return [=](void *p, Args &a) {
      auto &s = S(p);
      auto [x, y] = joint_common(s, a, who);
      for (int i = 3; i < 9; i++) finite(who, a[i].f);
      auto fn = chrono_types::make_shared<ExprFunction>(a[9].s);
      ch::ChFrame<> f = axis_frame(vec(a, 3), vec(a, 6), who);
      std::shared_ptr<ch::ChLinkMotorRotation> mot;
      if (speed) { auto m = chrono_types::make_shared<ch::ChLinkMotorRotationSpeed>(); m->Initialize(y->b, x->b, f); m->SetSpeedFunction(fn); mot = m; }
      else { auto m = chrono_types::make_shared<ch::ChLinkMotorRotationAngle>(); m->Initialize(y->b, x->b, f); m->SetAngleFunction(fn); mot = m; }
      JointObj *j = new_joint(s, a[0].s, JKind::Motor, mot, who);
      j->motor = mot;
      return joint_value(j);
    };
  };
  method(r, "System", "motor_speed", {"string", "Body", "Body", "float", "float", "float", "float", "float", "float", "string"}, "Joint",
         motor("System.motor_speed", true));
  method(r, "System", "motor_angle", {"string", "Body", "Body", "float", "float", "float", "float", "float", "float", "string"}, "Joint",
         motor("System.motor_angle", false));

  method(r, "System", "record", {"string", "string"}, "System", [](void *p, Args &a) {
    auto &s = S(p);
    need_not_started(s, "System.record");
    Record rec{};
    for (auto &b : s.bodies) if (b->name == a[0].s) { rec.is_body = true; rec.body = b.get(); }
    for (auto &j : s.joints) if (j->name == a[0].s) { rec.is_body = false; rec.joint = j.get(); }
    if (!rec.body && !rec.joint) throw dslvm::Error("System.record: no body or joint named '" + a[0].s + "'");
    rec.cols = lmphysics::split_names(a[1].s);
    if (rec.cols.empty()) throw dslvm::Error("System.record: no columns given");
    for (auto &c : rec.cols) {  // validate names now, not at the first step
      if (rec.is_body) body_value_of(*rec.body, c); else joint_value_of(*rec.joint, c);
      s.header.push_back(a[0].s + "." + c);
    }
    s.recs.push_back(std::move(rec));
    return sys_value(p);
  });
  method(r, "System", "step", {}, "System", [](void *p, Args &) { do_step(S(p)); return sys_value(p); });
  method(r, "System", "run", {"float"}, "System", [](void *p, Args &a) {
    auto &s = S(p);
    finite("System.run", a[0].f);
    double t_end = a[0].f;
    if (t_end < s.sys->GetChTime()) throw dslvm::Error("System.run: end time is before the current time");
    if ((t_end - s.sys->GetChTime()) / s.dt > 5e7) throw dslvm::Error("System.run: too many steps");
    start(s);
    while (s.sys->GetChTime() + 0.5 * s.dt < t_end) do_step(s);
    return sys_value(p);
  });
  method(r, "System", "time", {}, "float", [](void *p, Args &) { return Value::real(S(p).sys->GetChTime()); });
  method(r, "System", "energy", {}, "float", [](void *p, Args &) { return Value::real(total_energy(S(p))); });
  method(r, "System", "contacts", {}, "int", [](void *p, Args &) { return Value::integer((int64_t)S(p).sys->GetNumContacts()); });
  method(r, "System", "save_csv", {"string"}, "System", [](void *p, Args &a) {
    auto &s = S(p);
    start(s);
    std::ofstream f(a[0].s, std::ios::binary);
    if (!f) throw dslvm::Error("System.save_csv: cannot write '" + a[0].s + "'");
    for (size_t i = 0; i < s.header.size(); i++) f << (i ? "," : "") << s.header[i];
    f << "\n";
    for (auto &row : s.rows) {
      for (size_t i = 0; i < row.size(); i++) f << (i ? "," : "") << fmt12(row[i]);
      f << "\n";
    }
    if (!f) throw dslvm::Error("System.save_csv: write failed for '" + a[0].s + "'");
    return sys_value(p);
  });

  // ---------------------------------------------------------------- Body
  auto self = [](void *p) -> ch::ChBody & { return *B(p).b; };
  method(r, "Body", "pos", {"float", "float", "float"}, "Body", [self](void *p, Args &a) {
    for (int i = 0; i < 3; i++) finite("Body.pos", a[i].f);
    need_not_started(*B(p).sys, "Body.pos"); self(p).SetPos(vec(a, 0)); return Value::object("Body", p);
  });
  method(r, "Body", "vel", {"float", "float", "float"}, "Body", [self](void *p, Args &a) {
    for (int i = 0; i < 3; i++) finite("Body.vel", a[i].f);
    self(p).SetPosDt(vec(a, 0)); return Value::object("Body", p);
  });
  method(r, "Body", "rot_axis", {"float", "float", "float", "float"}, "Body", [self](void *p, Args &a) {
    for (int i = 0; i < 4; i++) finite("Body.rot_axis", a[i].f);
    ch::ChVector3d ax = vec(a, 0);
    if (ax.Length() < 1e-12) throw dslvm::Error("Body.rot_axis: axis must not be zero");
    need_not_started(*B(p).sys, "Body.rot_axis");
    self(p).SetRot(ch::QuatFromAngleAxis(a[3].f, ax.GetNormalized())); return Value::object("Body", p);
  });
  method(r, "Body", "omega", {"float", "float", "float"}, "Body", [self](void *p, Args &a) {
    for (int i = 0; i < 3; i++) finite("Body.omega", a[i].f);
    self(p).SetAngVelParent(vec(a, 0)); return Value::object("Body", p);
  });
  method(r, "Body", "fixed", {"bool"}, "Body", [self](void *p, Args &a) { self(p).SetFixed(a[0].b); return Value::object("Body", p); });
  method(r, "Body", "mass_props", {"float", "float", "float", "float"}, "Body", [self](void *p, Args &a) {
    for (int i = 0; i < 4; i++) positive("Body.mass_props", "mass and inertia", a[i].f);
    self(p).SetMass(a[0].f); self(p).SetInertiaXX(vec(a, 1)); return Value::object("Body", p);
  });
  method(r, "Body", "collide", {"string"}, "Body", [](void *p, Args &a) {
    auto &bo = B(p);
    auto it = bo.sys->mats.find(a[0].s);
    if (it == bo.sys->mats.end()) throw dslvm::Error("Body.collide: unknown material '" + a[0].s + "'");
    if (bo.shape == Shape::None) throw dslvm::Error("Body.collide: body '" + bo.name + "' has no shape (ground bodies cannot collide)");
    if (bo.collide) throw dslvm::Error("Body.collide: body '" + bo.name + "' already collides");
    if (bo.shape == Shape::Box) bo.b->AddCollisionShape(chrono_types::make_shared<ch::ChCollisionShapeBox>(it->second, bo.d[0], bo.d[1], bo.d[2]));
    else if (bo.shape == Shape::Sphere) bo.b->AddCollisionShape(chrono_types::make_shared<ch::ChCollisionShapeSphere>(it->second, bo.d[0]));
    else  // Chrono 9's collision cylinder runs along the shape's z axis; ours (and the inertia) along the body's y axis
      bo.b->AddCollisionShape(chrono_types::make_shared<ch::ChCollisionShapeCylinder>(it->second, bo.d[0], bo.d[1]),
                              ch::ChFrame<>(ch::VNULL, ch::QuatFromAngleX(-ch::CH_PI_2)));
    bo.b->EnableCollision(true);
    bo.collide = true;
    return Value::object("Body", p);
  });
  method(r, "Body", "mass", {}, "float", [self](void *p, Args &) { return Value::real(self(p).GetMass()); });
  getter(r, "Body", "x"); getter(r, "Body", "y"); getter(r, "Body", "z");
  getter(r, "Body", "vx"); getter(r, "Body", "vy"); getter(r, "Body", "vz");
  getter(r, "Body", "wx"); getter(r, "Body", "wy"); getter(r, "Body", "wz");
  getter(r, "Body", "lx"); getter(r, "Body", "ly"); getter(r, "Body", "lz");
  getter(r, "Body", "speed"); getter(r, "Body", "ke");

  // ---------------------------------------------------------------- Joint
  getter(r, "Joint", "angle"); getter(r, "Joint", "length"); getter(r, "Joint", "force"); getter(r, "Joint", "torque");
  method(r, "Joint", "reaction_x", {}, "float", [](void *p, Args &) { return Value::real(joint_value_of(J(p), "fx")); });
  method(r, "Joint", "reaction_y", {}, "float", [](void *p, Args &) { return Value::real(joint_value_of(J(p), "fy")); });
  method(r, "Joint", "reaction_z", {}, "float", [](void *p, Args &) { return Value::real(joint_value_of(J(p), "fz")); });
}

const char *usage = "usage: lmphysics --version | --notices | --dsl-schema [--json] | --dsl-signatures | [--dry-run] --dsl FILE [FILE ...]\n";
}  // namespace

int main(int argc, char **argv) {
#ifdef _WIN32
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
#endif
  Host host;
  dslvm::Registry reg;
  register_host(reg, host);
  std::string a1 = argc > 1 ? argv[1] : "";
  if (argc == 2 && a1 == "--version") { std::cout << "lmphysics " LMPHYSICS_VERSION "\n"; return std::cout ? 0 : 4; }
  if (argc == 2 && a1 == "--notices") {
    std::cout.write(reinterpret_cast<const char *>(lmphysics::embedded_notices), (std::streamsize)lmphysics::embedded_notices_size);
    return std::cout ? 0 : 4;
  }
  if (argc >= 2 && a1 == "--dsl-schema") {
    if (argc == 2) { for (const auto &s : reg.signatures()) std::cout << s << "\n"; return std::cout ? 0 : 4; }
    if (argc == 3 && std::string(argv[2]) == "--json") {
      std::cout.write(reinterpret_cast<const char *>(lmphysics::embedded_schema), (std::streamsize)lmphysics::embedded_schema_size);
      return std::cout ? 0 : 4;
    }
    std::cerr << usage; return 2;
  }
  if (argc == 2 && a1 == "--dsl-signatures") { for (const auto &s : reg.signatures()) std::cout << s << "\n"; return 0; }
  int first = 2;
  if (argc >= 2 && a1 == "--dry-run") first = 3;  // accepted for symmetry: nothing here has side effects beyond files
  if (argc <= first || std::string(argv[first - 1]) != "--dsl") { std::cerr << usage; return 2; }
  for (int i = first; i < argc; i++)
    if (std::string(argv[i]).empty() || std::string(argv[i]).rfind("--", 0) == 0) { std::cerr << usage; return 2; }
  const std::string schema(reinterpret_cast<const char *>(lmphysics::embedded_schema), lmphysics::embedded_schema_size);
  dslvm::Context context;
  context.set("phys", &host);
  std::vector<dslvm::Program> programs;
  for (int i = first; i < argc; i++) {
    try { programs.push_back(dslvm::Program::load(dslvm::read_file(argv[i]), schema, reg)); }
    catch (const dslvm::Error &e) { return dslvm::report_error("load", e); }
  }
  for (const auto &p : programs) {
    try { p.run(context, reg); }
    catch (const dslvm::Error &e) { return dslvm::report_error("run", e); }
    dslvm::report_ok();
  }
  return 0;
}
