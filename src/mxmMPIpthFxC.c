/************************************************************************************************
								=	Pontificia Universidad Javeriana	=

	Authors: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C.
	Versión Prototipo "Inicial" MPI Distribución de Matrices en Nodos de Cómputo	
    Oct 2026
    
	Descripción:
		Multiplicación de Matrices cuadradas, algoritmo clásico de Filas x Columnas
		Uso de Pthread para paralelizar el cálculo en cada Worker

	Ejecución:
		$mpirun -hostfile nodos -np totalProcesos ./mmMPIv1 dimMatrix nH
    
    Argumentos:
        nodos: fichero que contiene el Master y los Workers
        totalProcesos: cantidad de procesos master+workers
        dimMatrix: dimensión de matrix NxN				//  NxN % (np-1) == 0 {true}
        nH: número de hilos a usar en cada Worker
************************************************************************************************/

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include "functions.h"

#define MASTER 0
#define FROM_MASTER 1
#define FROM_WORKER 2

int main(int argc, char **argv){
    argumentos(argc);

    int N  = (int) atoi(argv[1]); 								// Dimension of the matrices (N x N)
    int nH = (int) atoi(argv[2]); 								// Cantidad hilos Pthread/worker
    double *matrixA = NULL, *matrixB = NULL, *matrixC = NULL;	// Punteros a reservas matrices
    int cantProcesos;											// Cantidad de Procesos/Tareas MPI
    int idProceso;												// ID Procesos/Tarea MPI
    double tti, ttf;											// Calculo de tiempo por MPI

    //	2.- Inicio MPI
    MPI_Init(&argc, &argv);                                     // Inicialización de entorno MPI
    MPI_Comm_size(MPI_COMM_WORLD, &cantProcesos);               // Captura de argumento cantidad de Procesos/Tareas MPI
    MPI_Comm_rank(MPI_COMM_WORLD, &idProceso);                  // Captura de argumento identificador de Procesos/Tareas MPI
    int cantWorkers = cantProcesos-1;                           // Cantidad de nodos workers
    int tW = N/cantWorkers;										// Tajada MatrixA a ser enviada a Workers
    double *tW_matA, *tW_matC;                                  // Punteros auxiliares para workers

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
    MPI_Bcast(&nH, 1, MPI_INT, 0, MPI_COMM_WORLD);

    // 5.- MASTER: envía las "tajadas" a los Workers: hacen el cálculo. Master imprime
    if(idProceso == MASTER) {
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

    // 6.- WORKERS: reciben la tajada de matrixA y matrixB, hacen el cálculo y envían el resultado a MASTER
    if(idProceso > MASTER) {
        tW_matA = (double *)malloc(tW*N*sizeof(double));			// Reserva de tajada memoria en Worker: MatrixA
        matrixB = (double *)malloc(N*N*sizeof(double));			// Reserva de memoria en Worker: MatrixB
        tW_matC = (double *)malloc(tW*N*sizeof(double));			// Reserva de tajada memoria en Worker: MatrixC
        
        MPI_Bcast(matrixB, N*N, MPI_DOUBLE, 0, MPI_COMM_WORLD);	// Recepción matrixB desde MASTER
        MPI_Recv(tW_matA, tW*N, MPI_DOUBLE, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE); // Recepción tajada matrixA desde MASTER

        mxmPthFxC(tW_matA, matrixB, tW_matC, tW, N, nH);			// Cálculo de multiplicación de matrices en Worker
        MPI_Send(tW_matC, tW*N, MPI_DOUBLE, 0, 1, MPI_COMM_WORLD);	// Envío de resultados a MASTER

        free(tW_matA);											// Liberación de memoria en Worker: MatrixA
        free(matrixB);											// Liberación de memoria en Worker: MatrixB
        free(tW_matC);											// Liberación de memoria en Worker: MatrixC
    }

    ttf = MPI_Wtime();

    if(idProceso == MASTER) {
        free(matrixA);											// Liberación de memoria en MASTER: MatrixA
        free(matrixB);											// Liberación de memoria en MASTER: MatrixB
        free(matrixC);											// Liberación de memoria en MASTER: MatrixC
        printf("Tiempo por MPI: %10f\n", ttf-tti);
    }

    MPI_Finalize();												// Finalización de entorno MPI
    return 0;
}


