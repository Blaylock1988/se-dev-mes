// PB_TurnTest.cs - Programmable Block script: measures how an aircraft's FLIGHT PATH follows its nose during a commanded turn.
// Used to pick autopilot rotation caps and to see how much a given airframe turns its path in yaw vs pitch.
// (Part of the se-dev-mes skill, references/aircraft_behaviors_and_tuning.md section 6.)
//
// Setup: paste into a Programmable Block on the aircraft's grid. The grid needs a cockpit or remote control and its gyros.
//        Test the NPC variant of the aircraft (gyros at full power, no active control-surface mods), in steady level flight at the speed you care about.
// Run with an argument:   yaw 35    -> yaw at 0.35 rad/s
//                         pitch 30  -> pitch at 0.30 rad/s
//                         stop      -> release the gyros
// ALWAYS give a number: the argument is rate x 100 in rad/s. With no number the rate defaults to 30 rad/s.
// Output: start nose pitch/roll (how level you were), then at the 90 and 180 degree marks of nose rotation:
//   time, flight-path change in degrees, speed, altitude change in meters (negative = lost height).
// Yaw is measured as compass-heading change about true vertical; pitch as total nose angle.
// Tested in game on forward-thrust propeller aircraft; not tested on hover craft.

IMyShipController c; List<IMyGyro> g = new List<IMyGyro>();
Vector3D f0, v0; double t, t90, t180, p90, s90, p180, s180, h0, d90, d180, pit0, rol0; float rate; bool run; string mode = "";
public Program() {
  Runtime.UpdateFrequency = UpdateFrequency.Update1;
  var cs = new List<IMyShipController>();
  GridTerminalSystem.GetBlocksOfType(cs, x => x.CubeGrid == Me.CubeGrid);
  if (cs.Count > 0) c = cs[0];
  GridTerminalSystem.GetBlocksOfType(g, x => x.CubeGrid == Me.CubeGrid);
}
void Drive(Vector3D worldAxis, float r) {
  foreach (var gy in g) {
    var l = Vector3D.TransformNormal(worldAxis * r, MatrixD.Transpose(gy.WorldMatrix));
    gy.GyroOverride = r != 0; gy.Pitch = (float)l.X; gy.Yaw = (float)l.Y; gy.Roll = (float)l.Z; } }
double Alt() { double h; c.TryGetPlanetElevation(MyPlanetElevation.Sealevel, out h); return h; }
Vector3D UpV() { var gv = c.GetNaturalGravity(); return gv.LengthSquared() > 0.01 ? -Vector3D.Normalize(gv) : c.WorldMatrix.Up; }
Vector3D Flat(Vector3D v, Vector3D up) { var h = v - Vector3D.Dot(v, up) * up; return h.LengthSquared() > 1e-6 ? Vector3D.Normalize(h) : v; }
double VAng() {
  var v = c.GetShipVelocities().LinearVelocity;
  if (v0.LengthSquared() < 1 || v.LengthSquared() < 1) return 0;
  return Math.Acos(MathHelper.Clamp(Vector3D.Dot(Vector3D.Normalize(v0), Vector3D.Normalize(v)), -1, 1)) * 57.2958; }
public void Main(string a) {
  if (c == null) { Echo("No cockpit or remote control on this grid"); return; }
  var w = a.Split(' ');
  if (w[0] == "pitch" || w[0] == "yaw") {
    mode = w[0]; rate = w.Length > 1 ? int.Parse(w[1]) / 100f : 30f;
    f0 = c.WorldMatrix.Forward; v0 = c.GetShipVelocities().LinearVelocity; h0 = Alt();
    var up = UpV();
    pit0 = Math.Asin(MathHelper.Clamp(Vector3D.Dot(f0, up), -1, 1)) * 57.2958;
    rol0 = Math.Asin(MathHelper.Clamp(Vector3D.Dot(c.WorldMatrix.Right, up), -1, 1)) * 57.2958;
    t = t90 = t180 = p90 = s90 = p180 = s180 = d90 = d180 = 0; run = true; }
  if (a == "stop") { run = false; Drive(Vector3D.Up, 0); }
  if (run) {
    t += Runtime.TimeSinceLastRun.TotalSeconds;
    var up = UpV();
    Drive(mode == "yaw" ? up : c.WorldMatrix.Right, rate);
    double ang = mode == "yaw"
      ? Math.Acos(MathHelper.Clamp(Vector3D.Dot(Flat(f0, up), Flat(c.WorldMatrix.Forward, up)), -1, 1)) * 57.2958
      : Math.Acos(MathHelper.Clamp(Vector3D.Dot(f0, c.WorldMatrix.Forward), -1, 1)) * 57.2958;
    if (ang >= 90 && t90 == 0) { t90 = t; p90 = VAng(); s90 = c.GetShipSpeed(); d90 = Alt() - h0; }
    if (ang >= 175) { t180 = t; p180 = VAng(); s180 = c.GetShipSpeed(); d180 = Alt() - h0; run = false; Drive(Vector3D.Up, 0); }
  }
  Echo($"{c.CustomName}, speed {c.GetShipSpeed():F0}, alt {Alt():F0}\nstart nose pitch {pit0:F0} deg, roll {rol0:F0} deg\n90deg at {t90:F1}s: path {p90:F0}, {s90:F0} m/s, alt {d90:F0} m\n180deg at {t180:F1}s: path {p180:F0}, {s180:F0} m/s, alt {d180:F0} m");
}
