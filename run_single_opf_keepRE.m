function mpc = run_single_opf_keepRE(cfgFile, solutionCsv, busXlsx, hIdx)
% RUN_SINGLE_OPF_KEEPRE  Build a MATPOWER case for one hour 
%                        
%
%   mpc = run_single_opf_keepRE('config.json','solution.csv',...
%                               '5bus_New.xlsx', 13)
%
%
%   1)  Extract data from bus file of MAST
%   2)  Finds the no of hours that MAST takes to run and extracts 
%       the values from the demand trace to make it into a matrix
%   3)  Extracts the dispatch and commitment variables
%       Dispatch Variables - Active Power(Pg) and Reactive Power(Qg)
%       Commitment Variables -  status_var_gen_name
%   4)  Full MPC for debugging 
%    
%   Functions Required 
%   1.build_mpc_from_excel_keepRE(busXlsx) - Extracts required variables from the 5
%   bus file 
%   2.extract_demand_window(cfgFile, busXlsx) - Makes the demand matrix per hour in ascending
%   order 
%   3.get_demand_info (located in extract_demand_window) - Helps to find
%   specific columns
%   4.read_mast_dispatch(solutionCsv) - Finds the dispatch and commitment variables in
%   the solution file provided by MAST 
%   5.check_hourcase(mpc, commitRow, dispRow, hIdx); - Modifies the MPC file for a specific hour

%% 1) —————————————————  build MPC  
mpc = build_mpc_from_excel_keepRE(busXlsx);            

%% 2) —————————————————  demand for the selected hour
D      = extract_demand_window(cfgFile, busXlsx);
Nt  = size(D.values, 2);
assert(hIdx>=1 && hIdx<=Nt, 'hour index must be 1 … %d', Nt);
define_constants;
mpc.bus(:, PD) = D.values(:, hIdx);                   

%% 3) —————————————————  commitment & dispatch rows
[tDisp, tCommit] = read_mast_dispatch(solutionCsv);
commitRow = tCommit(hIdx, :);      % *_On …
dispRow   = tDisp  (hIdx, :);      % *_Pg / *_Qg …

mpc = check_hourcase(mpc, commitRow, dispRow, hIdx);
auto_assign_bus_types(mpc, hIdx)
mpc = auto_assign_bus_types(mpc, hIdx);

%% 4) —————————————————  DEBUG PRINT 
fprintf('\n============= FULL MPC  (hour %d) =============\n', hIdx);

bhdr = {'BUS_I','BUS_TYPE','PD','QD','GS','BS','BUS_AREA',...
        'VM','VA','BASE_KV','ZONE','VMAX','VMIN'};
disp('--- BUS --------------------------------------------------------------')
disp(array2table(mpc.bus, 'VariableNames', bhdr))

if isfield(mpc,'branch') && ~isempty(mpc.branch)
    bchdr = {'F_BUS','T_BUS','BR_R','BR_X','BR_B','RATE_A','RATE_B','RATE_C',...
             'TAP','SHIFT','BR_STATUS','ANGMIN','ANGMAX'};
    disp('--- BRANCH -----------------------------------------------------------')
    disp(array2table(mpc.branch, 'VariableNames', bchdr))
end

baseHdr = {'GEN_BUS','PG','QG','QMAX','QMIN','VG','MBASE','GEN_STATUS',...
           'PMAX','PMIN','PC1','PC2','QC1MIN','QC1MAX','QC2MIN','QC2MAX',...
           'RAMP_AGC','RAMP_10','RAMP_30','RAMP_Q','APF'};
nGcol = size(mpc.gen,2);
for k = numel(baseHdr)+1 : nGcol, baseHdr{k}=sprintf('COL_%d',k); end
disp('--- GEN ----------------------------------------------------------------')
disp(array2table(mpc.gen, 'VariableNames', baseHdr(1:nGcol)))


chdr = {'MODEL','STARTUP','SHUTDOWN','NCOST','C2','C1','C0'};
nc  = size(mpc.gencost, 2);          
for k = numel(chdr)+1 : nc           
    chdr{k} = sprintf('COL_%d', k);
end

disp('--- GENCOST -----------------------------------------------------------')
disp(array2table(mpc.gencost, 'VariableNames', chdr(1:nc)))


%% 5) Running of Power flow

% runpf(mpc);
% runopf(mpc);

end

