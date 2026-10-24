"""Carga de los CSV del lanzador y definiciones comunes.
Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. """
import glob, os, re, sys
import numpy as np
import pandas as pd

CLAVE = ["sistema", "binario", "algoritmo", "modelo", "N", "workers", "hilos"]


def cargar(directorio="resultados"):
    """Lee resultados/*.csv (uno por sistema) y agrega columnas.
    t = tiempo de cómputo en segundos (columna t_us: sin reservar ni inicializar matrices)."""
    dfs = []
    for f in sorted(glob.glob(os.path.join(directorio, "*.csv"))):
        d = pd.read_csv(f)
        d["sistema"] = os.path.splitext(os.path.basename(f))[0]
        dfs.append(d)
    if not dfs:
        sys.exit(f"No hay archivos .csv en '{directorio}'.")
    df = pd.concat(dfs, ignore_index=True)
    df["t"] = df["t_us"] / 1e6
    df["algoritmo"] = np.where(df["binario"].str.endswith("FxT"), "FxT", "FxC")
    df["modelo"] = np.where(df["binario"].str.contains("omp"), "omp",
                   np.where(df["binario"].str.contains("pth"), "pth", "mpi"))
    return df


def tamanos_cache(directorio, sistema):
    """N máximo que cabe en L2 y L3, leído de info_*.txt (sistema_info.sh). {} si no hay."""
    for f in sorted(glob.glob(os.path.join(directorio, sistema, "info_*.txt"))):
        txt = open(f, encoding="utf-8", errors="replace").read()
        return {m[0]: int(m[1]) for m in re.findall(r"^(L\d)\s+\S+\s+N max = (\d+)", txt, re.M)}
    return {}
