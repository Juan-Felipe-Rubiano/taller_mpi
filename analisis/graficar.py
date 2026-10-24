"""Figuras a partir de resultados/*.csv (ejecutar estadisticas.py no es necesario).
Uso:  python3 analisis/graficar.py [--resultados resultados] [--figuras figuras]
Las barras de error son el IC95 de la media; los tiempos son de cómputo (columna t_us).
Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. """
import argparse, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from datos import cargar, tamanos_cache
from estadisticas import resumen

COL = {1: "#4c78a8", 2: "#f58518", 4: "#54a24b"}          # color por número de hilos
plt.rcParams.update({"figure.dpi": 100, "axes.grid": True, "grid.alpha": .3,
                     "axes.spines.top": False, "axes.spines.right": False})
FIG = "figuras"


def guardar(fig, nombre):
    if fig.get_layout_engine() is None:
        fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(f"{FIG}/{nombre}.{ext}", dpi=200)
    plt.close(fig)


def fig_tiempos(r, s, alg):
    """Tiempo vs workers, barras agrupadas por hilos; una fila por modelo, una columna por N."""
    d = r[(r.sistema == s) & (r.algoritmo == alg) & (r.modelo != "mpi")]
    Ns, mods = sorted(d.N.unique()), ["omp", "pth"]
    if d.empty:
        return
    fig, ax = plt.subplots(2, len(Ns), figsize=(3.2 * len(Ns), 5.5), squeeze=False)
    for i, m in enumerate(mods):
        for j, n in enumerate(Ns):
            a = ax[i][j]
            x = d[(d.modelo == m) & (d.N == n)]
            for k, h in enumerate(sorted(x.hilos.unique())):
                y = x[x.hilos == h].sort_values("workers")
                a.bar(np.arange(len(y)) + (k - 1) * 0.27, y.media, 0.27, color=COL.get(h, "gray"),
                      yerr=(y.ic95_sup - y.ic95_inf) / 2, capsize=2, label=f"{h} hilos")
                a.set_xticks(np.arange(len(y)), y.workers.astype(str))
            a.set_title(f"{'OpenMP' if m == 'omp' else 'Pthreads'}, N={n}", fontsize=9)
            a.set_xlabel("workers"); a.set_ylabel("tiempo (s)" if j == 0 else "")
            if i == 0 and j == 0:
                a.legend(fontsize=7)
    fig.suptitle(f"Tiempo de cómputo, algoritmo {alg}, sistema {s}")
    guardar(fig, f"tiempos_{alg}_{s}")


def mapa(a, tabla, titulo, fmt, **kw):
    im = a.imshow(tabla.values, aspect="auto", **kw)
    a.set_xticks(range(tabla.shape[1]), [str(c) for c in tabla.columns])
    a.set_yticks(range(tabla.shape[0]), [str(c) for c in tabla.index])
    a.set_xlabel("hilos"); a.set_ylabel("workers"); a.set_title(titulo, fontsize=9); a.grid(False)
    for (i, j), v in np.ndenumerate(tabla.values):
        if np.isfinite(v):
            a.text(j, i, fmt.format(v), ha="center", va="center", fontsize=8)
    return im


def fig_eficiencia(r, s):
    d = r[(r.sistema == s) & (r.modelo != "mpi")]
    if d.empty:
        return
    n = d.N.max()
    fig, ax = plt.subplots(2, 2, figsize=(7, 6), layout="constrained")
    for a, (m, alg) in zip(ax.flat, [(m, g) for m in ("omp", "pth") for g in ("FxC", "FxT")]):
        t = d[(d.modelo == m) & (d.algoritmo == alg) & (d.N == n)].pivot(index="workers", columns="hilos", values="eficiencia")
        im = mapa(a, t, f"{'OpenMP' if m == 'omp' else 'Pthreads'} {alg}", "{:.2f}", cmap="viridis", vmin=0, vmax=1.1)
    fig.colorbar(im, ax=ax, label="eficiencia = speedup / (workers·hilos)", shrink=.8)
    fig.suptitle(f"Eficiencia respecto a W=1, H=1 (N={n}), sistema {s}")
    guardar(fig, f"eficiencia_{s}")


def fig_algoritmos(r, s):
    """Razón de medianas FxC/FxT por N, para W=1 y W máximo (H=1)."""
    d = r[(r.sistema == s) & (r.hilos == 1)]
    wmax = d.workers.max()
    fig, ax = plt.subplots(1, 2, figsize=(8, 3.5), sharey=True)
    for a, w in zip(ax, (1, wmax)):
        for m, c in (("mpi", "#4c78a8"), ("omp", "#f58518"), ("pth", "#54a24b")):
            x = d[(d.modelo == m) & (d.workers == w)].pivot(index="N", columns="algoritmo", values="mediana")
            if {"FxC", "FxT"} <= set(x.columns):
                a.plot(x.index, x.FxC / x.FxT, "o-", color=c, label=m)
        a.axhline(1, color="k", lw=.8); a.set_xscale("log", base=2); a.set_title(f"{w} worker(s), 1 hilo", fontsize=9)
        a.set_xlabel("N"); a.set_ylabel("mediana FxC / mediana FxT")
    ax[0].legend(fontsize=8)
    fig.suptitle(f"¿Cuántas veces más lento es FxC que FxT? ({s})")
    guardar(fig, f"fxc_vs_fxt_{s}")


def fig_omp_pth(r, s):
    d = r[(r.sistema == s) & (r.modelo.isin(["omp", "pth"]))]
    if d.empty:
        return
    n = d.N.max()
    fig, ax = plt.subplots(1, 2, figsize=(7.5, 3.8), layout="constrained")
    for a, alg in zip(ax, ("FxC", "FxT")):
        t = d[(d.algoritmo == alg) & (d.N == n)].pivot_table(index=["workers", "hilos"], columns="modelo", values="mediana")
        t = (t.omp / t.pth).unstack("hilos")
        lim = max(0.1, np.nanmax(np.abs(np.log2(t.values))))
        im = mapa(a, np.log2(t), f"{alg}, N={n}", "{:+.2f}", cmap="RdBu_r", vmin=-lim, vmax=lim)
    fig.colorbar(im, ax=ax, label="log2(t_OpenMP / t_Pthreads)  (<0: OpenMP más rápido)", shrink=.8)
    fig.suptitle(f"OpenMP frente a Pthreads ({s})")
    guardar(fig, f"omp_vs_pth_{s}")


def fig_dispersion(df, r, s):
    """Izq: coeficiente de variación por N. Der: tiempo/mediana contra la ronda (deriva)."""
    d = df[df.sistema == s].merge(r[["sistema", "binario", "N", "workers", "hilos", "mediana"]],
                                  on=["sistema", "binario", "N", "workers", "hilos"])
    d["rel"] = d.t / d.mediana
    fig, ax = plt.subplots(1, 2, figsize=(9, 3.6))
    rs = r[r.sistema == s]
    Ns = sorted(rs.N.unique())
    ax[0].boxplot([rs[rs.N == n].cv_pct.dropna() for n in Ns], tick_labels=[str(n) for n in Ns])
    ax[0].set_xlabel("N"); ax[0].set_ylabel("CV (%) de cada configuración")
    ax[0].set_title("Dispersión por tamaño", fontsize=9)
    ax[1].scatter(d.ronda, d.rel, s=3, alpha=.15, color="#4c78a8")
    ax[1].plot(*zip(*d.groupby("ronda").rel.median().items()), color="k", lw=1.5, label="mediana de la ronda")
    ax[1].set_ylim(.8, 1.4); ax[1].set_xlabel("ronda"); ax[1].set_ylabel("tiempo / mediana de su configuración")
    ax[1].set_title("Deriva en el tiempo", fontsize=9); ax[1].legend(fontsize=8)
    fig.suptitle(f"Variabilidad de las mediciones ({s})")
    guardar(fig, f"dispersion_{s}")


def fig_gflops(r, s, dir_res):
    d = r[(r.sistema == s) & (r.modelo == "mpi") & (r.workers == 1)]
    fig, a = plt.subplots(figsize=(5.5, 3.6))
    for alg, c in (("FxC", "#4c78a8"), ("FxT", "#f58518")):
        x = d[d.algoritmo == alg].sort_values("N")
        a.plot(x.N, x.gflops, "o-", color=c, label=alg)
    for nivel, n in tamanos_cache(os.path.join(dir_res), s).items():
        if nivel in ("L2", "L3") and d.N.min() / 2 <= n <= d.N.max() * 2:
            a.axvline(n, ls="--", color="gray"); a.text(n, a.get_ylim()[1], f" {nivel}", va="top", fontsize=8)
    a.set_xscale("log", base=2); a.set_xticks(sorted(d.N.unique()), [str(n) for n in sorted(d.N.unique())])
    a.set_xlabel("N"); a.set_ylabel("GFLOPS (2N³ / t)"); a.legend()
    a.set_title(f"Rendimiento con 1 worker y la jerarquía de memoria ({s})", fontsize=9)
    guardar(fig, f"gflops_{s}")


def fig_sistemas(r):
    """Compara sistemas en la configuración común con más paralelismo y mayor N."""
    ss = sorted(r.sistema.unique())
    if len(ss) < 2:
        return
    comun = None
    for s in ss:
        c = set(map(tuple, r[r.sistema == s][["binario", "N", "workers", "hilos"]].values))
        comun = c if comun is None else comun & c
    if not comun:
        return
    _, n, w, h = max(comun, key=lambda t: (t[2] * t[3], t[1]))
    d = r[(r.N == n) & (r.workers == w) & (r.hilos == h)]
    bins = sorted(d.binario.unique())
    fig, a = plt.subplots(figsize=(8, 3.8))
    for k, s in enumerate(ss):
        y = d[d.sistema == s].set_index("binario").loc[bins]
        a.bar(np.arange(len(bins)) + (k - (len(ss) - 1) / 2) * 0.8 / len(ss), y.media, 0.8 / len(ss),
              yerr=(y.ic95_sup - y.ic95_inf) / 2, capsize=2, label=s)
    a.set_xticks(range(len(bins)), bins, rotation=20, fontsize=8)
    a.set_ylabel("tiempo (s)"); a.legend()
    a.set_title(f"Entre sistemas: N={n}, {w} worker(s), {h} hilo(s) (IC95 de la media)", fontsize=9)
    guardar(fig, "entre_sistemas")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--resultados", default="resultados")
    ap.add_argument("--figuras", default="figuras")
    a = ap.parse_args()
    FIG = a.figuras
    os.makedirs(FIG, exist_ok=True)
    df = cargar(a.resultados)
    r = resumen(df)
    for s in sorted(r.sistema.unique()):
        for alg in ("FxC", "FxT"):
            fig_tiempos(r, s, alg)
        fig_eficiencia(r, s); fig_algoritmos(r, s); fig_omp_pth(r, s)
        fig_dispersion(df, r, s); fig_gflops(r, s, a.resultados)
    fig_sistemas(r)
    print("Figuras en", FIG)
