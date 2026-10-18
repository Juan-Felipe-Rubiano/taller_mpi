/************************************************************************************************
								=	Pontificia Universidad Javeriana	=

	Author: John Corredor
	Revision para taller: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
	Versión Prototipo "Inicial" MPI Distribución de Matrices en Nodos de Cómputo	

	Descripción:
		Multiplicación de Matrices cuadradas, algoritmo Filas x Columnas
		Square Matrix Multiplication, rowsxcolumns version:
		=> MPI_Init:				- Inicializacíón del entorno MPI 
		=> MPI_Comm_size:			- Obtener cantidad de procesos o workers en ejecución
		=> MPI_Comm_rank:			- Obtener el ID del proceso o worker  
		=> MPI_Get_processor_name:	- Obtener nombre del Nodo de Cómputo 
		=> MPI_Finalize:			- Finalización del entorno MPI

	Ejecución:
		$mpirun -hostfile fileHOSTSMPI -np 3 ./mmMPIv1 8 1
************************************************************************************************/
#include <mpi.h>
#include <omp.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include "functions.h" 

// Estructura de datos para la toma de tiempos
struct timeval inicio, fin;

/**
 * @brief Función inicialización matrices
 * @param mA la matriz A
 * @param mB La matriz B
 * @param D la dimensión de ambas matrices cuadradas
 */
void iniMatrix(double *mA, double *mB, int D){
	/* Originalmente setteaba la semilla de rand() para que sea pseudoaleatoria en función
	   del instante de tiempo. Normalmente lo recomendable es llamar esta función
	   al inicio de main para que si se llama dos veces rápidamente no salga se 
	   siembre la misma semilla.

	   Se modificó para que se puedan comparar los resultados entre ejecuciones
	*/
	//srand(time(NULL)); 
	srand(123456789);
	for(int i=0; i<D*D; i++, mA++, mB++){
		//llena las matrices con valores una fórmula específica y hace uso de los número pseudoaleatorios
		*mA = (0.1*i + 0.3*i) * (double) rand()/RAND_MAX*(5.1-2.3);
		*mB = (2.3*i - 0.1*i) * (double) rand()/RAND_MAX*(6.1-2.8);
	}
}

/**
 * @brief Función impresión para verificación
 * @param matrix la matriz a imprimir
 * @param D la dimensión de esta
 */
void impMatrix(double *matrix, int D){
	// la dimensión de la matriz cuadrada no puede ser mayor a 13
	if(D<14){
		for (int i = 0; i < D*D; i++, matrix++) {
			if(i%D == 0 ) printf("\n");
			// aproxima a dos decimales, por lo que puede haber
			// diferencias con calculadoras de matrices online
			printf("%9.2f ", *matrix); 
		}
		printf("\n\n");
	}
}

/**
 * @brief Función matrix Transpuesta
 * @param mB matriz a transponer
 * @param mT matriz transpuesta, ahí se guardará el resultado
 * @param D dimensión de la matriz
 */
void matrixTRP(double *mB, double *mT, int D){
	for(int i=0; i<D; i++)
		for(int j=0; j<D; j++)
			mT[i*D+j] = mB[j*D+i];
	impMatrix(mT, D);
}

/**
 * @brief Función MxM: algoritmo clásico filasxcolumnas
 * @param mA matriz A
 * @param mB matriz B
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 */
void mxmFxC(double *mA, double *mB, double *mC, int tw, int D){
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j;
			for(int k=0; k<D; k++, pA++, pB+=D)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

/**
 * @brief Función MxT: algoritmo filasxtranspuesta
 * @param mA matriz A
 * @param mB matriz B transpuesta
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 */
void mxmFxT(double *mA, double *mB, double *mC, int tw, int D){
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j*D;
			// Ahora, los números en ambas matrices están 
			// al lado en memoria (localidad espacial)
			// por lo que se cargan juntos en caché
			// y entonces el procesador no tiene que volver a pedir
			// datos a la RAM que es más lenta (jerarquía de memoria)
			// entonces con matrices grandes se notará más velocidad
			for(int k=0; k<D; k++, pA++, pB++)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

/**
 * @brief Función MxM: algoritmo clásico con uso de OpenMP
 * @param mA matriz A
 * @param mB matriz B
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 * @param nH numero de hilos a usar
 */
void mxmOmpFxC(double *mA, double *mB, double *mC, int tw, int D, int nH){
	// El código debajo se reparte y ejecuta paralelamente en varios hilos
	// reparte iteraciones de bucle entre hilos disponibles
	// las variables i, j y k son privadas para cada hilo
	// para evitar race conditions (se definieron dentro del bloque paralelo, asi
	// que no hay que poner private(i,j,k)
	// Líneas originales: #pragma omp parallel y #pragma omp parallel for private(i,j,k) 
	// se modificaron porque se intentaba hacer paralelismo sobre
	// paralelismo lo cual no es eficiente. Y ahora queda explícito el uso de nH 
	// y no solo se depende de omp_set_num_threads, antes no se usaba el parámetro
	#pragma omp parallel for num_threads(nH) schedule(static)
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j;
			for(int k=0; k<D; k++, pA++, pB+=D)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

/**
 * @brief Función MxM: algoritmo  FilasxFilas <matrix transpuesta> con uso de Hilos OpenMP
 * @param mA matriz A
 * @param mB matriz B transpuesta
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 * @param nH numero de hilos a usar
 */
void mxmOmpFxT(double *mA, double *mB, double *mC, int tw, int D, int nH){
	//se aplica el mismo ajuste de la clásica
	#pragma omp parallel for num_threads(nH) schedule(static)
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j*D;
			for(int k=0; k<D; k++, pA++, pB++)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

typedef struct{
	int id_hilo; // Identificador del hilo de 0 a nH-1
	int nH; 	// Número de hilos totales
	int tw; 	// Número de filas a procesar en esta llamada
	int D;		// Dimensión de las matrices cuadradas
	double *mA;	// tajada de la matriz A que le corresponde a este worker
	double *mB;	// matriz B (puede estar transpuesta o no, según el algoritmo)
	double *mC; // tajada de la matriz C donde se guardará el resultado de la multiplicación
} params_t;


/**
 * @brief Calcula el rango de filas que le corresponde a un hilo. Si la división no es exacta, el último hilo toma las filas restantes.
 * @param params parámetros del hilo
 * @param inicio primera fila incluida
 * @param fin última fila excluida
 */
static void rango_filas(const params_t *params, int *inicio, int *fin){
	int base = params->tw / params->nH; // número de filas por hilo
	*inicio = params->id_hilo * base;
	*fin = (params->id_hilo == params->nH - 1) ? params->tw : *inicio + base; // el último hilo toma las filas restantes
}

/**
 * @brief cálculo realizado por cada hilo. En filasxcolumnas.
 * @param arg apuntador a params_t que contiene los parámetros del hilo
 */
 static void *calculo_hilo_FxC(void *arg){
	const params_t *params = (const params_t *)arg;
	int inicio, fin;
	rango_filas(params, &inicio, &fin);
	for(int i=inicio; i<fin; i++)
		for(int j=0; j<params->D; j++){
			double Suma = 0.0;
			double *pA = params->mA+i*params->D;
			double *pB = params->mB+j;
			for(int k=0; k<params->D; k++, pA++, pB+=params->D)
				Suma += *pA * *pB;
			params->mC[i*params->D+j] = Suma;
		}
	return NULL;
}

/**
 * @brief cálculo realizado por cada hilo. Algoritmo con filasxfilas y matrix transpuesta.
 * @param arg apuntador a params_t que contiene los parámetros del hilo
 */
 static void *calculo_hilo_FxT(void *arg){
	const params_t *params = (const params_t *)arg;
	int inicio, fin;
	rango_filas(params, &inicio, &fin);
	for(int i=inicio; i<fin; i++)
		for(int j=0; j<params->D; j++){
			double Suma = 0.0;
			double *pA = params->mA+i*params->D;
			double *pB = params->mB+j*params->D;
			for(int k=0; k<params->D; k++, pA++, pB++)
				Suma += *pA * *pB;
			params->mC[i*params->D+j] = Suma;
		}
	return NULL;
}

/**
 * @brief lanzador de hilos para multiplicación de matrices que ejecutan el algoritmo que se pasa como parámetro.
 * @param function apuntador a la función que ejecutará cada hilo
 * @param mA tajada de matriz A
 * @param mB matriz B (puede estar transpuesta o no, según el algoritmo)
 * @param mC tajada de matriz C donde se guardará el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices cuadradas
 * @param nH número de hilos a usar
 */
static void lanzador_hilos(void *(*function)(void *), double *mA, double *mB, double *mC, int tw, int D, int nH){
	if(nH < 1){
		fprintf(stderr, "Error: número de hilos (recibido: %d) debe ser mayor a 0\n", nH);
		MPI_Abort(MPI_COMM_WORLD, 1);
		exit(1);
	}

	pthread_t hilos[nH];
	params_t params[nH];
	for(int i=0; i<nH; i++){
		params[i] = (params_t){.id_hilo = i, .nH = nH, .tw = tw, .D = D, .mA = mA, .mB = mB, .mC = mC};
		if(pthread_create(&hilos[i], NULL, function, &params[i]) != 0){
			fprintf(stderr, "Error: no se pudo crear el hilo %d\n", i);
			MPI_Abort(MPI_COMM_WORLD, 1);
			exit(1);
		}
	}
	for(int i=0; i<nH; i++){
		pthread_join(hilos[i], NULL);
	}
}

/**
 * @brief Función MxM: algoritmo clásico con uso de Pthread
 * @param mA matriz A
 * @param mB matriz B
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 * @param nH numero de hilos a usar
 */
void mxmPthFxC(double *mA, double *mB, double *mC, int tw, int D, int nH){
	lanzador_hilos(calculo_hilo_FxC, mA, mB, mC, tw, D, nH);
}

/**
 * @brief Función MxM: algoritmo FilasxFilas <Matrix Transpuesta> con Pthread
 * @param mA matriz A
 * @param mB matriz B transpuesta
 * @param mC matriz donde se guarda el resultado de la multiplicación
 * @param tw número de filas a procesar en esta llamada
 * @param D dimensión de las matrices
 * @param nH numero de hilos a usar
 */
void mxmPthFxT(double *mA, double *mB, double *mC, int tw, int D, int nH){
	lanzador_hilos(calculo_hilo_FxT, mA, mB, mC, tw, D, nH);
}


void mensajeVerifica(int N, int cantidadW){
	if(N<14){
		printf("\n");
		printf("********************************************************************\n");
		printf("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n");
		printf("++++++ \t\tDimensión de Matrix NxN \t  = %dx%d \t++++\n", N, N);
		printf("++++++ \t\tCantidad de Workers (np - MASTER) = %d \t\t++++\n", cantidadW);
		printf("++++++ \t\tTajada de matriz A para Workers   = %dx%d \t++++\n", N/cantidadW,N);
		printf("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n");
		printf("********************************************************************\n");
		printf("\n");
	}
}

void iniTime(){
		gettimeofday(&inicio, (void *)0);
}

void endTime(){
		gettimeofday(&fin, (void *)0);
		fin.tv_usec -= inicio.tv_usec;
		fin.tv_sec  -= inicio.tv_sec;
		double tiempo = (double) (fin.tv_sec*1000000 + fin.tv_usec);
		printf("%9.0f \n", tiempo);
}

void argumentos(int cantidad){
	if (cantidad != 3){
		printf("Ingreso de Argumentos: \n\n");
		printf("\t\t$mpirun -hostfile file -np p ./ejecutable DimMatriz NumHilos \n\n");
		exit(0);
	}
}

void verificarDiv(int qworkers, int Dim){
	// Se revisa que modulo de Dimensión de Matrix / Workers == 0
	if ((qworkers < 1) || (Dim%qworkers != 0)) {
		printf("Error: NxN (%d) debe ser divisible por cantidad de workers (%d)\n", Dim, qworkers);
		printf("Error: Número de procesos (%d) > 1 \n", qworkers);
		MPI_Abort(MPI_COMM_WORLD, 1);
		exit(0);
	}
	if(Dim<14){
		printf("|================================================================================|\n");
		printf("|\t\t\tMultiplicación de Matrices  << MPI >>             	 |\n");
		printf("|================================================================================|\n");
		printf(" \t= Dimensión Matrix NxN = %dx%d \n", Dim, Dim);
		printf(" \t= Distribución de %d filas 'Matrix A' para %d Workers \n", Dim/qworkers, qworkers);
		printf("|================================================================================|\n");
	}

}

void functionOMP(int nhilos){
   #pragma omp parallel num_threads(nhilos)
   {
      int i = omp_get_thread_num();
      printf("Hello from thread %d\n", i);
   }
}
