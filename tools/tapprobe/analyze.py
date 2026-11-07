"""Analisi della fase 0 di Knock: accuratezza di pattern e zone dai dati di tapprobe.
Uso: python3 -I analyze.py data/taps.csv
"""
import csv
import sys
from collections import Counter, defaultdict

import numpy as np

ZONES = ["alto_sx", "alto_dx", "basso_sx", "basso_dx"]
path = sys.argv[1] if len(sys.argv) > 1 else "data/taps.csv"
rows = list(csv.DictReader(open(path)))
cols = list(rows[0].keys())
audio_cols = ["level_db", "peak_db", "centroid", "decay_ms"] + [c for c in cols if c.startswith("b") and c[1:].isdigit()]
imu_cols = [c for c in cols if c[:2] in ("ax", "ay", "az", "gx", "gy", "gz")]

# Raggruppa per pattern
patterns = defaultdict(list)
for r in rows:
    patterns[(r["label"], r["pattern"])].append(r)

# 1. Pattern: doppio/triplo riconosciuto?
print("== Pattern (doppio/triplo) ==")
ok = tot = 0
for z in ZONES:
    for kind, n in (("doppio", 2), ("triplo", 3)):
        sizes = [len(v) for (lab, _), v in patterns.items() if lab == f"{z}:{kind}"]
        good = sum(s == n for s in sizes)
        ok += good
        tot += len(sizes)
        print(f"  {z:9s} {kind}: {good}/{len(sizes)} corretti  {dict(Counter(sizes))}")
if tot:
    print(f"  Totale: {ok}/{tot} = {ok / tot:.0%}")
noise = Counter(len(v) for (lab, _), v in patterns.items() if lab.startswith("rumore"))
fp = noise.get(2, 0) + noise.get(3, 0)
print(f"  Falsi positivi durante la digitazione: {fp} pattern da 2-3 tap (gruppi trovati: {dict(noise)})")

# 2. Zone: un esempio per pattern (media dei suoi tap), solo pattern corretti
X_a, X_i, y = [], [], []
for (lab, _), v in patterns.items():
    z, _, kind = lab.partition(":")
    if z not in ZONES:
        continue
    if len(v) != (2 if kind == "doppio" else 3):
        continue
    X_a.append(np.mean([[float(r[c]) for c in audio_cols] for r in v], axis=0))
    X_i.append(np.mean([[float(r[c]) for c in imu_cols] for r in v], axis=0))
    y.append(ZONES.index(z))
y = np.array(y)
if len(y) < 8:
    sys.exit("Troppi pochi pattern per valutare le zone.")
X_a, X_i = np.array(X_a), np.array(X_i)
imu_present = np.abs(X_i).sum() > 0


def loo_knn(X, y, k=5):
    """kNN con leave-one-out, feature standardizzate."""
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    D = ((Z[:, None, :] - Z[None, :, :]) ** 2).sum(-1)
    np.fill_diagonal(D, np.inf)
    pred = []
    for i in range(len(y)):
        nn = np.argsort(D[i])[:k]
        votes = Counter(y[nn])
        pred.append(votes.most_common(1)[0][0])
    return np.array(pred)


def report(name, X):
    p = loo_knn(X, y)
    acc = (p == y).mean()
    lr = ((p % 2) == (y % 2)).mean()       # sx/dx
    tb = ((p // 2) == (y // 2)).mean()     # alto/basso
    print(f"\n== Zone con {name}: 4 zone {acc:.0%}, sinistra/destra {lr:.0%}, alto/basso {tb:.0%} (n={len(y)}) ==")
    m = np.zeros((4, 4), int)
    for a, b in zip(y, p):
        m[a, b] += 1
    print("  vero \\ predetto  " + "  ".join(f"{z:>8s}" for z in ZONES))
    for i, z in enumerate(ZONES):
        print(f"  {z:16s} " + "  ".join(f"{v:8d}" for v in m[i]))


if np.abs(X_a).sum() > 0:
    report("audio", X_a)
else:
    print("\nAudio: non registrato (modalità solo sensori).")
if imu_present:
    report("IMU", X_i)
    if np.abs(X_a).sum() > 0:
        report("audio + IMU", np.hstack([X_a, X_i]))
    print("\n== Picco medio accelerometro per zona (g, segno incluso) ==")
    ix = [imu_cols.index(c) for c in ("ax_pk", "ay_pk", "az_pk")]
    for i, z in enumerate(ZONES):
        v = X_i[y == i][:, ix].mean(0) if (y == i).any() else [0, 0, 0]
        print(f"  {z:9s} x {v[0]:+.4f}  y {v[1]:+.4f}  z {v[2]:+.4f}")
else:
    print("\nIMU: nessun dato registrato.")
