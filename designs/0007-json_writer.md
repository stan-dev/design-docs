- Feature Name: JSON output for Cmdstan
- Start Date: 2019-12-27
- RFC PR: (leave this empty)
- Stan Issue: (leave this empty)

# Summary
[summary]: #summary

I would like to propose adding JSON as an output option for Cmdstan, complementing the existing CSV output. This started as an [issue on Cmdstan](https://github.com/stan-dev/cmdstan/issues/789) but as this topic requires a more general agreement and approval the issue is now elevated to a design doc.

# Motivation
[motivation]: #motivation
There are a couple of reasons for doing this: 
- this would simplify the Cmdstan-CmdstanPy, Cmdstan-CmdstanR communication
- simplify handling of sampling results and metadata in other programming languages
- it would also simplify some use cases mentioned by @maedoc in [this issue](https://github.com/stan-dev/cmdstan/issues/511#issuecomment-565356551): 
	- restarts of Cmdstan models (for when a model takes longer than a given time limit on a cluster),
	- simulating data and then fitting a model to its data
	- multiple model workflow
	- intializing HMC from an optimization
- preliminary results show that JSON output is also slightly faster in some cases (see below)

# Guide-level explanation
[guide-level-explanation]: #guide-level-explanation

The main change would be that instead of only allowing csv output for Cmdstan ([example](https://raw.githubusercontent.com/stan-dev/cmdstan/develop/src/test/interface/example_output/eight_schools_output.csv)) we would also have the option of a JSON ouput. An example output would look similar to the example below:
```JSON
{
"meta": {
    "stan_version_major": 2,
    "stan_version_minor": 21,
    "stan_version_patch": 0,
    "model": "eight_schools_model",
    "method": "sample",
    "sample": {
        "num_samples": 10,
        "num_warmup": 1000,
        "save_warmup": 0,
        "thin": 1,
        "adapt":{
            "engaged": 1,
            "gamma": 0.050000000000000003,
            "delta": 0.80000000000000004,
            "kappa": 0.75,
            "t0": 10,
            "init_buffer": 75,
            "term_buffer": 50,
            "window": 25
        }
    }    
},
"step_size": 0.372621,
"inverse_mass_matrix_diag": [18.2285, 1.21924, 0.780185, 0.875131, 0.921772, 0.878005, 0.770609, 0.827646, 0.731635, 0.713899, 0.900615, 0.754151],
"samples":[[-51.044778,0.962712,0.37262,4.0,15.0,0.0,60.34343,11.304475,2.554103,-0.369945,-1.208247,-0.074997,0.867542,0.804843,-1.09118,-1.502441,-0.386866,-1.408202,0.207749,10.359596,8.218486,11.112924,13.520268,13.360128,8.517489,7.467084,10.316379,7.707781,11.835088],[-52.864594,0.84787,0.37262,3.0,15.0,0.0,59.504754,5.789448,0.370447,0.042525,-0.369192,-0.14859,-1.221288,-0.309616,-0.875135,-0.215068,1.375747,-2.241982,0.505575,5.805201,5.652681,5.734403,5.337025,5.674751,5.465256,5.709776,6.299089,4.958912,5.976736],[-52.617135,0.916438,0.37262,4.0,15.0,0.0,60.022217,8.755569,0.473294,1.049158,0.485332,-1.183938,1.728922,0.521784,-0.983077,1.422458,-0.363141,1.104313,0.740966,9.25213,8.985274,8.195218,9.573858,9.002527,8.290284,9.428811,8.583696,9.278235,9.106264],[-56.64873,0.828951,0.37262,2.0,7.0,0.0,60.040686,15.478846,0.379333,0.538912,-0.006475,-2.116285,1.562337,0.431793,-1.403904,1.046636,-0.575158,1.294478,1.623317,15.683273,15.476389,14.676068,16.071492,15.642639,14.946298,15.87587,15.260669,15.969885,16.094624],[-48.92103,0.318818,0.37262,4.0,15.0,0.0,65.581008,10.445837,2.136365,0.261096,1.208946,-0.539443,0.033684,0.03858,-0.283,0.35481,-1.177642,1.607905,0.750019,11.003635,13.028589,9.293387,10.517798,10.528259,9.841243,11.203841,7.929962,13.880912,12.048152],[-47.454484,1.0,0.37262,3.0,7.0,0.0,53.285885,6.43741,4.494301,1.440751,-0.143511,0.187546,0.226508,-0.645326,0.036783,0.990114,1.648384,-0.179351,-0.254901,12.912583,5.792424,7.2803,7.455409,3.537116,6.602726,10.887285,13.845745,5.63135,5.291806],[-48.093197,0.947498,0.37262,4.0,15.0,0.0,54.316045,9.039139,6.876012,-0.354503,-0.005195,-1.037007,0.06226,0.169926,0.836055,-0.536622,-1.369424,0.980715,0.330869,6.601566,9.003415,1.908665,9.467244,10.207553,14.787865,5.349314,-0.377043,15.782549,11.3142],[-46.536515,0.994792,0.37262,4.0,15.0,0.0,52.108556,8.749221,6.750503,0.395675,-0.169556,0.421857,-0.275193,-0.565822,-0.976979,0.95275,1.437867,-0.53873,-0.361132,11.420231,7.604628,11.596972,6.891527,4.929632,2.154119,15.180765,18.455552,5.11252,6.311393],[-46.140776,0.960326,0.37262,3.0,15.0,0.0,50.120721,10.701512,9.488804,0.849441,-0.312036,-1.669781,-0.212627,-0.235502,-1.058349,0.034213,-0.225973,0.890451,0.878977,18.761701,7.740656,-5.142714,8.683931,8.466877,0.659043,11.026155,8.55729,19.150836,19.041961],[-53.644293,0.626838,0.37262,4.0,15.0,0.0,59.601769,7.882549,0.421829,-0.294862,-0.189965,-0.006145,-0.42955,-0.552286,2.84409,-0.446171,-1.276383,0.909832,-0.934817,7.758167,7.802416,7.879956,7.701352,7.649578,9.082271,7.69434,7.344132,8.266343,7.488215]]
}
```

# Reference-level explanation
[reference-level-explanation]: #reference-level-explanation

The JSON


The main
# Drawbacks
[drawbacks]: #drawbacks

As this will be an optional feature I dont see any real drawbacks, except for additional code to maintain.

# Rationale and alternatives
[rationale-and-alternatives]: #rationale-and-alternatives

The alternative to this approach would be going with a binary format directly. I see the binary output format as the next step after we refactor things to facilitate the JSON format.
The other obvious alternative would be staying with csv only, but a need for a faster and more machine-friendly format has been expressed many times. JSON is primarily the latter, while binary is both.

# Unresolved questions
[unresolved-questions]: #unresolved-questions

- Argument naming. The arguments I am proposing here are far from final, I am usually bad with names.
- Which formats to support for Inf and NaN? Which one should be default?