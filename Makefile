GCC= mpicc -fopenmp -lm 
MODULO= functions
BIN= bin/
SRC= src/

PROGRAMAS=  mxmMPI_FxC mxmMPI_FxT mxmMPIompFxC mxmMPIompFxT 
all: ${PROGRAMAS}

mxmMPI_FxC:
	$(GCC) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPI_FxT:
	$(GCC) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIompFxC:
	$(GCC) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIompFxT:
	$(GCC) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

clean:
	$(RM) $(BIN)*
