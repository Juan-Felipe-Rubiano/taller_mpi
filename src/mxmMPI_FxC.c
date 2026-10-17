/************************************************************************************************#
								=	Pontificia Universidad Javeriana	=

	Author: John Corredor
	Sept 2026

	Descripción:
		Matrix Multiplication version MPI FilasxColumnas ALGORITMO CLÁSICO

	Ejecución:
		$mpirun -hostfile nodosFichero -np totalProcesos ./mmMPIv1 dimMatrix numHilosOMP

	Argumentos:
		nodosFichero: fichero que contiene el Master y los Workers
		totalProcesos: cantidad de procesos master+workers
		dimMatrix: dimensión de matrix NxN				//  NxN % (np-1) == 0 {true}
		numHilosOMP: valor (NO APLICA)

		=> MPI_Init:				- Initialize MPI environment
		=> MPI_Comm_size:			- get the number of the processes
		=> MPI_Comm_rank:			- get the rank of the process
		=> MPI_Get_processor_name:	- get the name of the processor
		=> MPI_Finalize:			- Finalize MPI environment
#************************************************************************************************/

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include "functions.h" 

#define MASTER 0
#define FROM_MASTER 1
#define FROM_WORKER 2

int main(int argc, char *argv[]) {
	//	1.- Revisión de Argumentos de Entrada del BINARIO
	argumentos(argc);
	int N  = (int) atoi(argv[1]); 								// Dimension of the matrices (N x N)
	int nH = (int) atoi(argv[2]); 								// Cantidad Hilos (openMP, Posix, Fork())
    double *matrixA = NULL, *matrixB = NULL, *matrixC = NULL;	// Punteros a reservas para matrices
	int cantProcesos;											// Cantidad de Procesos/Tareas MPI
	int idProceso;												// ID Procesos/Tarea MPI
	double tti, ttf;												// Toma de tiempos desde MPI

	//	2.- Inicio MPI
	MPI_Init(&argc, &argv);                                     // Inicialización de entorno MPI
	MPI_Comm_size(MPI_COMM_WORLD, &cantProcesos);               // Captura de argumento cantidad de Procesos/Tareas MPI
	MPI_Comm_rank(MPI_COMM_WORLD, &idProceso);                  // Captura de argumento identificador de Procesos/Tareas MPI
	int cantWorkers = cantProcesos-1;                           // Cantidad de nodos workers
	int tW = N/cantWorkers;										// Tajada MatrixA a ser enviada a Workers
	double *tW_matA, *tW_matC;

	tti = MPI_Wtime();

	//	3.- Master process (idTask=0) initializes everything
    if (idProceso == MASTER) {
		verificarDiv(cantWorkers, N);							// Verificador de dimensión Matrix % Workers == 0
        matrixA = (double *)malloc(N*N*sizeof(double));			// Reserva de memoria en Master: MatrixA
        matrixB = (double *)malloc(N*N*sizeof(double));			// Reserva de memoria en Master: MatrixB
        matrixC = (double *)calloc(N*N,sizeof(double));			// Reserva de memoria en Master: MatrixC
		iniMatrix(matrixA, matrixB, N);							// Inicialización MatrixA y MatrixB
		impMatrix(matrixA, N);									//Impresión inicial MatrixA (N<13)
		impMatrix(matrixB, N);									//Impresión inicial MatrixB (N<13)
    }

	// 4.- Transmisión Dimensión (N) y tajada de cómputo a todos los Workers  
    MPI_Bcast(&N,  1, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Bcast(&tW, 1, MPI_INT, 0, MPI_COMM_WORLD);
	
	// 5.- MASTER: envía las "tajadas" a los Workers: hacen el cálculo. Master imprime 
    if (idProceso == MASTER) {
		iniTime();												// Inicio captura de tiempo 
		MPI_Bcast(matrixB, N*N, MPI_DOUBLE, 0, MPI_COMM_WORLD); // Trasmisión a workers de matrixB
        
        // Envio de tajadas de matrixA a cada Worker 
        for (int w = 1; w < cantProcesos; w++) {
            int iniSlice = (w-1)*tW;
            MPI_Send(matrixA+iniSlice*N, tW*N, MPI_DOUBLE, w, 0, MPI_COMM_WORLD);
        }
        
        // Recepción de resultados de cada Worker
        for (int w = 1; w < cantProcesos; w++) {
            int iniSlice = (w-1)*tW;
            MPI_Recv(matrixC+iniSlice*N, tW*N, MPI_DOUBLE, w, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        }
		endTime(); 												// Fin captura de tiempo 
        
		impMatrix(matrixC, N);									//Impresión MatrixC (N<13)
    } 

	// 6.- WORKERS: reciben sus tajadas de matA, multiplican y finalmente envian resultados a MASTER		
	if (idProceso > MASTER){
        tW_matA = (double *)malloc(tW*N*sizeof(double));			// Reserva de tajada memoria en Worker: MatrixA
        matrixB = (double *)malloc(N*N*sizeof(double));			// Reserva de memoria en Worker: MatrixB
        tW_matC = (double *)malloc(tW*N*sizeof(double));			// Reserva de tajada memoria en Worker: MatrixC
        
        MPI_Bcast(matrixB, N*N, MPI_DOUBLE, 0, MPI_COMM_WORLD);	// Recepción matrixB desde MASTER
		// Recepción de Tajada de MatrixA en cada Worker
        MPI_Recv(tW_matA, tW*N, MPI_DOUBLE, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);	

		//** Cálculo de multiplicación de matrices algoritmo clásico **
		mxmFxC(tW_matA, matrixB, tW_matC, tW, N);
        
        // Envío de resultados al MASTER
        MPI_Send(tW_matC, tW*N, MPI_DOUBLE, 0, 1, MPI_COMM_WORLD);
        
        free(tW_matA);										// Liberar reserva memoria tW_matA
        free(tW_matC);										// Liberar reserva memoria tW_matC
        free(matrixB);										// Liberar reserva memoria matrixB 
    }
	
	ttf = MPI_Wtime();

	// 7.- MASTER: Libera reserva de memoria
    if (idProceso == MASTER) {
        free(matrixA);
        free(matrixB);
        free(matrixC);
		printf("Tiempo MPI = %10f\n", (ttf-tti));
    }

    MPI_Finalize();
    return 0;
}
