# Taller de Evaluación de Rendimiento MPI (MPI + OpenMP / Pthreads)

Multiplicación de matrices con dos algoritmos (FxC: filas × columnas, FxT: filas × transpuesta)
y tres modelos (MPI puro, MPI + OpenMP, MPI + Pthreads). Son 6 binarios, que `lanzador.pl` ejecuta
con N ∈ {256, 512, 1024, 2048}, workers ∈ {1, 2, 4}, hilos ∈ {1, 2, 4} y **30 repeticiones**
por configuración.

## 1. Preparación

```bash
sudo dnf update
sudo dnf install build-essential openmpi-bin libopenmpi-dev perl git python3-pip
```
Clonar y compilar:
```bash
git clone https://github.com/juan-felipe-rubiano/taller_mpi.git
cd taller_mpi
chmod +x scripts/*.sh
make
make verificar          # debe terminar en "TODO CORRECTO"
```

## 2. Describir máquina
```bash
scripts/sistema_info.sh resultados/<nombre>
```
Usar un nombre por máquina: `portatil1`, `portatil2`. Crea `info_<host>.txt` (CPU, cachés, memoria, versiones).
Guardar también la salida de `lscpu`.

## 3. Lanzar
```bash
perl lanzador.pl portatil1       # usar el mismo nombre del paso 2
```
- Las configuraciones se ejecutan por rondas y en orden aleatorio. Cada ejecución se guarda en
  `resultados/<nombre>.csv`.
- Si se interrumpe, volver a lanzar **el mismo comando**:
  continúa donde quedó. No borrar el CSV.
- Los portátiles solo ejecutan las configuraciones con workers X hilos <= núcleos de la máquina;
  el resto se descarta solo.

## 4. Qué devolver
Un zip con:
- `resultados/<nombre>.csv`
- la carpeta `resultados/<nombre>/` (los `info_*.txt`)
- la salida de `lscpu` y el modelo de la máquina.

## 5. Análisis
```bash
pip install pandas numpy scipy matplotlib
python3 analisis/estadisticas.py    # tablas/  (CSV y LaTeX) y comparaciones.csv
python3 analisis/graficar.py        # figuras/ (PNG y PDF)
```
Lee todos los `resultados/*.csv`; el nombre del archivo es el nombre del sistema.

## 6. Entrega
```bash
make entregar          # crea entrega_mpi.zip con los .c, .h y .pl
```