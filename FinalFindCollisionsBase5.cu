//Final find Collisions base 5

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <cuda.h>
#include <mpi.h>

#include <sys/stat.h>
#include <sys/time.h>

#define ROOT 0
#define MAXNGPU 3
#define MAX_THREAD 512
#define M 625
#define DP 21

#define BASE 5
#define NARGS 10
static  uint32_t PRIME= pow(BASE, NARGS);

#define J1 1
//#define J2 3  in input


#define TIMER_DEF     struct timeval temp_1, temp_2
#define TIMER_START   gettimeofday(&temp_1, (struct timezone*)0)
#define TIMER_STOP    gettimeofday(&temp_2, (struct timezone*)0)
#define TIMER_ELAPSED ((temp_2.tv_sec-temp_1.tv_sec)*1.e6+(temp_2.tv_usec-temp_1 .tv_usec))


//nvcc -I/usr/local/openmpi-4.1.4/include -L/usr/local/openmpi-4.1.4/lib -lmpi basepf.cu -o basepf
//mpirun -np 7 basepf 500 2

void cudaErrorCheck(cudaError_t error, const char * msg){
  	  if ( error != cudaSuccess){
  	  fprintf(stderr, "%s:%s\n ", msg, cudaGetErrorString(error));
  	  exit(EXIT_FAILURE);}}

__host__ __device__ uint32_t abcFunct(int32_t a, int32_t b, int32_t c){
   	 uint32_t F=b+pow(a-c,2);
   	 return F%BASE;
}


__host__ __device__ uint32_t baseFunct(uint32_t x, int J2, uint32_t MAXP){
    
   	uint32_t *arrayEquivX=(uint32_t*)malloc(sizeof(int)*NARGS);
    	uint32_t exp=MAXP;
   	uint32_t remnant;
   	uint32_t y;

   	remnant=x;

   	for (int i=0; i<NARGS; i++){
       		 exp=exp/BASE;
       		 arrayEquivX[NARGS-i-1]=remnant/exp;
       		 remnant=remnant%exp;
       		 //printf("in pos %d (exp %d) there is %d with remainder %d \n", POWER-1-i, exp, arrayEquivX[POWER-i-1],remnant);
   	 }

   	 y=0;
   	 exp=MAXP;

   	 for (int i=0; i<NARGS; i++){
       		exp=exp/BASE;
     	 	y=y+exp*abcFunct(arrayEquivX[i], arrayEquivX[(i+J1)%NARGS], arrayEquivX[(i+J2)%NARGS]);
      		 
   	 }
   	 //printf("modulo is %d \n", exp);
   	 y=y%MAXP;
   	 return y;
}


__global__ void findPathAndDP(
  	uint32_t* d_x0p,
  	uint32_t* d_x,
   	int lg,
   	int r,
  	int n_per_proc,
  	uint32_t* d_DjX0,
  	uint32_t* d_DjD,
  	uint32_t* d_Djsteps,
  	uint32_t* d_DjC,
  	int* d_nDPaux,
     	uint32_t MAXP
) {

  	int tid = threadIdx.x + blockDim.x * blockIdx.x;
  	 
	if (tid<n_per_proc) {
  		//initialization of arrays
  		d_nDPaux[tid]=0;
  		d_DjX0[tid]=0;
  		d_DjD[tid]=0;
  		d_Djsteps[tid]=0;
  		d_DjC[tid]=0;
  	  	//places starting points in the right position
  	  	d_x[tid*lg] = d_x0p[tid];
  		//printf("starting point %d \n", d_x[tid*lg]);
  		__syncthreads();
  	  	//all threads start computing path
  		for(int i = 0; i < lg-1; i++) {
           		d_x[tid*lg+i+1]=baseFunct(d_x[tid*lg+i],r, MAXP);
          		//printf("indx %d path ID %d, %d step %d \n",tid*lg+i, tid, i+1, d_x[tid*lg+i+1]);
          		//finds DPs
  		  	if (d_x[tid*lg+i+1] % DP == 0) {
                   		 d_nDPaux[tid]=1;
                   		 d_DjX0[tid] = d_x0p[tid];
                   		 d_DjD[tid] = d_x[tid*lg+i+1];
                   		 d_Djsteps[tid] = i+1;
                   		 d_DjC[tid] = d_x[tid*lg+i];
                   		 //printf("DP found %d in indx %d \n", d_DjD[tid], tid);
                   		 break;
       			  }
  	  	}  			 
  	}
}



void FindIntermediateColl (int r, uint32_t DjX0i, uint32_t Djstepsi,
	uint32_t DjX0k, uint32_t Djstepsk, uint32_t* newDjC, uint32_t* newDjD, uint32_t MAXP){

	//printf("in %d steps from %d and %d steps from %d we reach %d \n", Djsteps[i], DjX0[i], Djsteps[k], DjX0[k], DjD[i]);
	int diff;
	int lim;
		 
	if (Djstepsi<Djstepsk){
		diff=Djstepsk-Djstepsi;
		lim=Djstepsi;
	}
	else{
		diff=Djstepsi-Djstepsk;
		lim=Djstepsk;
	}
  		 
	uint32_t *tempReach= (uint32_t*)malloc(sizeof(int)*(diff+1));
	uint32_t *tempShort= (uint32_t*)malloc(sizeof(int)*lim);
	uint32_t *tempLong=  (uint32_t*)malloc(sizeof(int)*lim);
		 
	if (Djstepsi<Djstepsk){
		tempShort[0]=DjX0i;
		tempReach[0]=DjX0k;
	}
	else{
		tempShort[0]=DjX0k;
		tempReach[0]=DjX0i;
                }

	for (int d=0; d<diff; d++) tempReach[d+1]=baseFunct(tempReach[d],r, MAXP);

	tempLong[0]=tempReach[diff];

	if (tempShort[0]!=tempLong[0]){
		//printf("%d and %d will collide on %d in %d steps \n", tempShort[0], tempLong[0], DjD[i], lim);
		for(int l=0; l<lim-1;l++){
			tempShort[l+1]=baseFunct(tempShort[l],r, MAXP);
			tempLong[l+1] =baseFunct(tempLong[l],r, MAXP);
			if (tempShort[l+1]==tempLong[l+1]){
				newDjC[0]=tempShort[l];
				newDjC[1]=tempLong[l];
				newDjD[0]=tempShort[l+1];
				newDjD[1]=tempLong[l+1];
				break;
			}
		}
		printf("intermediate collision between %d and %d on %d \n", newDjC[0], newDjC[1], newDjD[0]);
	}
	free(tempReach);
	free(tempShort);
	free(tempLong);
}


    
int main (int argc, char** argv) {

	TIMER_DEF;
	TIMER_START;
	
	//input validation
	if(argc != 3){
		fprintf(stderr,"wrong number of inputs\n");
		return EXIT_FAILURE;}
	
	int lg=atoi(argv[1]);
	
	if(lg <=0){
		fprintf(stderr,"[ERROR] - lg must be > 0\n");
		return EXIT_FAILURE;}
	
	int r=atoi(argv[2]);
	
	if(r <0){
		fprintf(stderr,"[ERROR] - r must be > 0\n");
	  	return EXIT_FAILURE;}
	
	//MPI initialization
	int rank, NP;
	MPI_Init(&argc, &argv);
	
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);
	MPI_Comm_size(MPI_COMM_WORLD, &NP);
	
	
	int n_per_proc; // elements per process
	n_per_proc=M/NP;
	
	if (rank==ROOT) printf("num start point per proc %d \n", n_per_proc);
	
	//each process selects a GPU to work on
	int usableGPUs;
	cudaErrorCheck(cudaGetDeviceCount(&usableGPUs),"cudaGetDevice");
	//if (usableGPUs>MAXNGPU) usableGPUs=MAXNGPU;
	
	if(NP>usableGPUs){
		fprintf(stderr,"[ERROR] - rerun with less than %d processes\n", usableGPUs);
	   	return EXIT_FAILURE; }
	
	cudaErrorCheck(cudaSetDevice(rank%MAXNGPU),"cudaSetDevice");
	
	int *x0glob=(int*)malloc(sizeof(int)*PRIME);
	if(x0glob==NULL){
		fprintf(stderr,"[ERROR] - Cannot allocate memory\n");
	   	return EXIT_FAILURE; }
	
	for (int i=0; i<M ; i++) x0glob[i]=0;
	
	//initialization global values and arrays
	int nCollisFinal=0;
	
	int *scA=(int*)malloc(sizeof(int)*M*(M-1)/2);
	if(scA==NULL){
		fprintf(stderr,"[ERROR] - Cannot allocate memory\n");
	  	return EXIT_FAILURE; }
	int *scB=(int*)malloc(sizeof(int)*M*(M-1)/2);

	for (int i=0; i<M*(M-1)/2 ; i++){
		scA[i]=0;
	  	scB[i]=0;}
	
	int nCovered=0;
	
	int nIter=0;
	int nMoot=0;
	
	while (nCollisFinal < 1){
		//generation and scattering of random starting points
	  	int nDPj=0;   
	  	 
	  	uint32_t *x0=(uint32_t*)malloc(sizeof(int)*M);
	
		if (x0==NULL) {
	  		fprintf(stderr,"[ERROR][RANK %d] Cannot allocate memory\n",rank);
	  		MPI_Abort(MPI_COMM_WORLD,1);}
	    
		if (rank == ROOT){
		for (int i = 0; i < NP*n_per_proc; i++){
	  		int a=1;
	  	  	while (a==1){
	  			x0[i]=rand()%PRIME;
	  			//printf("indx %d-  %d \n", i, x0[i]);
	  			int b=0;
	  		  	for(int k=0; k<i; k++){
	  		  	if (x0[i]==x0[k]){
	  				b++;
	  				break;
				}}
	  			if (b==0) a=0;
	  		}//WHILE
	  	  	int c=0;
	  		for(int k=0; k<nCovered; k++){
	  		if (x0[i]==x0glob[k]){
	  			c++;
	      			break;
			}}
	  		if (c==0){
	  			x0glob[nCovered]=x0[i];
	  			nCovered++;}
			}
		}//IFROOT
	
		uint32_t *x0p=(uint32_t*)malloc(sizeof(int)*n_per_proc);
	
	  	if(x0p==NULL){
	  		fprintf(stderr,"[ERROR] - Cannot allocate memory\n");
	  	  	return EXIT_FAILURE;
		}
	 
	  	MPI_Bcast(&nCovered,1, MPI_INT,ROOT,MPI_COMM_WORLD);
		MPI_Scatter(x0, n_per_proc, MPI_INT, x0p, n_per_proc, MPI_INT, ROOT, MPI_COMM_WORLD);
	  	MPI_Barrier(MPI_COMM_WORLD);
	    
		free(x0);
	  	 
		//allocation and initialization of device arrays
	  	uint32_t *d_x0p;
	  	cudaErrorCheck(cudaMalloc(&d_x0p,sizeof(int)*n_per_proc),"cudaMalloc d_x0p");
		cudaErrorCheck(cudaMemcpy(d_x0p,x0p,sizeof(int)*n_per_proc,cudaMemcpyHostToDevice),"Memcpy d_x0p");
	
	  	uint32_t *d_x;
	  	cudaErrorCheck(cudaMalloc(&(d_x), sizeof(int) * lg*n_per_proc),"cudaMalloc d_x");
	
	  	uint32_t *d_DjX0;
	  	uint32_t *d_DjD;
	  	uint32_t *d_Djsteps;
	  	uint32_t *d_DjC;
	  	int *d_nDPaux;
	
	  	cudaErrorCheck(cudaMalloc(&(d_DjX0), sizeof(int) *n_per_proc),"cudaMalloc d_DjX0");
	  	cudaErrorCheck(cudaMalloc(&(d_DjD), sizeof(int)*n_per_proc),"cudaMalloc d_DjD");
	  	cudaErrorCheck(cudaMalloc(&(d_Djsteps), sizeof(int) *n_per_proc),"cudaMalloc d_Djsteps");
	  	cudaErrorCheck(cudaMalloc(&(d_DjC), sizeof(int) *n_per_proc),"cudaMalloc d_DjC");
	  	cudaErrorCheck(cudaMalloc(&(d_nDPaux), sizeof(int)*n_per_proc),"cudaMalloc d_nDPaux");
	
		uint32_t *DjX0=(uint32_t*)malloc(sizeof(int)*n_per_proc);
	  	uint32_t *DjD=(uint32_t*)malloc(sizeof(int)*n_per_proc);
	  	uint32_t *Djsteps=(uint32_t*)malloc(sizeof(int)*n_per_proc);
	  	uint32_t *DjC=(uint32_t*)malloc(sizeof(int)*n_per_proc);
	  	int *nDPaux=(int*)malloc(sizeof(int)*n_per_proc);
	  		 
	
		//invocation of CUDA function
		int nthreads=MAX_THREAD;
	  	int nblocks=  n_per_proc/MAX_THREAD+1 ;
	  	 
	  	findPathAndDP<<<nblocks, nthreads>>>(d_x0p, d_x,lg, r, n_per_proc, d_DjX0, d_DjD, d_Djsteps, d_DjC, d_nDPaux, PRIME);
	                   			          		 
	
		//copies from device to host
	  	cudaErrorCheck(cudaMemcpy(DjX0, d_DjX0,sizeof(int)*n_per_proc, cudaMemcpyDeviceToHost), "Memcpy");
	  	cudaErrorCheck(cudaMemcpy(DjD, d_DjD,sizeof(int)*n_per_proc, cudaMemcpyDeviceToHost), "Memcpy");
	  	cudaErrorCheck(cudaMemcpy(Djsteps, d_Djsteps,sizeof(int)*n_per_proc, cudaMemcpyDeviceToHost), "Memcpy");
	  	cudaErrorCheck(cudaMemcpy(DjC, d_DjC,sizeof(int)*n_per_proc, cudaMemcpyDeviceToHost), "Memcpy");
	  	cudaErrorCheck(cudaMemcpy(nDPaux, d_nDPaux,sizeof(int)*n_per_proc, cudaMemcpyDeviceToHost), "Memcpy");
	
		//frees on device
		cudaFree(d_x0p);
		cudaFree(d_x);
	   	cudaFree(d_x0p);
	   	cudaFree(d_DjX0);
	   	cudaFree(d_DjD);
	   	cudaFree(d_Djsteps);
	   	cudaFree(d_DjC);
	   	cudaFree(d_nDPaux);
	
		//frees on host
		free(x0p);
	
		//calculates tot number of DP per process
	   	for (int i=0; i<n_per_proc; i++) nDPj+=nDPaux[i];
		//printf("rank %d - tot DPs found in iteration %d \n", rank, nDPj);
	    
		//flags processes that didn't find any DP
		int flag=0;
		if(nDPj==0 && rank!=ROOT) flag=1;
	    
		//finds collisins (per process)
		int nCollisj=0;
	  	uint32_t *CjA=(uint32_t*)malloc(sizeof(int)*n_per_proc*(n_per_proc-1)/2);
	  	uint32_t *CjB=(uint32_t*)malloc(sizeof(int)*n_per_proc*(n_per_proc-1)/2);
	
	  	int ncjaux=0;
	  	for (int i = 0; i < n_per_proc; i++){
	  	for (int k = i+1; k<n_per_proc; k++){
	  	if(DjD[i]==DjD[k]){
			if (DjC[i]==DjC[k]){
		  		uint32_t *newDjC=(uint32_t*)malloc(sizeof(int)*2);
		  		uint32_t *newDjD=(uint32_t*)malloc(sizeof(int)*2);
		  		 
		  		newDjC[0]=DjC[i];
		  		newDjC[1]=DjC[k];
		  		newDjD[0]=DjD[i];
		  		newDjD[1]=DjD[k];
		  		 
		  		FindIntermediateColl (r, DjX0[i], Djsteps[i],
		              				DjX0[k], Djsteps[k], newDjC, newDjD, PRIME);
		  		 
		  		DjC[i]=newDjC[0];
		  		DjC[k]=newDjC[1];
		  		DjD[i]=newDjD[0];
		  		DjD[k]=newDjD[1];
		  		 
		  		free(newDjC);
		  		free(newDjD);
		  	}
	  	 
	  		if (DjC[i]!=DjC[k]){
				printf("rank %d collision between %d and %d on %d on indx %d \n", rank, DjC[i], DjC[k], DjD[i], i);
				if (DjC[i]<DjC[k]){
					CjA[ncjaux]=DjC[i];
					CjB[ncjaux]=DjC[k];}
				else{
					CjA[ncjaux]=DjC[k];
					CjB[ncjaux]=DjC[i];}
				ncjaux++;
			}
	  	}}}
	
		if ( ncjaux!=0) printf("rank %d - no of collisions %d \n" , rank, ncjaux);    
		
		//eliminates duplicates (per process)
		uint32_t *scjA=(uint32_t*)malloc(sizeof(int)*n_per_proc*(n_per_proc-1)/2);
		uint32_t *scjB=(uint32_t*)malloc(sizeof(int)*n_per_proc*(n_per_proc-1)/2);
		
		for (int i=0; i<n_per_proc*(n_per_proc-1)/2 ; i++){
			  scjA[i]=0;
			  scjB[i]=0;}
		
		if (ncjaux>0){
			nCollisj=1;
			scjA[0]=CjA[0];
			scjB[0]=CjB[0];
			printf("rank %d -first collis %d and %d \n", rank, scjA[0], scjB[0]);
		
			for (int i = 1; i < ncjaux; i++){
			  	int a=0;
				for (int k = 0; k<i; k++){
				if(CjA[i]==CjA[k] && CjB[i]==CjB[k]){
					a++;
					break;
				}}
		          	
				if (a==0){
					  scjA[nCollisj]=CjA[i];
					  scjB[nCollisj]=CjB[i];
					  printf("rank %d -collis bw %d and %d \n", rank, scjA[nCollisj], scjB[nCollisj]);
					  nCollisj++;
				}
			}
			printf("rank %d -no of unique collisions in iteration %d \n" , rank, nCollisj);
		}
		
		int nCollisT=0;     
	    
		//each process shares with root number of collisions found and related information
		MPI_Barrier(MPI_COMM_WORLD);
		MPI_Reduce(&nCollisj, &nCollisT, 1, MPI_INT, MPI_SUM, ROOT, MPI_COMM_WORLD);
	    
		if (rank==ROOT) printf("reduce success %d \n", nCollisT);
	
	
		uint32_t *CA=(uint32_t*)malloc(sizeof(int)*M*(n_per_proc-1)/2);
	   	uint32_t *CB =(uint32_t*)malloc(sizeof(int)*M*(n_per_proc-1)/2);
	
		if (CA==NULL) {
	   		fprintf(stderr,"[ERROR][RANK %d] Cannot allocate memory\n",rank);
	   	 	MPI_Abort(MPI_COMM_WORLD,1);}
	    
		for (int i=0; i<M*(n_per_proc-1)/2 ; i++){
	   		CA[i]=0;
	   	 	CB[i]=0;}
	    
		MPI_Gather(scjA, n_per_proc*(n_per_proc-1)/2, MPI_INT, CA, n_per_proc*(n_per_proc-1)/2, MPI_INT, ROOT, MPI_COMM_WORLD);
		MPI_Gather(scjB, n_per_proc*(n_per_proc-1)/2, MPI_INT, CB, n_per_proc*(n_per_proc-1)/2, MPI_INT, ROOT, MPI_COMM_WORLD);
	
		//each process shares with root the number of DPs found
	
		int nDP=0;
		uint32_t *DX0=(uint32_t*)malloc(sizeof(int)*M);
	   	uint32_t *DD =(uint32_t*)malloc(sizeof(int)*M);
	   	uint32_t *Dsteps =(uint32_t*)malloc(sizeof(int)*M);
		uint32_t *DC =(uint32_t*)malloc(sizeof(int)*M);
	    
		for (int i=0; i<M ; i++){
			DX0[i]=0;
		   	DD[i]=0;
			Dsteps[i]=0;
			DC[i]=0;}
	    
		MPI_Reduce(&nDPj, &nDP, 1, MPI_INT, MPI_SUM, ROOT, MPI_COMM_WORLD);
		MPI_Barrier(MPI_COMM_WORLD);
	
		int key;    
		if (flag==0) key= rank;
		else key=NP-rank;
	
		// Split the global communicator
	  	MPI_Comm new_comm;
	  	MPI_Comm_split(MPI_COMM_WORLD, flag, key, &new_comm);
	
		//each process that found DPs>0 shares with root the related information
		MPI_Gather(DjX0, n_per_proc, MPI_INT, DX0, n_per_proc, MPI_INT, ROOT, new_comm);
		MPI_Gather(DjD, n_per_proc, MPI_INT, DD, n_per_proc, MPI_INT, ROOT, new_comm);
		MPI_Gather(Djsteps, n_per_proc, MPI_INT, Dsteps, n_per_proc, MPI_INT, ROOT, new_comm);
		MPI_Gather(DjC, n_per_proc, MPI_INT, DC , n_per_proc, MPI_INT, ROOT, new_comm);
		MPI_Comm_free(&new_comm);
	
		MPI_Barrier(MPI_COMM_WORLD);
	
		//frees on device    
	  	free(DjX0);
	  	free(DjD);
	  	free(Djsteps);
	  	free(DjC);
	  	free(scjA);
	  	free(scjB);
	
	    
		int nCollisTot=0;
	
		//eliminates duplicates (globally)
		if(rank==ROOT){
			printf("Cumulative Collis till now %d \n", nCollisFinal);
		
			if (nCollisT>0){
			  	for (int i = 0; i < M*(n_per_proc-1)/2; i++){
			  		int a=0;
			  		int b=0;
			  		if (CB[i]!=0){
			      			for (int k = 0; k<i; k++){
			          		if(CA[i]==CA[k] && CB[i]==CB[k]){
			                  		a++;
			                  		break;
						}}
			          		//printf( "a= %d on indx %d \n", a, i);
			  		if (a==0){
			                  	for (int h = 0;h<nCollisFinal+1;h++){
			                  	if(CA[i]==scA[h] && CB[i]==scB[h]){
							b++;
			                          	break;
						}}
			                  	if (b==0){
							scA[nCollisFinal+nCollisTot]=CA[i];
							scB[nCollisFinal+nCollisTot]=CB[i];
							printf("new Collis bw %d and %d on indx %d \n", scA[nCollisFinal+nCollisTot],
					  scB[nCollisFinal+nCollisTot], i);
			                          	nCollisTot++;}
			  		  	} 	 
			  		}
				}
			  	printf("nSingleRank of this iteration %d \n", nCollisTot);
		  	}
		    
			//looks for new "interrank" collsions
			int nCollisIr=0;
			int nCollisIrT=0;
			uint32_t *tempA=(uint32_t*)malloc(sizeof(int)*M*n_per_proc*(NP-1)/2);
		   	uint32_t *tempB =(uint32_t*)malloc(sizeof(int)*M*n_per_proc*(NP-1)/2);
		
			for (int i = 0; i <M; i++){
			if (DC[i]==0 && DD[i]!=1) break;
			for (int k =n_per_proc+i/(n_per_proc); k<M; k++){
				int a=1;
				int b=1;
			  	 
			  	if(DC[k]==0 && DD[k]!=1) break;
			  	if(DD[i]==DD[k]){
		  			a=0;
		  			b=0;
				}
		
		  	  	if (a==0){
			  		if (DC[i]==DC[k]){
						  uint32_t *newDjC=(uint32_t*)malloc(sizeof(int)*2);
						  uint32_t *newDjD=(uint32_t*)malloc(sizeof(int)*2);
			
						  newDjC[0]=DC[i];
						  newDjC[1]=DC[k];
						  newDjD[0]=DD[i];
						  newDjD[1]=DD[k];
			
						  FindIntermediateColl (r, DX0[i], Dsteps[i],
							 DX0[k], Dsteps[k], newDjC, newDjD, PRIME);
			
						  DC[i]=newDjC[0];
						  DC[k]=newDjC[1];
						  DD[i]=newDjD[0];
						  DD[k]=newDjD[1];
			
						  free(newDjC);
						  free(newDjD);
			  		}
		  			 
			  		if (DC[i]!=DC[k]){
			  			for (int h = 0;h<nCollisFinal+nCollisTot+1;h++){
			              		if((DC[i]==scA[h] && DC[k]==scB[h]) || (DC[i]==scB[h] && DC[k]==scA[h])){
			                      		b++;
			                      		break;
						}}
			              		if (b==0){
			  				if (DC[i]<DC[k]){
			  					tempA[nCollisIrT]=DC[i];
			  					tempB[nCollisIrT]=DC[k];}
			  				  else{
			  					tempA[nCollisIrT]=DC[k];
			  					tempB[nCollisIrT]=DC[i];}
			  				  //printf("new interrank %d and %d Collis bw %d and %d on %d \n", i, k, tempA[nCollisIrT], tempB[nCollisIrT], DD[i]);
			  				  nCollisIrT++;
		  			  	}
		          		}
		  	  	}//a=0
			}}
		
			//eliminates duplicates between new collisions
			if (nCollisIrT>0){
			  	nCollisIr=1;
				scA[nCollisFinal+nCollisTot]=tempA[0];    
				scB[nCollisFinal+nCollisTot]=tempB[0];
			    	printf("first interrank collis bw %d and %d \n", scA[nCollisFinal+nCollisTot], scB[nCollisFinal+nCollisTot]);
		
		       		for (int i = 1; i < nCollisIrT; i++){
		       			int a=0;
		               		for (int k = 0; k<i; k++){
		               		if(tempA[i]==tempA[k] && tempB[i]==tempB[k]){
		                       		a++;
		                       		break;
					}}
		               		if (a==0){
		                       		scA[nCollisFinal+nCollisTot+nCollisIr]=tempA[i];
		                       		scB[nCollisFinal+nCollisTot+nCollisIr]=tempB[i];
		                       		printf("interrank collis bw %d and %d \n", scA[nCollisFinal+nCollisTot+nCollisIr], scB[nCollisFinal+nCollisTot+nCollisIr]);
		                       		nCollisIr++;
					}
		       		 }
			}
		
			//frees on device
			free(tempA);
			free(tempB);
		
			nCollisTot=nCollisTot+nCollisIr;
			printf("nTot of this iteration %d \n", nCollisTot);
		} //ROOT
	
		MPI_Barrier(MPI_COMM_WORLD);
	    
		//each process is updated on the number of collisions found in this iteration
	   	MPI_Bcast(&nCollisTot,1, MPI_INT,ROOT,MPI_COMM_WORLD);
	    
		free(DX0);
	   	free(DD);
	   	free(Dsteps);
	   	free(DC);
	    
		free(CA);
	  	free(CB);
	    
		if (nCollisTot==0) nMoot++;
		else nMoot=0;
	
		if (nMoot>=200){
	  		MPI_Bcast(&nMoot,1, MPI_INT,ROOT,MPI_COMM_WORLD);
	  		MPI_Barrier(MPI_COMM_WORLD);
	  	  	if (rank ==ROOT) printf("no new Collision have been found for %d iterations, the required number of Collisions migth be too high \n", nMoot);
	  	  	break;
		}
	    
		nCollisFinal= nCollisFinal+nCollisTot;
	  	MPI_Bcast(&nCollisFinal,1, MPI_INT,ROOT,MPI_COMM_WORLD);
		MPI_Barrier(MPI_COMM_WORLD);
		if (rank==ROOT) printf("nFin %d \n", nCollisFinal);
		nIter++;
	
		/*if (nCovered>=PRIME){
	       		//MPI_Bcast(&nCovered,1, MPI_INT,ROOT,MPI_COMM_WORLD);
	       		MPI_Barrier(MPI_COMM_WORLD);
	       		if (rank==ROOT) printf(" %d points searched, the required number of Collisions migth be too high \n", nCovered);
	       		break;
		}*/
	
	}//WHILE

	//for last iteration
	MPI_Barrier(MPI_COMM_WORLD);
	MPI_Bcast(&nCollisFinal,1, MPI_INT,ROOT,MPI_COMM_WORLD);
	if (rank==ROOT) {
		printf("nDef reached %d \n", nCollisFinal);
		for (int i=0; i<nCollisFinal; i++) printf ("%d and %d \n", scA[i], scB[i]);
	}
	
	MPI_Barrier(MPI_COMM_WORLD);
	TIMER_STOP;
	
	//save in csv subroutine
	if (rank==ROOT) {
	    
	   	/* uint32_t triala102 =baseFunct(67835,2, PRIME);
		uint32_t trialb102 =baseFunct(8309185,2, PRIME);
		printf("coll on %d & %d \n", triala102, trialb102);
		uint32_t triala103 =baseFunct(171518,3, PRIME);
		uint32_t trialb103 =baseFunct(8089679,3, PRIME);
		printf("coll on %d & %d \n", triala103, trialb103);
		printf("in %d iterations %d points in the set have been searched \n", nIter, nCovered);*/
	
		printf("running time: %f microseconds\n",TIMER_ELAPSED);
		printf("Do you want to save the ouput in a csv? (0=no/1=yes) \n");
	
		int answ;
		scanf("%d", &answ);
		if(answ==1){
		  	FILE *fp;
		  	char filename[100];
		  	printf("Type file name \n ");
		  	//gets(filename);
		  	scanf("%99s", filename);
		  	strcat(filename,".csv");
		  	fp=fopen(filename,"w+");
		  	for(int i = 0; i<nCollisFinal; i++) fprintf(fp,"\n %d,%d", scA[i], scB[i]);
		  	fclose(fp);
		}    
	}//ROOT
	
	//frees on device
	free(scA);
	free(scB);
	free(x0glob);
	
	MPI_Finalize();
	return 0;
}


