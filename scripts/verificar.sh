#!/bin/bash
##################################
# Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
#  Para cada caso (N, workers, hilos) y cada binario:
#    1. El programa termina sin error y dentro del tiempo limite.
#    2. La salida tiene los dos tiempos que lee el analisis: la linea en
#       microsegundos y la linea "Tiempo ... MPI".
#    3. La matriz C impresa es IDENTICA a la del binario de referencia
#       (mxmMPI_FxC con 1 worker y 1 hilo). Con la semilla fija y el mismo orden
#       de acumulacion, los resultados deben coincidir exactamente.
#    4. La referencia se contrasta contra un calculo independiente en Python
#       (A y B se leen de lo que imprime el programa), que detecta algoritmos
#       equivocados como A x B^T.
#
#  Solo se usan N < 14, porque el programa unicamente imprime las matrices
#  cuando N es pequeno.
#
#  Variables opcionales:
#    MPIRUN        comando mpirun               (por defecto: mpirun)
#    MPIRUN_FLAGS  banderas de mpirun           (por defecto: --oversubscribe --bind-to none)
#                  en el cluster:  MPIRUN_FLAGS="--hostfile nodos --bind-to none"
#    TIMEOUT       segundos maximos por corrida (por defecto: 60)
#
#  Codigo de salida: 0 si todo coincide, 1 si algo falla.
####################################
set -u
cd "$(dirname "$0")/.." || exit 2
 
BIN=bin
MPIRUN=${MPIRUN:-mpirun}
MPIRUN_FLAGS=${MPIRUN_FLAGS:---oversubscribe --bind-to none}
TIMEOUT=${TIMEOUT:-60}
 
SIN_HILOS="mxmMPI_FxC mxmMPI_FxT"
CON_HILOS="mxmMPIompFxC mxmMPIompFxT mxmMPIpthFxC mxmMPIpthFxT"
REFERENCIA=mxmMPI_FxC
 
# Casos "N workers hilos". Incluyen divisiones no exactas de filas entre hilos
# (12 2 4: 6 filas / 4 hilos) y mas hilos que filas (12 6 3: 2 filas / 3 hilos).
CASOS="8 1 1
8 2 2
8 4 2
12 3 2
12 2 4
12 6 3"
 
for b in $SIN_HILOS $CON_HILOS; do
    if [ ! -x "$BIN/$b" ]; then
        echo "Falta $BIN/$b. Ejecute 'make' primero." >&2
        exit 2
    fi
done
 
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
 
# Imprime solo la matriz C: lo que sale entre la linea de microsegundos
# (un entero solo en la linea) y la linea "Tiempo ...". Quita blancos repetidos.
extraer_C() {
    awk '
        /^ *[0-9]+ *$/ && !enC { enC = 1; next }
        /Tiempo/               { enC = 0 }
        enC && NF              { gsub(/[ \t]+/, " "); sub(/^ /, ""); sub(/ $/, ""); print }
    ' "$1"
}
tiempo_us()  { awk '/^ *[0-9]+ *$/ { gsub(/ /, ""); print; exit }' "$1"; }
tiempo_mpi() { grep -E 'Tiempo( por)? MPI *[=:]' "$1" | head -1 | sed -E 's/.*[=:] *//; s/ //g'; }
 
# Ejecuta un binario. Deja la salida en $TMP/salida. Devuelve el codigo de mpirun.
correr() {  # binario N workers hilos
    # shellcheck disable=SC2086
    timeout "$TIMEOUT" $MPIRUN $MPIRUN_FLAGS -np $(( $3 + 1 )) "$BIN/$1" "$2" "$4" \
        > "$TMP/salida" 2> "$TMP/error" < /dev/null   # < /dev/null: mpirun no debe leer la entrada del bucle
}
 
# Contraste independiente: lee A, B, C de la salida de la referencia y recalcula.
chequeo_python() {  # archivo de salida, N
    python3 - "$1" "$2" <<'PYEOF'
import re, sys
texto, n = open(sys.argv[1]).read().splitlines(), int(sys.argv[2])
fila = re.compile(r'^\s*-?\d+\.\d\d(\s+-?\d+\.\d\d)*\s*$')
filas = [[float(x) for x in l.split()] for l in texto if fila.match(l)]
if len(filas) != 3 * n or any(len(f) != n for f in filas):
    print("no se pudo leer A, B y C de la salida (%d filas)" % len(filas)); sys.exit(1)
A, B, C = filas[:n], filas[n:2*n], filas[2*n:]
ref = [[sum(A[i][k] * B[k][j] for k in range(n)) for j in range(n)] for i in range(n)]
escala = max(abs(v) for f in ref for v in f) or 1.0
err = max(abs(C[i][j] - ref[i][j]) for i in range(n) for j in range(n)) / escala
# A y B se imprimen con 2 decimales, por eso la tolerancia no es cero.
if err > 1e-3:
    print("C no coincide con A x B (error relativo %.2e)" % err); sys.exit(1)
print("error relativo %.1e" % err)
PYEOF
}
 
total=0; fallos=0
printf '%-14s %3s %3s %3s  %-9s %12s %12s  %s\n' binario N W H resultado t_us t_MPI_s detalle
 
while read -r N W H; do
    # --- referencia para este N ---
    if ! correr "$REFERENCIA" "$N" 1 1; then
        echo "FALLA la referencia ($REFERENCIA N=$N): ver $TMP/error" >&2; cat "$TMP/error" >&2; exit 1
    fi
    cp "$TMP/salida" "$TMP/ref_$N.out"
    extraer_C "$TMP/ref_$N.out" > "$TMP/ref_$N.C"
    if [ "${CHEQUEO_PYTHON:-1}" = 1 ] && command -v python3 >/dev/null 2>&1 && [ ! -e "$TMP/py_$N" ]; then
        if msg=$(chequeo_python "$TMP/ref_$N.out" "$N"); then
            echo "  [ref N=$N] calculo independiente en Python: OK ($msg)"
        else
            echo "  [ref N=$N] calculo independiente en Python: FALLA ($msg)"; fallos=$((fallos+1))
        fi
        : > "$TMP/py_$N"
    fi
 
    for b in $SIN_HILOS $CON_HILOS; do
        h=$H; case " $SIN_HILOS " in *" $b "*) h=1 ;; esac
        total=$((total+1)); detalle=""; res="OK"
        if ! correr "$b" "$N" "$W" "$h"; then
            res="FALLA"; detalle="mpirun termino con error: $(head -c 150 "$TMP/error" | tr '\n' ' ')"
        else
            us=$(tiempo_us "$TMP/salida"); tm=$(tiempo_mpi "$TMP/salida")
            extraer_C "$TMP/salida" > "$TMP/actual.C"
            if [ -z "$us" ] || [ -z "$tm" ]; then
                res="FALLA"; detalle="la salida no trae los dos tiempos (us='$us', MPI='$tm')"
            elif [ ! -s "$TMP/actual.C" ]; then
                res="FALLA"; detalle="no se encontro la matriz C en la salida"
            elif ! cmp -s "$TMP/actual.C" "$TMP/ref_$N.C"; then
                res="FALLA"; detalle="la matriz C difiere de la referencia"
            fi
        fi
        [ "$res" = FALLA ] && fallos=$((fallos+1))
        printf '%-14s %3s %3s %3s  %-9s %12s %12s  %s\n' "$b" "$N" "$W" "$h" "$res" "${us:--}" "${tm:--}" "$detalle"
        us=""; tm=""
    done
done <<< "$CASOS"
 
echo
if [ "$fallos" -eq 0 ]; then
    echo "TODO CORRECTO: $total ejecuciones coinciden con la referencia."
    exit 0
else
    echo "HAY $fallos FALLO(S) en $total ejecuciones."
    exit 1
fi