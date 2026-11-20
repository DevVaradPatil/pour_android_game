import 'sand_sim.dart';

const int gridW = 240, gridH = 420;

/// Phase 1 toy: a closed glass box with a few shelves and four colored blocks of sand.
SandSim toyBox({int seed = 1}) {
  final sim = SandSim(gridW, gridH, seed: seed);
  const wall = Cell.wall;
  sim.fillRect(0, 0, gridW, 3, wall);
  sim.fillRect(0, gridH - 3, gridW, 3, wall);
  sim.fillRect(0, 0, 3, gridH, wall);
  sim.fillRect(gridW - 3, 0, 3, gridH, wall);
  // Shelves.
  sim.line(30, 230, 110, 260, wall);
  sim.line(130, 290, 210, 260, wall);
  sim.line(60, 340, 180, 340, wall);
  // A funnel in the middle.
  sim.line(70, 170, 112, 200, wall);
  sim.line(170, 170, 128, 200, wall);
  // Sand blocks (blue, yellow, red, green).
  for (var i = 0; i < 4; i++) {
    sim.fillRect(14 + i * 55, 20, 48, 110, Cell.firstSand + i);
  }
  return sim;
}
