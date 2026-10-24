"""Estadísticas a partir de resultados/*.csv.
Uso:  python3 analisis/estadisticas.py [--resultados resultados] [--tablas tablas]
Genera en tablas/:  resumen_<sistema>.csv  y  comparaciones.csv
Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. """

import argparse, os
import numpy as np
import pandas as pd
from scipy import stats
from datos import cargar, CLAVE


def resumen(df):
    """Una fila por configuración: dispersión, IC95, atípicos, normalidad, deriva,
    y speedup / eficiencia / GFLOPS frente al caso W=1, H=1 del mismo binario."""
    filas = []
    for clave, g in df.groupby(CLAVE):
        t = g["t"].to_numpy()
        n = len(t)
        media, sd = t.mean(), t.std(ddof=1) if n > 1 else np.nan
        h = stats.t.ppf(0.975, n - 1) * sd / np.sqrt(n) if n > 1 else np.nan
        q1, q3 = np.percentile(t, [25, 75])
        atip = int(((t < q1 - 1.5 * (q3 - q1)) | (t > q3 + 1.5 * (q3 - q1))).sum())
        sw = stats.shapiro(t).pvalue if n >= 3 and np.ptp(t) > 0 else np.nan
        rho = stats.spearmanr(g["ronda"], t).statistic if n >= 3 and np.ptp(t) > 0 else np.nan
        filas.append(dict(zip(CLAVE, clave)) | dict(
            n=n, media=media, mediana=np.median(t), sd=sd, cv_pct=100 * sd / media,
            minimo=t.min(), maximo=t.max(), ic95_inf=media - h, ic95_sup=media + h,
            atipicos=atip, shapiro_p=sw, rho_ronda=rho))
    r = pd.DataFrame(filas)
    base = (r[(r.workers == 1) & (r.hilos == 1)]
            .set_index(["sistema", "binario", "N"])["mediana"].rename("t_base"))
    r = r.join(base, on=["sistema", "binario", "N"])
    p = r.workers * r.hilos
    r["speedup"] = r.t_base / r.mediana
    r["eficiencia"] = r.speedup / p
    r["karp_flatt"] = np.where(p > 1, (1 / r.speedup - 1 / p) / (1 - 1 / p), np.nan)
    r["gflops"] = 2.0 * r.N ** 3 / r.mediana / 1e9
    return r.drop(columns="t_base")


def holm(p):
    """Corrección de Holm para un vector de valores p."""
    p = np.asarray(p, float)
    orden = np.argsort(p)
    aj = np.minimum(1, np.maximum.accumulate((len(p) - np.arange(len(p))) * p[orden]))
    out = np.empty_like(aj)
    out[orden] = aj
    return out


def comparar(df, factor, a, b, fijos):
    """Compara los tiempos del nivel a contra el nivel b del factor, manteniendo `fijos` iguales."""
    filas = []
    for clave, g in df.groupby(fijos):
        ta, tb = g[g[factor] == a]["t"], g[g[factor] == b]["t"]
        if len(ta) < 3 or len(tb) < 3:
            continue
        filas.append(dict(zip(fijos, clave)) | dict(
            comparacion=f"{a} vs {b}", mediana_a=ta.median(), mediana_b=tb.median(),
            razon_medianas=ta.median() / tb.median(),
            welch_p=stats.ttest_ind(ta, tb, equal_var=False).pvalue,
            mannwhitney_p=stats.mannwhitneyu(ta, tb).pvalue))
    return pd.DataFrame(filas)


def comparaciones(df):
    c1 = comparar(df, "algoritmo", "FxC", "FxT", ["sistema", "modelo", "N", "workers", "hilos"])
    c2 = comparar(df, "modelo", "omp", "pth", ["sistema", "algoritmo", "N", "workers", "hilos"])
    c = pd.concat([c1, c2], ignore_index=True)
    c["mannwhitney_p_holm"] = c.groupby("sistema")["mannwhitney_p"].transform(holm)
    c["significativa_5pct"] = c["mannwhitney_p_holm"] < 0.05
    return c


def a_latex(t, columnas, formatos):
    """Tabla LaTeX sencilla (sin depender de jinja2)."""
    lineas = [r"\begin{tabular}{" + "r" * len(columnas) + "}", r"\hline",
              " & ".join(c.replace("_", r"\_") for c in columnas) + r" \\", r"\hline"]
    for _, f in t.iterrows():
        lineas.append(" & ".join(formatos[c].format(f[c]) if pd.notna(f[c]) else "--"
                                 for c in columnas).replace("_", r"\_") + r" \\")
    return "\n".join(lineas + [r"\hline", r"\end{tabular}"])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--resultados", default="resultados")
    ap.add_argument("--tablas", default="tablas")
    a = ap.parse_args()
    df = cargar(a.resultados)
    os.makedirs(a.tablas, exist_ok=True)
    r = resumen(df)
    fm = {"binario": "{}", "N": "{:d}", "workers": "{:d}", "hilos": "{:d}", "n": "{:d}",
          "mediana": "{:.4f}", "cv_pct": "{:.1f}", "speedup": "{:.2f}", "eficiencia": "{:.2f}",
          "gflops": "{:.2f}"}
    for s, g in r.groupby("sistema"):
        g = g.sort_values(["binario", "N", "workers", "hilos"])
        g.to_csv(f"{a.tablas}/resumen_{s}.csv", index=False)
        open(f"{a.tablas}/resumen_{s}.tex", "w", encoding="utf-8").write(a_latex(g, list(fm), fm))
    c = comparaciones(df)
    c.to_csv(f"{a.tablas}/comparaciones.csv", index=False)
    print(f"{len(df)} mediciones, {len(r)} configuraciones, {df['sistema'].nunique()} sistema(s).")
    print(f"Configuraciones con menos de 30 repeticiones: {(r.n < 30).sum()}")
    print(f"Con CV > 5 %: {(r.cv_pct > 5).sum()}   con atípicos: {(r.atipicos > 0).sum()}")
    print(f"Comparaciones significativas (Holm, 5 %): {int(c.significativa_5pct.sum())} de {len(c)}")
    print(f"Tablas en {a.tablas}/")
