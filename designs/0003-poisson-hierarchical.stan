functions {
  // runs reduce over the index range start to end. Mapping from
  // data-index set to group indices pre-stored in gidx
  real hierarchical_reduce(int start, int end, int[] y, vector log_lambda_group, int[] gidx) {
    return poisson_log_lpmf(y[start:end]| log_lambda_group[gidx[start:end]]);   
  }

  // function defined in C++ which calls parallel_reduce_sum with a
  // lambda functor which simply binds the arguments passed into it
  real parallel_hierarchical_reduce(int[] y, vector log_lambda_group, int[] gidx, int grainsize);

  // map-rect alterantive
  vector mr_reduce(vector beta, vector log_lambda, real[] xr, int[] xi) {
    real lp = poisson_log_lpmf(xi| log_lambda[1]);
    return [lp]';
  }
  
  real hierarchical_map(int g, vector log_lambda, int[,] yg) {
    real lp = poisson_log_lpmf(yg[g]| log_lambda[g]);
    return lp;
  }
  
  // parallel_map TBB based alternative
  real[] parallel_hierarchical_map(int[] group, vector log_lambda, int[,] yg);
}
data {
  int<lower=0> N;
  int<lower=0> G;
  int<lower=0> grainsize;
  int<lower=0,upper=3> method;
}
transformed data {
  real true_log_lambda = log(5.0); 
  real true_tau = log(10)/1.96;
  int y[N*G];
  int yg[G,N];
  real xr[G,0];
  int gidx[N*G]; 
  int start[G];
  int end[G];
  int group[G];
  vector[0] theta_dummy;

  print("Simulating problem size: G = ", G, "; N = ", N);
  if (method == 0) {
    print("Using parallel reduce TBB with grainsize = ", grainsize);
    reject("TBB reduce not supported");
  } else if (method == 1) {
    print("Using parallel map TBB");
    reject("TBB map not supported");
  } else if (method == 2) {
    print("Using map_rect.");
  } else if (method == 3) {
    print("Using serial evaluation only.");
  }

  for(g in 1:G) {
    real lambda_group = lognormal_rng(true_log_lambda, true_tau);
    int elem = 1;
    group[g] = g;
    start[g] = (g-1) * N + 1;
    end[g] = g * N;
    for(i in start[g]:end[g]) {
      y[i] = poisson_rng(lambda_group);
      yg[g,elem] = y[i];
      gidx[i] = g;
      elem += 1; 
    }
  }

  print("Model data initialized.");
  print("My lucky number: ", y[1]);
}
parameters { 
  real log_lambda;
  real<lower=0> tau; 
  vector[G] eta;
}
model {
  vector[G] log_lambda_group = log_lambda + eta * tau;
  real lpmf = 0;

  if (method == 0) {
    lpmf = parallel_hierarchical_reduce(y, log_lambda_group, gidx, grainsize);
  } else if (method == 1) {
    lpmf = sum(parallel_hierarchical_map(group, log_lambda_group, yg));
  } else if (method == 2) {
      vector[1] log_lambda_group_tilde[G];
      for(g in 1:G)
        log_lambda_group_tilde[g,1] = log_lambda_group[g];
      lpmf = sum(map_rect(mr_reduce, theta_dummy, log_lambda_group_tilde, xr, yg));
  } else if (method == 3) {
      lpmf = poisson_log_lpmf(y| log_lambda_group[gidx]);
  }

  target += lpmf;
  target += std_normal_lpdf(log_lambda);
  target += std_normal_lpdf(tau);
  target += std_normal_lpdf(eta);
}
generated quantities {
  real msq_log_lambda = square(true_log_lambda - log_lambda);
  real msq_tau = square(true_tau - tau);
}
