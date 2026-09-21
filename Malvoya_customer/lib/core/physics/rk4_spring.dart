/**
 * Runge-Kutta 4th Order (RK4) Spring Kinematics
 * Replaces linear animations with physical spring equations, preserving user finger
 * velocity during drawer dismissals and SKU chip interactions.
 */
class RK4Spring {
  final double mass;
  final double stiffness;
  final double damping;

  RK4Spring({
    this.mass = 1.0,
    this.stiffness = 320.0,
    this.damping = 24.0,
  });

  double acceleration(double pos, double vel, double target) {
    return (-stiffness * (pos - target) - damping * vel) / mass;
  }

  void step(double dt, SpringState current, double target) {
    double p1 = current.pos;
    double v1 = current.vel;
    double a1 = acceleration(p1, v1, target);

    double p2 = p1 + 0.5 * v1 * dt;
    double v2 = v1 + 0.5 * a1 * dt;
    double a2 = acceleration(p2, v2, target);

    double p3 = p1 + 0.5 * v2 * dt;
    double v3 = v1 + 0.5 * a2 * dt;
    double a3 = acceleration(p3, v3, target);

    double p4 = p1 + v3 * dt;
    double v4 = v1 + a3 * dt;
    double a4 = acceleration(p4, v4, target);

    current.pos += (dt / 6.0) * (v1 + 2 * (v2 + v3) + v4);
    current.vel += (dt / 6.0) * (a1 + 2 * (a2 + a3) + a4);
  }
}

class SpringState {
  double pos;
  double vel;
  SpringState(this.pos, this.vel);
}
