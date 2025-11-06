function mpc = case5
%CASE5  Power flow data for modified 5 bus, 5 gen case based on PJM 5-bus system
%   Please see CASEFORMAT for details on the case file format.
%
%   Based on data from ...
%     F.Li and R.Bo, "Small Test Systems for Power System Economic Studies",
%     Proceedings of the 2010 IEEE Power & Energy Society General Meeting
%
%   Created by Rui Bo in 2006, modified in 2010, 2014.
%   Distributed with permission.
%
%   MATPOWER

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	2	    0	    0	0	0	1	1	0	330	1	1.05	0.95;
	2	3	 8309.4		0	0	0	1	1	0	330	1	1.05	0.95;
	3	1	 5106.1		0	0	0	1	1	0	330	1	1.05	0.95;
	4	1	 1642.9		0	0	0	1	1	0	330	1	1.05	0.95;
	5	1	 5002.7		0	0	0	1	1	0	330	1	1.05	0.95;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	    0	    0	  1e6	 -1e6	1	100	1	12500	    0	0	0	0	0	0	0	0	0	0	0	0;
	1	 9567.1		0	  1e6	 -1e6	1	100	1	15000	    0	0	0	0	0	0	0	0	0	0	0	0;
	2	 9000		0	  1e6	 -1e6	1	100	1	18000	 9000	0	0	0	0	0	0	0	0	0	0	0;
	4	 3500		0	  1e6	 -1e6	1	100	1	15000	 3500	0	0	0	0	0	0	0	0	0	0	0;
];

%% branch data
%	fbus	tbus	r	    x	    b	    rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	1	3	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	2	3	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	2	4	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	2	5	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	3	4	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
	4	5	8.4e-05	8.4e-05	0	    Inf	Inf	Inf	1	0	1	-0.6109	0.6109;
];

%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [
	2	0	        0	        3	0.0001	0	1;
	2	0	        0	        3	0.0001	0	1;
	2	300000	    30000	    3	0.0001	20	18000;
	2	250000	    0	        3	0.0001	100	18000;
];