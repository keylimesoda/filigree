#!/usr/bin/env python3
"""Compute Filigree's dive points and write their reference orbits.

A dive point is a Misiurewicz point c* of the Mandelbrot set, where the
critical orbit lands after k steps on a repelling cycle of period p, or a
repelling fixed point of a Julia set. The picture repeats itself about such a
point: zoomed in by |rho^m| (rho is the cycle's multiplier, m is chosen so the
repeat barely turns) and turned by -arg(rho^m), the view matches itself with
its escape counts m*p higher. Background.qml loops a dive there forever.

fractal.frag follows every pixel as a small offset from the dive point's own
orbit (perturbation). The orbit is known exactly, so float32 stays accurate at
any depth. This script finds each point to 60 digits, then rewrites the orbit
table between the ORBIT markers in fractal.frag and prints the divePoints
entries for Background.qml.

Requires mpmath (only needed to add or change dive points):
    python3 divepoints.py [--write]
"""
import argparse
from pathlib import Path
import re

import mpmath as mp

mp.mp.dps = 60
TIDE_PERIOD = 2    # fractal.frag's tidePeriod
STEP = 1.15        # target zoom per keyframe


def misiurewicz(guess, k, p):
    """Solve z_{k+p}(c) = z_k(c) by Newton's method near guess."""
    c = mp.mpc(guess)
    for _ in range(200):
        z, dz = mp.mpc(0), mp.mpc(0)
        zs, dzs = [z], [dz]
        for _ in range(k + p):
            dz = 2 * z * dz + 1
            z = z * z + c
            zs.append(z)
            dzs.append(dz)
        step = (zs[k + p] - zs[k]) / (dzs[k + p] - dzs[k])
        c -= step
        if abs(step) < mp.mpf(10) ** -50:
            break
    orbit = [mp.mpc(0)]
    for _ in range(k + p - 1):
        orbit.append(orbit[-1] ** 2 + c)
    return c, orbit


# name, kind, point guess, preperiod, period, loop power m, depth (the span
# at which one loop matches the next closely enough to fade between them),
# Julia constant.
POINTS = [
    ("filigree", "mandelbrot", mp.mpc(-0.10109636, 0.95628651), 4, 1, 3, 4.3e-4, None),
    ("seahorse", "mandelbrot", mp.mpc(-0.77568377, 0.13646737), 24, 1, 25, 1.0e-5, None),
    ("julia", "julia", None, 0, 1, 21, 1.1e-3, mp.mpc(mp.mpf("-0.8"), mp.mpf("0.156"))),
]


def build():
    entries, table, start = [], [], 0
    for name, kind, guess, k, p, m, depth, jc in POINTS:
        if kind == "julia":
            # The repelling fixed point alpha of z^2 + c.
            point = (1 - mp.sqrt(1 - 4 * jc)) / 2
            orbit = [point]
        else:
            point, orbit = misiurewicz(guess, k, p)
        rho = mp.mpc(1)
        for z in orbit[k:k + p]:
            rho *= 2 * z
        loop = rho ** m
        entries.append(dict(name=name, julia=jc, point=point, start=start, pre=k, period=p,
                            scale=abs(loop), turn=-mp.arg(loop), phase=m * p / TIDE_PERIOD,
                            steps=int(round(float(mp.log(abs(loop)) / mp.log(STEP)))),
                            depth=depth, rho=rho, closest=min(abs(z) for z in orbit if z != 0)))
        table.extend(orbit)
        start += len(orbit)
    return entries, table


def glsl_table(entries, table):
    names = ", ".join("%s %d" % (e["name"], e["start"]) for e in entries)
    lines = ["const int ORBIT_LENGTH = %d;" % (len(table) + 1),
             "// Starts: %s; the last entry is plain iteration." % names,
             "const vec2 ORBIT[ORBIT_LENGTH] = vec2[]("]
    lines += ["    vec2(%.9e, %.9e)," % (float(z.real), float(z.imag)) for z in table]
    lines.append("    vec2(0.0, 0.0)")
    lines.append(");")
    return "\n".join(lines)


def qml_table(entries):
    rows = []
    for e in entries:
        julia = "julia: false"
        if e["julia"] is not None:
            julia = "julia: true, juliaReal: %s, juliaImag: %s" % (
                mp.nstr(e["julia"].real, 17), mp.nstr(e["julia"].imag, 17))
        rows.append("    {name: \"%s\", %s, x: %s, y: %s,\n"
                    "     scale: %.6f, turn: %.6f, phase: %s, steps: %d, depth: %s,\n"
                    "     orbitStart: %d, orbitPre: %d, orbitPeriod: %d}"
                    % (e["name"], julia, mp.nstr(e["point"].real, 17), mp.nstr(e["point"].imag, 17),
                       float(e["scale"]), float(e["turn"]), repr(e["phase"]), e["steps"],
                       repr(e["depth"]), e["start"], e["pre"], e["period"]))
    return "  readonly property var divePoints: [\n" + ",\n".join(rows) + "\n  ]"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="rewrite the orbit table in fractal.frag")
    args = parser.parse_args()
    entries, table = build()
    for e in entries:
        print("// %-9s pre %2d period %d |rho| %.6f arg %.6f -> scale %.5f turn %+.5f steps %2d, closest |Z| %.4f"
              % (e["name"], e["pre"], e["period"], float(abs(e["rho"])), float(mp.arg(e["rho"])),
                 float(e["scale"]), float(e["turn"]), e["steps"], float(e["closest"])))
    for e in entries:
        # fractal.frag rebases once an offset passes 0.05; an orbit value
        # smaller than this would let offsets swamp z before that.
        if e["closest"] < 0.15:
            raise SystemExit("%s: the orbit comes within %.3f of zero, too close for the 0.05 rebase threshold"
                             % (e["name"], float(e["closest"])))
    block = glsl_table(entries, table)
    if args.write:
        shader = Path(__file__).with_name("fractal.frag")
        text = shader.read_text(encoding="utf-8")
        new, count = re.subn(r"(// ORBIT BEGIN\n).*?(\n// ORBIT END)", lambda m: m.group(1) + block + m.group(2),
                             text, flags=re.S)
        if count != 1:
            raise SystemExit("fractal.frag needs one ORBIT BEGIN / ORBIT END block")
        shader.write_text(new, encoding="utf-8")
        print("// wrote %d orbit entries to %s" % (len(table) + 1, shader))
    else:
        print(block)
    print(qml_table(entries))


if __name__ == "__main__":
    main()
