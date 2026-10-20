#!/bin/bash
##################################
# Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
# Verifica que los 6 binarios calculan bien C = A X B. Para cada caso, compara la matriz C impresa con la del 
# binario de referencia
# Uso: MPIRUN_FLAGS="--hostfile nodos --bind-to none" make verificar
####################################
cd "$(dirname "$0")/.." || exit 2
MPIRUN_FLAGS=${MPIRUN_FLAGS:---oversubscribe --bind-to none}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fallos=0
 
# Salida del programa: ... línea con microsegundos, matriz C, línea "Tiempo ... MPI" ...
matriz_C() { awk '/^ *[0-9]+ *$/ && !c {c=1; next} /Tiempo/ {c=0} c && NF {$1=$1; print}' "$1"; }
correr()   { mpirun $MPIRUN_FLAGS -np $(($3 + 1)) "bin/$1" "$2" "$4" < /dev/null > "$TMP/out" 2>&1; }
 
# Casos "N workers hilos": incluyen filas no divisibles entre hilos (12 2 4) y más hilos que filas (12 6 3)
for caso in "8 1 1" "8 4 2" "12 2 4" "12 6 3"; do
    read -r N W H <<< "$caso"
 
    correr mxmMPI_FxC "$N" 1 1 || { echo "FALLA la referencia N=$N"; cat "$TMP/out"; exit 1; }
    matriz_C "$TMP/out" > "$TMP/ref"
    # Cálculo independiente: A y B salen de lo impreso, C se recalcula
    python3 - "$TMP/out" "$N" <<'PY' || { echo "FALLA: la referencia no coincide con A x B (N=$N)"; fallos=$((fallos+1)); }
import re, sys
n = int(sys.argv[2])
f = [[float(x) for x in l.split()] for l in open(sys.argv[1]) if re.fullmatch(r'\s*(-?\d+\.\d\d\s*)+', l)]
A, B, C = f[:n], f[n:2*n], f[2*n:3*n]
# A y B se imprimen con 2 decimales: la tolerancia es relativa y no cero
err = max(abs(C[i][j] - sum(A[i][k]*B[k][j] for k in range(n))) for i in range(n) for j in range(n))
sys.exit(err > 1e-3 * max(map(max, C)))
PY
 
    for b in mxmMPI_FxC mxmMPI_FxT mxmMPIompFxC mxmMPIompFxT mxmMPIpthFxC mxmMPIpthFxT; do
        h=$H; [[ $b == mxmMPI_* ]] && h=1          # los binarios sin hilos ignoran H
        if correr "$b" "$N" "$W" "$h" && [ "$(matriz_C "$TMP/out")" = "$(cat "$TMP/ref")" ] \
           && grep -qE 'Tiempo( por)? MPI *[=:]' "$TMP/out"; then
            echo "OK     $b N=$N W=$W H=$h"
        else
            echo "FALLA  $b N=$N W=$W H=$h"; fallos=$((fallos+1))
        fi
    done
done
 
[ $fallos -eq 0 ] && echo "TODO CORRECTO" || echo "HAY $fallos FALLO(S)"
exit $((fallos > 0))
 